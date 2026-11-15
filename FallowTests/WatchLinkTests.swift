import CryptoKit
import Foundation
import Testing
@testable import Fallow

struct WatchLinkTests {
    func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func contextCarriesTheSnapshotAndKeyOnly() throws {
        var snapshot = WidgetSnapshot(writtenAt: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.rhythmCount = 2
        snapshot.rhythmIDs = ["r1", "r2"]
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let context = WatchPayload.context(snapshot: snapshot, publicKey: key)
        #expect(WatchPayload.snapshot(in: context) == snapshot)
        #expect(WatchPayload.publicKey(in: context) == key)
        #expect(!WatchPayload.isErased(context))
        #expect(Set(context.keys) == [WatchPayload.snapshotKey, WatchPayload.publicKeyKey])
    }

    @Test func emptyContextErasesTheWatch() {
        let context = WatchPayload.context(snapshot: nil, publicKey: nil)
        #expect(WatchPayload.isErased(context))
        #expect(WatchPayload.snapshot(in: context) == nil)
    }

    @Test func aTickFromTheWatchReachesTheInboxAndTheSnapshot() throws {
        let folder = try tempFolder()
        let vaultKey = Curve25519.KeyAgreement.PrivateKey()
        let entry = InboxEntry.rhythm("r2", done: true, day: "2026-11-20")
        let box = try Inbox.seal(entry, to: vaultKey.publicKey.rawRepresentation)
        let info = WatchPayload.outgoing(entry, box: box)

        var stored = WidgetSnapshot(writtenAt: .now)
        stored.rhythmDay = "2026-11-20"
        stored.rhythmsDone = ["r1"]
        let ok = WatchBridge.receive(info, folder: folder, readSnapshot: { stored }, writeSnapshot: { stored = $0 })

        #expect(ok)
        #expect(stored.done(on: "2026-11-20") == ["r1", "r2"])
        let files = Inbox.waiting(in: folder)
        #expect(files.count == 1)
        #expect(try Inbox.open(Data(contentsOf: files[0]), with: vaultKey) == entry)
    }

    @Test func aLineFromTheWatchStaysSealed() throws {
        let folder = try tempFolder()
        let vaultKey = Curve25519.KeyAgreement.PrivateKey()
        let entry = try #require(ReminderActions.lineEntry("  Ten minutes outside helped  "))
        #expect(entry.text == "Ten minutes outside helped")
        let box = try Inbox.seal(entry, to: vaultKey.publicKey.rawRepresentation)
        let info = WatchPayload.outgoing(entry, box: box)
        // Only the sealed box travels: no tick, no words in the clear.
        #expect(WatchPayload.tick(in: info) == nil)
        #expect(Set(info.keys) == [WatchPayload.boxKey])

        var wrote = false
        let ok = WatchBridge.receive(info, folder: folder, readSnapshot: { nil }, writeSnapshot: { _ in wrote = true })
        #expect(ok)
        #expect(!wrote)
        #expect(Inbox.waiting(in: folder).count == 1)
    }

    @Test func somethingThatIsNotABoxIsDropped() throws {
        let folder = try tempFolder()
        #expect(!WatchBridge.receive([WatchPayload.boxKey: Data("hello".utf8)], folder: folder))
        #expect(!WatchBridge.receive([:], folder: folder))
        #expect(Inbox.waiting(in: folder).isEmpty)
    }

    @Test func breathingSendsOnlyItsTimes() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), duration: 180)
        let info = WatchPayload.mindful(interval)
        #expect(WatchPayload.mindful(in: info) == interval)
        #expect(WatchPayload.box(in: info) == nil)
        #expect(WatchPayload.mindful(in: [WatchPayload.mindfulStartKey: 10.0, WatchPayload.mindfulEndKey: 5.0]) == nil)
    }

    @MainActor
    @Test func healthFlagFollowsTheSetting() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        #expect(SharedBridge.snapshot(from: contents).healthMindful == nil)
        contents.settings.healthMindful = true
        #expect(SharedBridge.snapshot(from: contents).healthMindful == true)
    }

    @Test func emptyLineIsIgnored() {
        #expect(ReminderActions.lineEntry("   \n") == nil)
    }

    @Test func remindersGetTheirButtons() {
        #expect(ReminderScheduler.category(for: .evening) == .line)
        #expect(ReminderScheduler.category(for: .friday) == .friday)
        #expect(ReminderScheduler.category(for: .morning) == .later)
        #expect(ReminderScheduler.category(for: .freeFriday) == nil)
        #expect(ReminderActions.Category.friday.snoozeMinutes == 15)
        #expect(ReminderActions.Category.later.snoozeMinutes == 60)
        #expect(!ReminderActions.snoozePrefix.hasPrefix(ReminderScheduler.prefix))
    }
}

@MainActor
struct WatchExerciseTests {
    @Test func theWatchSeesTimingButNoTextByDefault() {
        let run = ExerciseRun()
        var sent: [WatchExercise?] = []
        run.onWatchChange = { sent.append($0) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        run.start(Exercise(title: "Secret title", minutes: 5, steps: "Private step\n\nAnother"))
        let first = run.watchState(at: now)
        #expect(first?.stepCount == 2)
        #expect(first?.stepText == nil)
        #expect(first?.started == false)
        #expect(first?.remaining == 300)

        run.startClock(now: now)
        let running = run.watchState(at: now.addingTimeInterval(60))
        #expect(running?.endsAt == now.addingTimeInterval(300))
        #expect(running?.remaining(at: now.addingTimeInterval(60)) == 240)
        run.pause(now: now.addingTimeInterval(60))
        #expect(run.watchState(at: now.addingTimeInterval(90))?.isPaused == true)
        run.close()
        #expect(sent.last == .some(nil))
        #expect(sent.count >= 4)
    }

    @Test func stepsGoToTheWatchOnlyWhenAllowed() {
        let run = ExerciseRun()
        run.showStepsOnWatch = true
        run.start(Exercise(title: "Breathing", minutes: nil, steps: "In\n\nOut"))
        #expect(run.watchState()?.stepText == "In")
        run.show(step: 1)
        #expect(run.watchState()?.stepText == "Out")
    }

    @Test func aFeelingFromTheWatchLandsOnItsOwnRun() {
        let run = ExerciseRun()
        run.start(Exercise(title: "Breathing", minutes: 5, steps: "In"))
        let id = run.watchState()!.session
        run.rate(session: "another run", before: 7, after: nil)
        #expect(run.session?.before == nil)
        run.rate(session: id, before: 7, after: nil)
        run.rate(session: id, before: nil, after: 3)
        #expect(run.session?.before == 7)
        #expect(run.session?.after == 3)

        let info = WatchPayload.feeling(.init(session: id, before: 14, after: nil))
        #expect(WatchPayload.feeling(in: info) == .init(session: id, before: 10, after: nil))
    }
}
