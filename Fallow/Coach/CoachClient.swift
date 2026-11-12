import Foundation
import Security

/// Where Claude lives for now: Răgaz's mind-coach function in the Kitchen Tales backend, reached
/// with the person's Kitchen Tales account (Cognito email + password, then refresh tokens).
/// These identifiers are not secret: the Kitchen Tales web app ships them too.
struct CoachConfig: Sendable, Equatable {
    var region: String
    var clientID: String
    var graphQLURL: URL

    /// The Kitchen Tales family user pool (eu-central-1_mH3Vk6Rfm), its web app client and the API.
    static let kitchenTales: CoachConfig? = CoachConfig(
        region: "eu-central-1",
        clientID: "4eiiqrg9hfhm54ckehvnr2d86d",
        graphQLURL: URL(string: "https://vm7rxsikqndzva5cntsnnziqoq.appsync-api.eu-central-1.amazonaws.com/graphql")!
    )

    var cognitoURL: URL { URL(string: "https://cognito-idp.\(region).amazonaws.com/")! }
}

enum CoachError: Error, Equatable {
    case notConfigured
    case signedOut
    case wrongPassword
    /// The account still has its temporary password: set a new one in Kitchen Tales first.
    case newPasswordRequired
    case offline
    /// The server's own words (e.g. the monthly limit).
    case server(String)
}

/// The signed-in account: kept in the Keychain on this iPhone, never in the vault file.
struct CoachSession: Codable, Equatable, Sendable {
    var email: String
    var refreshToken: String
    var idToken: String?
    var expiresAt: Date?

    var hasFreshToken: Bool {
        guard idToken != nil, let expiresAt else { return false }
        return expiresAt > .now.addingTimeInterval(60)
    }
}

protocol CoachSessionStore: Sendable {
    func load() -> CoachSession?
    func save(_ session: CoachSession?)
}

