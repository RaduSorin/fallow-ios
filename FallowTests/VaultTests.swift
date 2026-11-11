import CryptoKit
import Foundation
import Testing
@testable import Fallow

struct VaultCryptoTests {
    @Test func sealThenOpenGivesBackTheSameBytes() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("Make room for slowness.".utf8)
        let sealed = try VaultCrypto.seal(plain, key: key)
        #expect(sealed.starts(with: VaultCrypto.header))
        #expect(try VaultCrypto.open(sealed, key: key) == plain)
    }

    @Test func anotherKeyCannotOpenIt() throws {
        let sealed = try VaultCrypto.seal(Data("secret".utf8), key: SymmetricKey(size: .bits256))
        #expect(throws: VaultError.wrongKey) {
            try VaultCrypto.open(sealed, key: SymmetricKey(size: .bits256))
        }
    }

    @Test func garbageIsReportedAsCorrupted() {
        #expect(throws: VaultError.corrupted) {
            try VaultCrypto.open(Data("not a vault".utf8), key: SymmetricKey(size: .bits256))
        }
    }
}

@MainActor
struct VaultTests {
    let file = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).fallow")

    @Test func startsNotSetUpWithoutAFile() {
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        #expect(vault.state == .notSetUp)
    }

    @Test func setUpUnlocksAndWritesOnlyCiphertext() throws {
        let vault = Vault(keyStore: InMemoryKeyStore(), fileURL: file)
        var settings = VaultSettings()
        settings.morningReminder = 7 * 60
        try vault.setUp(settings: settings)

        #expect(vault.state == .unlocked)
        #expect(vault.contents?.settings.morningReminder == 7 * 60)
        let onDisk = try Data(contentsOf: file)
        #expect(String(data: onDisk, encoding: .utf8)?.contains("morningReminder") != true)
    }

    @Test func lockForgetsContentsAndUnlockBringsThemBack() async throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        try vault.setUp(settings: VaultSettings())
        try vault.update { $0.settings.iCloudBackup = false }

        vault.lock()
        #expect(vault.state == .locked)
        #expect(vault.contents == nil)

        await vault.unlock(reason: "test")
        #expect(vault.state == .unlocked)
        #expect(vault.contents?.settings.iCloudBackup == false)
    }

    @Test func reopeningTheAppStartsLocked() throws {
        let keys = InMemoryKeyStore()
        try Vault(keyStore: keys, fileURL: file).setUp(settings: VaultSettings())
        let reopened = Vault(keyStore: keys, fileURL: file)
        #expect(reopened.state == .locked)
    }

    @Test func cancelledFaceIDStaysLockedWithoutAnError() async throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        try vault.setUp(settings: VaultSettings())
        vault.lock()

        keys.failNextLoad = .cancelled
        await vault.unlock(reason: "test")
        #expect(vault.state == .locked)
        #expect(vault.lastError == .cancelled)
    }

    @Test func eraseRemovesKeyAndFile() throws {
        let keys = InMemoryKeyStore()
        let vault = Vault(keyStore: keys, fileURL: file)
        try vault.setUp(settings: VaultSettings())
        try vault.eraseEverything()

        #expect(vault.state == .notSetUp)
        #expect(!keys.hasKey())
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

struct VaultSettingsTests {
    @Test func minutesRoundTripThroughADate() {
        let date = VaultSettings.date(fromMinutes: 8 * 60 + 30)
        #expect(VaultSettings.minutes(from: date) == 8 * 60 + 30)
    }
}
