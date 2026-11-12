import Foundation
import Testing
@testable import Fallow

/// Answers requests from a closure, so the client can be tested without a network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            request.httpBody = data
        }
        Self.seen.append(request)
        let (status, body) = Self.handler?(request) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct CoachTests {
    let config = CoachConfig(region: "eu-central-1", clientID: "client123", graphQLURL: URL(string: "https://example.appsync-api.eu-central-1.amazonaws.com/graphql")!)

    func client(_ store: MemoryCoachSessionStore = MemoryCoachSessionStore()) -> CoachClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        StubProtocol.seen = []
        return CoachClient(config: config, store: store, session: URLSession(configuration: configuration))
    }

    func json(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    @Test func signsInWithPasswordAndKeepsOnlyTheTokens() async throws {
        let store = MemoryCoachSessionStore()
        StubProtocol.handler = { _ in (200, #"{"AuthenticationResult":{"IdToken":"id-1","RefreshToken":"refresh-1","ExpiresIn":3600}}"#) }
        try await client(store).signIn(email: "  Lori@Example.com ", password: "secret")

        let sent = try #require(StubProtocol.seen.first)
        #expect(sent.url?.host == "cognito-idp.eu-central-1.amazonaws.com")
        #expect(sent.value(forHTTPHeaderField: "X-Amz-Target") == "AWSCognitoIdentityProviderService.InitiateAuth")
        let body = json(sent)
        #expect(body["AuthFlow"] as? String == "USER_PASSWORD_AUTH")
        #expect((body["AuthParameters"] as? [String: String])?["USERNAME"] == "lori@example.com")

        let session = try #require(store.load())
        #expect(session.email == "lori@example.com")
        #expect(session.refreshToken == "refresh-1")
        #expect(!String(describing: session).contains("secret"))
    }

    @Test func explainsWrongPasswordAndTemporaryPassword() async {
        StubProtocol.handler = { _ in (400, #"{"__type":"NotAuthorizedException","message":"Incorrect username or password."}"#) }
        await #expect(throws: CoachError.wrongPassword) { try await client().signIn(email: "a@b.c", password: "x") }
        StubProtocol.handler = { _ in (200, #"{"ChallengeName":"NEW_PASSWORD_REQUIRED","Session":"s"}"#) }
        await #expect(throws: CoachError.newPasswordRequired) { try await client().signIn(email: "a@b.c", password: "x") }
    }

    @Test func chatRefreshesTheTokenAndSendsFallowInput() async throws {
        let store = MemoryCoachSessionStore(CoachSession(email: "a@b.c", refreshToken: "refresh-1"))
        StubProtocol.handler = { request in
            if request.url?.host?.hasPrefix("cognito-idp") == true {
                return (200, #"{"AuthenticationResult":{"IdToken":"id-2","ExpiresIn":3600}}"#)
            }
            return (200, #"{"data":{"mindCoach":"{\"kind\":\"chat\",\"text\":\"Hello, Lori.\"}"}}"#)
        }
        let messages = [CoachState.Message(role: .user, text: "Hi")]
        let answer = try await client(store).chat(messages, note: "Likes walks", context: "Intention: rest", english: true)
        #expect(answer == "Hello, Lori.")

        #expect(StubProtocol.seen.count == 2)
        #expect(json(StubProtocol.seen[0])["AuthFlow"] as? String == "REFRESH_TOKEN_AUTH")
        let graph = StubProtocol.seen[1]
        #expect(graph.value(forHTTPHeaderField: "Authorization") == "id-2")
        let input = try #require((json(graph)["variables"] as? [String: String])?["input"])
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])
        #expect(parsed["app"] as? String == "fallow")
        #expect(parsed["lang"] as? String == "en")
        #expect(parsed["kind"] as? String == "chat")
        #expect(parsed["note"] as? String == "Likes walks")
        #expect(store.load()?.idToken == "id-2")
    }

    @Test func serverErrorsAndExpiredSessions() async throws {
        let store = MemoryCoachSessionStore(CoachSession(email: "a@b.c", refreshToken: "r", idToken: "id", expiresAt: .now.addingTimeInterval(3600)))
        StubProtocol.handler = { _ in (200, #"{"data":{"mindCoach":null},"errors":[{"message":"Monthly limit reached."}]}"#) }
        await #expect(throws: CoachError.server("Monthly limit reached.")) {
            try await client(store).chat([.init(role: .user, text: "Hi")], note: "", context: "", english: true)
        }
        StubProtocol.handler = { _ in (401, #"{"errors":[{"errorType":"UnauthorizedException"}]}"#) }
        await #expect(throws: CoachError.signedOut) {
            try await client(store).chat([.init(role: .user, text: "Hi")], note: "", context: "", english: true)
        }
        #expect(store.load() == nil)
    }

    @Test func notConfiguredMeansNoCalls() async {
        let c = CoachClient(config: nil, store: MemoryCoachSessionStore())
        #expect(!c.isConfigured)
        await #expect(throws: CoachError.notConfigured) { try await c.signIn(email: "a@b.c", password: "x") }
    }
}

struct CoachStateTests {
    @Test func contextNeverIncludesTheJournal() {
        var c = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(.current())
        plan.intention = "Slow mornings"
        plan.success = "Up before 7"
        c.save(plan)
        c.save(Note(date: DayKey.string(.now), month: .current(), kind: .free, text: "very private"))

        #expect(c.coachContext(.chat, english: true).isEmpty)
        let intention = c.coachContext(.intention, english: true)
        #expect(intention.contains("Slow mornings"))
        #expect(intention.contains("Up before 7"))
        #expect(!intention.contains("very private"))
        #expect(c.coachContext(.month, english: false).contains("Vineri cu exercițiul făcut"))
    }

    @Test func keepsTheLast300Messages() {
        var state = CoachState()
        for i in 0..<310 { state.append(.init(role: .user, text: "\(i)")) }
        #expect(state.messages.count == CoachState.keep)
        #expect(state.messages.first?.text == "10")
    }

    @Test func firstMessageBringsTheBellflower() {
        var c = VaultContents(createdAt: .now, settings: VaultSettings())
        c.checkHerbarium(visit: true)
        var coach = CoachState()
        coach.append(.init(role: .user, text: "Hi", at: .now.addingTimeInterval(5)))
        c.coach = coach
        #expect(c.checkHerbarium(now: .now.addingTimeInterval(10)).contains("claude"))
    }
}
