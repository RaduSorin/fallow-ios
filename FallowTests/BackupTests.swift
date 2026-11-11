import CryptoKit
import Foundation
import Testing
@testable import Fallow

struct TransferFileTests {
    func sample() -> VaultContents {
        var c = VaultContents(createdAt: Date(timeIntervalSince1970: 1_790_000_000), settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11))
        plan.intention = "Slow mornings"
        c.save(plan)
        c.save(Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .free, text: "Hello"))
        return c
    }

    @Test func sealsAndOpensWithThePassphrase() throws {
        let file = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        #expect(file.starts(with: TransferFile.header))
        #expect(!String(decoding: file, as: UTF8.self).contains("Slow mornings"))
        let opened = try TransferFile.open(file, passphrase: "  quiet forest walk ")
        #expect(opened.months.first?.intention == "Slow mornings")
        #expect(opened.notes.first?.text == "Hello")
    }

    @Test func wrongPassphraseAndOtherFilesAreRefused() throws {
        let file = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        #expect(throws: TransferFile.Failure.wrongPassphrase) { try TransferFile.open(file, passphrase: "loud city") }
        #expect(throws: TransferFile.Failure.wrongPassphrase) { try TransferFile.open(file, passphrase: "") }
        #expect(throws: TransferFile.Failure.notAFallowFile) { try TransferFile.open(Data("hello".utf8), passphrase: "x") }
        #expect(throws: TransferFile.Failure.shortPassphrase) { try TransferFile.seal(sample(), passphrase: " short  ") }
    }

    @Test func tooManyRoundsAreRefused() throws {
        var file = try TransferFile.seal(sample(), passphrase: "quiet forest walk", rounds: 1_000)
        let at = TransferFile.header.count + 16
        file.replaceSubrange(at..<at + 4, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: TransferFile.Failure.notAFallowFile) { try TransferFile.open(file, passphrase: "quiet forest walk") }
    }

    /// Made in Node with Web Crypto (PBKDF2-SHA256, AES-GCM), the way Kitchen Tales will write it.
    @Test func opensAFileMadeWithWebCrypto() throws {
        let file = try #require(Data(base64Encoded: "RkFMTE9XWDGecn4W/hNqqmFlrmfUAsx6AAAD6OSUwF2MUfPyAY5SHyipzvg4i+hN6ngQcygx1gsuKcyZ6lQTfz2oZp+sHS1H3QbNEbBzkv+ja1ZQ3Np1c3FImkEnuzpKdCuNh7y2+/m/kXere5E94RykYqph5AB7XpOt60pv06j3QOHndS4wKzKoUcPvPgLOMLjLDreMqKw0L9N88RQHY3OcolUvspM8+yTDOXZ8fnhBzjunRCZW5EA88Mensf0DgmAWQsmbHnP74V6RmdY1UQbdRx9tcumpe6Wtfp6VQYVi881+aRVJL2oreoKcTS3ryDwnMMVjQ0MkzLctPRERo0LdHCIcGqsSV7fVD6yb+rHzVb1n/rqeo1gi4DdMkWkS0M15txxc2OQq15UIGFKBSYZQvQFYPMB2XvZL1tuVTFA3tuOVPXy18nrTv7kBKlTG9Y767J0I64ugA0fmgafbtdjhd7pXp9EwUx+6hjiXGKvmndVd3HlbDy6gZ6SbvBLGO+RSBngYpOJxO8jq5QFTNh86LBX/Mdeg61vP6gzw6U2orrPK/ZYIJ47mVZRyCWxUh56X3KQsq+XG1gLqubMNYbp70od5Z5LwizNosJtHLjCk/iRB4MBH+QxswFYJsZI="))
        let contents = try TransferFile.open(file, passphrase: "Pădure liniștită")
        #expect(contents.months.first?.intention == "Mai multă odihnă")
        #expect(contents.notes.first?.text == "Prima notă")
        #expect(contents.notes.first?.kind == .free)
    }
}

