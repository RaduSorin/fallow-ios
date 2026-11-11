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
