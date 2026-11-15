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