/// A file made by Kitchen Tales' "Exportă pentru Fallow" (src/lib/mind/fallow.ts), so Răgaz data
/// written by the web app opens here with every part: months, notes, worry list, exercises, herbarium.
struct KitchenTalesImportTests {
    @Test func opensARagazExport() throws {
        let file = try #require(Data(base64Encoded: "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"))
        let c = try TransferFile.open(file, passphrase: "Pădure liniștită")
        #expect(c.settings.fridayReminder)
        #expect(!c.settings.worryReminder)
        #expect(c.settings.morningReminder == nil)

        let month = try #require(c.plan(for: MonthID(year: 2026, month: 11)))
        #expect(month.intention == "Mai multă odihnă")
        #expect(month.target == 3)
        #expect(month.fridays.map(\.exerciseId) == ["e1", nil])

        let friday = try #require(c.notes.first { $0.id == "fri-1" })
        #expect(friday.kind == .friday)
        #expect(friday.fit == .yes)
        #expect(friday.before == 7 && friday.after == 4)
        #expect(c.reflection(for: MonthID(year: 2026, month: 11))?.answers?[ReflectionQuestion.signKey] == "yes")
        let worry = try #require(c.notes.first { $0.kind == .worry }?.worry)
        #expect(worry.step == "La 23 în pat")
        #expect(worry.parent?.need == "Odihnă")

        #expect(c.exercises.map(\.title) == ["Scrisoare blândă", "Plimbare"])
        #expect(Herbarium.hasProgram(c))

        let book = try #require(c.herbarium)
        #expect(Set(book.earned.keys) == ["vineri", "luna:2026-11"])
        #expect(book.pending == ["luna:2026-11"])
    }
}

@MainActor
struct BackupTests {
    let folder = URL.temporaryDirectory.appending(path: "backup-\(UUID().uuidString)", directoryHint: .isDirectory)

    func makeBackup(keys: InMemoryBackupKey = InMemoryBackupKey()) throws -> (Backup, FolderBackupStore, InMemoryBackupKey) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = FolderBackupStore(url: folder.appending(path: "vault.fallowbackup"))
        let defaults = UserDefaults(suiteName: "backup-tests-\(UUID().uuidString)")!
        return (Backup(store: store, keys: keys, defaults: defaults), store, keys)
    }

    func contents(backup: Bool = true) -> VaultContents {
        var settings = VaultSettings()
        settings.iCloudBackup = backup
        var c = VaultContents(createdAt: .now, settings: settings)
        c.addRhythm("Walk")
        return c
    }

    @Test func backsUpSealedAndRestoresOnANewPhone() async throws {
        let (backup, store, keys) = try makeBackup()
        await backup.backUp(contents())
        guard case .saved = backup.status else { Issue.record("not saved: \(backup.status)"); return }
        let sealed = try #require(try await store.read())
        #expect(!String(decoding: sealed, as: UTF8.self).contains("Walk"))

        // A new iPhone: same iCloud file, same synced key.
        let newPhone = Backup(store: store, keys: keys, defaults: UserDefaults(suiteName: "backup-tests-\(UUID().uuidString)")!)
        #expect(await newPhone.hasBackup())
        let restored = try await newPhone.restore()
        #expect(restored.rhythms.map(\.title) == ["Walk"])

        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
        try vault.restore(restored)
        #expect(vault.state == .unlocked)
        #expect(vault.contents?.rhythms.map(\.title) == ["Walk"])
    }

    @Test func offMeansNoBackup() async throws {
        let (backup, store, _) = try makeBackup()
        await backup.backUp(contents(backup: false))
        #expect(backup.status == .off)
        #expect(try await store.read() == nil)
    }

    @Test func restoreExplainsWhatIsMissing() async throws {
        let (backup, store, keys) = try makeBackup()
        await #expect(throws: BackupError.notFound) { try await backup.restore() }
        await backup.backUp(contents())
        try keys.deleteKey()
        await #expect(throws: BackupError.noKey) { try await backup.restore() }
        _ = try keys.createKey()
        await #expect(throws: BackupError.wrongKey) { try await backup.restore() }
        _ = store
    }

    @Test func manyChangesMakeOneBackup() async throws {
        let (backup, store, _) = try makeBackup()
        backup.delay = .milliseconds(200)
        var c = contents()
        backup.schedule(c)
        c.addRhythm("Read")
        backup.schedule(c)
        await backup.flush()
        let restored = try await backup.restore()
        #expect(restored.rhythms.map(\.title) == ["Walk", "Read"])
        _ = store
    }

    @Test func deleteRemovesTheBackupAndItsKey() async throws {
        let (backup, store, keys) = try makeBackup()
        await backup.backUp(contents())
        try await backup.deleteBackup()
        #expect(try await store.read() == nil)
        #expect(try keys.key() == nil)
    }
}