struct KeychainCoachSessionStore: CoachSessionStore {
    var service = "app.fallow.ios.coach"
    var account = "kitchen-tales"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> CoachSession? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CoachSession.self, from: data)
    }

    func save(_ session: CoachSession?) {
        SecItemDelete(query as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

final class MemoryCoachSessionStore: CoachSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: CoachSession?
    init(_ session: CoachSession? = nil) { self.session = session }
    func load() -> CoachSession? { lock.withLock { session } }
    func save(_ session: CoachSession?) { lock.withLock { self.session = session } }
}

/// What Fallow sends to the coach (the same JSON Răgaz sends, with app and language).
struct CoachRequest: Encodable, Sendable {
    struct Turn: Encodable, Sendable {
        var role: String
        var text: String
    }

    var kind: String
    var app = "fallow"
    var lang: String
    var messages: [Turn]?
    var note: String?
    var context: String?
    var items: [String]?
}

/// Talks to Cognito and to the coach. Stateless apart from the session store.
struct CoachClient: Sendable {
    let config: CoachConfig?
    let store: any CoachSessionStore
    var session: URLSession = .shared

    static func live() -> CoachClient {
        CoachClient(config: .kitchenTales, store: KeychainCoachSessionStore())
    }

    var isConfigured: Bool { config != nil }
    var signedInEmail: String? { store.load()?.email }

    func signIn(email: String, password: String) async throws {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result = try await initiateAuth(flow: "USER_PASSWORD_AUTH", parameters: ["USERNAME": clean, "PASSWORD": password])
        guard let refresh = result.RefreshToken else { throw CoachError.wrongPassword }
        store.save(CoachSession(email: clean, refreshToken: refresh, idToken: result.IdToken, expiresAt: result.expiry))
    }

    func signOut() { store.save(nil) }

    /// Sends one request to the coach and returns its JSON answer.
    func call(_ request: CoachRequest) async throws -> Data {
        guard let config else { throw CoachError.notConfigured }
        let token = try await idToken()
        var http = URLRequest(url: config.graphQLURL)
        http.httpMethod = "POST"
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue(token, forHTTPHeaderField: "Authorization")
        let input = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        http.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": "mutation MindCoach($input: String!) { mindCoach(input: $input) }",
            "variables": ["input": input],
        ])
        let (data, response) = try await send(http)
        struct Answer: Decodable {
            struct Payload: Decodable { var mindCoach: String? }
            struct Problem: Decodable { var message: String }
            var data: Payload?
            var errors: [Problem]?
        }
        if (response as? HTTPURLResponse)?.statusCode == 401 { store.save(nil); throw CoachError.signedOut }
        let answer = try? JSONDecoder().decode(Answer.self, from: data)
        if let problem = answer?.errors?.first { throw CoachError.server(problem.message) }
        guard let text = answer?.data?.mindCoach else { throw CoachError.server("") }
        return Data(text.utf8)
    }

    func chat(_ messages: [CoachState.Message], note: String, context: String, english: Bool) async throws -> String {
        struct Out: Decodable { var text: String }
        let turns = messages.suffix(CoachState.send).map { CoachRequest.Turn(role: $0.role.rawValue, text: $0.text) }
        let data = try await call(CoachRequest(kind: "chat", lang: english ? "en" : "ro", messages: Array(turns), note: note, context: context))
        return try JSONDecoder().decode(Out.self, from: data).text
    }

    /// What Claude proposes to add to the note ("" when nothing new).
    func proposeMemory(_ messages: [CoachState.Message], note: String, english: Bool) async throws -> String {
        struct Out: Decodable { var text: String }
        let turns = messages.suffix(40).map { CoachRequest.Turn(role: $0.role.rawValue, text: $0.text) }
        let data = try await call(CoachRequest(kind: "remember", lang: english ? "en" : "ro", messages: Array(turns), note: note))
        return try JSONDecoder().decode(Out.self, from: data).text
    }

    // MARK: Cognito

    private struct AuthResult: Decodable {
        var IdToken: String?
        var RefreshToken: String?
        var ExpiresIn: Int?
        var expiry: Date { .now.addingTimeInterval(TimeInterval(ExpiresIn ?? 3600)) }
    }

    private func idToken() async throws -> String {
        guard var current = store.load() else { throw CoachError.signedOut }
        if current.hasFreshToken, let token = current.idToken { return token }
        let result: AuthResult
        do {
            result = try await initiateAuth(flow: "REFRESH_TOKEN_AUTH", parameters: ["REFRESH_TOKEN": current.refreshToken])
        } catch CoachError.wrongPassword {
            store.save(nil)
            throw CoachError.signedOut
        }
        guard let token = result.IdToken else { throw CoachError.signedOut }
        current.idToken = token
        current.expiresAt = result.expiry
        store.save(current)
        return token
    }

    private func initiateAuth(flow: String, parameters: [String: String]) async throws -> AuthResult {
        guard let config else { throw CoachError.notConfigured }
        var http = URLRequest(url: config.cognitoURL)
        http.httpMethod = "POST"
        http.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        http.setValue("AWSCognitoIdentityProviderService.InitiateAuth", forHTTPHeaderField: "X-Amz-Target")
        http.httpBody = try JSONSerialization.data(withJSONObject: [
            "AuthFlow": flow, "ClientId": config.clientID, "AuthParameters": parameters,
        ])
        let (data, response) = try await send(http)
        struct Envelope: Decodable {
            var AuthenticationResult: AuthResult?
            var ChallengeName: String?
            var __type: String?
            var message: String?
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if envelope?.ChallengeName == "NEW_PASSWORD_REQUIRED" { throw CoachError.newPasswordRequired }
        if let result = envelope?.AuthenticationResult { return result }
        let type = envelope?.__type ?? ""
        if type.contains("NotAuthorized") || type.contains("UserNotFound") { throw CoachError.wrongPassword }
        throw CoachError.server(envelope?.message ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost].contains(error.code) {
            throw CoachError.offline
        }
    }
}
