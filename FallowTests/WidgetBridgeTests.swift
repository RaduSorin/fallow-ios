import CryptoKit
import Foundation
import Testing
@testable import Fallow

@MainActor
struct WidgetBridgeTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func planned() -> VaultContents {
        var c = VaultContents(createdAt: .now, settings: VaultSettings())
        var exercise = Exercise(title: "Breathing", steps: "In\n\nOut")
        exercise.id = "ex"
        c.save(exercise)
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: calendar)
        plan.intention = "Slowness"
        plan.fridays[1].exerciseId = "ex" // 13 November
        plan.fridays[1].title = "Breathing"
        c.save(plan)
        c.rhythms = [Rhythm(id: "r1", title: "Walk without the phone"), Rhythm(id: "r2", title: "Tea")]
        c.toggleRhythm("r1", on: "2026-11-13")
        return c
    }

    @Test func snapshotHoldsNothingWrittenByDefault() throws {
        let snapshot = SharedBridge.snapshot(from: planned(), now: date(2026, 11, 13), calendar: calendar)
        #expect(snapshot.intention == nil)
        #expect(snapshot.rhythms == nil)
        #expect(snapshot.fridays.contains("2026-11-13"))
        #expect(snapshot.fridaysWithExercise == ["2026-11-13"])
        #expect(snapshot.rhythmCount == 2)
        #expect(snapshot.done(on: "2026-11-13") == ["r1"])
        #expect(snapshot.done(on: "2026-11-14").isEmpty)
        // Not a word of the intention, the rhythms or the exercise in the file.
        let json = String(decoding: try JSONEncoder.shared.encode(snapshot), as: UTF8.self)
        #expect(!json.contains("Slowness"))
        #expect(!json.contains("Walk"))
        #expect(!json.contains("Breathing"))
    }

    @Test func intentionAndRhythmsOnlyWhenTurnedOn() {
        var contents = planned()
        contents.settings.widgetIntention = true
        contents.settings.widgetRhythms = true
        let snapshot = SharedBridge.snapshot(from: contents, now: date(2026, 11, 13), calendar: calendar)
        #expect(snapshot.intention == "Slowness")
        #expect(snapshot.rhythms?.map(\.title) == ["Walk without the phone", "Tea"])
    }

    @Test func reflectionIsSuggestedInTheFirstWeek() {
        let contents = planned()
        let early = SharedBridge.snapshot(from: contents, now: date(2026, 12, 2), calendar: calendar)
        #expect(early.reflectionUntil == "2026-12-07")
        let late = SharedBridge.snapshot(from: contents, now: date(2026, 12, 9), calendar: calendar)
        #expect(late.reflectionUntil == nil)
    }

    @Test func widgetLeadsWithWhatTheDayHolds() {
        var snapshot = WidgetSnapshot(writtenAt: .now)
        snapshot.fridays = ["2026-11-13", "2026-11-20"]
        snapshot.fridaysWithExercise = ["2026-11-13"]
        #expect(WidgetFocus.for(snapshot, day: "2026-11-13", isMonday: false) == .fridayExercise)
        #expect(WidgetFocus.for(snapshot, day: "2026-11-20", isMonday: false) == .freeFriday)
        #expect(WidgetFocus.for(snapshot, day: "2026-11-16", isMonday: true) == .worryList)
        #expect(WidgetFocus.for(snapshot, day: "2026-11-17", isMonday: false) == .nextFriday("2026-11-20"))
        snapshot.intention = "Slowness"
        #expect(WidgetFocus.for(snapshot, day: "2026-11-17", isMonday: false) == .intention("Slowness"))
        snapshot.reflectionUntil = "2026-11-18"
        #expect(WidgetFocus.for(snapshot, day: "2026-11-16", isMonday: true) == .reflection)
        #expect(WidgetFocus.for(snapshot, day: "2026-11-21", isMonday: false) == .intention("Slowness"))
        #expect(WidgetFocus.fridayExercise.route == "friday")
    }

    @Test func widgetTickChangesOnlyThatDay() {
        var snapshot = WidgetSnapshot(writtenAt: .now)
        snapshot.rhythmDay = "2026-11-12"
        snapshot.rhythmsDone = ["r1"]
        snapshot.set("r2", done: true, on: "2026-11-13")
        #expect(snapshot.done(on: "2026-11-13") == ["r2"])
        snapshot.set("r2", done: false, on: "2026-11-13")
        #expect(snapshot.done(on: "2026-11-13").isEmpty)
    }

    @Test func linksOpenTheRightScreen() {
        #expect(AppRoute(url: FallowLink.url("friday")) == .friday)
        #expect(AppRoute(url: FallowLink.url("note")) == .note)
        #expect(AppRoute(url: URL(string: "https://fallow.app/friday")!) == nil)
        #expect(AppRoute(url: FallowLink.url("nowhere")) == nil)
    }
}

struct InboxTests {
    @Test func onlyTheVaultKeyOpensAnEntry() throws {
        let key = Curve25519.KeyAgreement.PrivateKey()
        let entry = InboxEntry.note("Saw the first snow", day: "2026-11-13", at: Date(timeIntervalSince1970: 1_800_000_000))
        let box = try Inbox.seal(entry, to: key.publicKey.rawRepresentation)
        #expect(!String(decoding: box, as: UTF8.self).contains("snow"))
        #expect(try Inbox.open(box, with: key) == entry)
        #expect(throws: (any Error).self) { try Inbox.open(box, with: Curve25519.KeyAgreement.PrivateKey()) }
        #expect(throws: (any Error).self) { try Inbox.open(Data("nonsense".utf8), with: key) }
    }

    @Test func postedEntriesWaitOldestFirst() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let pub = key.publicKey.rawRepresentation
        try Inbox.post(.note("second", day: "2026-11-13", at: Date(timeIntervalSince1970: 1_800_000_100)), folder: folder, publicKey: pub)
        try Inbox.post(.note("first", day: "2026-11-13", at: Date(timeIntervalSince1970: 1_800_000_000)), folder: folder, publicKey: pub)
        let texts = try Inbox.waiting(in: folder).map { try Inbox.open(Data(contentsOf: $0), with: key).text }
        #expect(texts == ["first", "second"])
        #expect(throws: (any Error).self) { try Inbox.post(.note("x", day: "2026-11-13"), folder: folder, publicKey: nil) }
    }

    @Test func entriesLandInTheVault() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        contents.rhythms = [Rhythm(id: "r1", title: "Walk")]
        contents.apply(.rhythm("r1", done: true, day: "2026-11-13"))
        contents.apply(.rhythm("r1", done: true, day: "2026-11-13")) // twice changes nothing
        #expect(contents.rhythmsDone(on: "2026-11-13") == ["r1"])
        contents.apply(.rhythm("r1", done: false, day: "2026-11-13"))
        #expect(contents.rhythmsDone(on: "2026-11-13").isEmpty)
        contents.apply(.rhythm("gone", done: true, day: "2026-11-13"))
        #expect(contents.rhythmLog.isEmpty)

        contents.apply(.note("  Saw the first snow ", day: "2026-11-13"))
        contents.apply(.note("   ", day: "2026-11-13"))
        #expect(contents.notes.count == 1)
        #expect(contents.notes.first?.text == "Saw the first snow")
        #expect(contents.notes.first?.kind == .free)
        #expect(contents.notes.first?.month == MonthID(year: 2026, month: 11))
    }

    @Test func drainMakesTheKeyThenTakesEntriesIn() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = await Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
        try await vault.setUp(settings: VaultSettings())
        await SharedBridge.drain(into: vault, folder: folder)
        let raw = try #require(await vault.contents?.inboxKey)
        let pub = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw).publicKey.rawRepresentation
        try Inbox.post(.note("From Siri", day: "2026-11-13"), folder: folder, publicKey: pub)
        await SharedBridge.drain(into: vault, folder: folder)
        #expect(await vault.contents?.notes.map(\.text) == ["From Siri"])
        #expect(Inbox.waiting(in: folder).isEmpty)
    }
}
