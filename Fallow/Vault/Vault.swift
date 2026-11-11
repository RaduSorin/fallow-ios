import CryptoKit
import Foundation
import Observation

/// The encrypted vault: locked until Face ID opens it, locked again
/// when the app goes to the background.
@MainActor
@Observable
final class Vault {
    enum State: Equatable {
        case notSetUp
        case locked
        case unlocked
    }

    private(set) var state: State
    private(set) var contents: VaultContents?
    private(set) var lastError: VaultError?
    private(set) var isUnlocking = false

    @ObservationIgnored private var key: SymmetricKey?
    @ObservationIgnored private let keyStore: any VaultKeyStore
    @ObservationIgnored let fileURL: URL
    /// Called with the new contents after setup, unlock and every change (the app reschedules reminders).
    @ObservationIgnored var onChange: ((VaultContents) -> Void)?

    init(keyStore: any VaultKeyStore, fileURL: URL) {
        self.keyStore = keyStore
        self.fileURL = fileURL
        let hasFile = FileManager.default.fileExists(atPath: fileURL.path)
        state = hasFile && keyStore.hasKey() ? .locked : .notSetUp
    }

    static func live() -> Vault {
        let folder = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return Vault(keyStore: KeychainKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
    }

    /// First run: makes a new key and an empty vault with these settings.
    func setUp(settings: VaultSettings) throws {
        let newKey = try keyStore.createKey()
        var fresh = VaultContents(createdAt: .now, settings: settings)
        fresh.checkHerbarium(visit: true)
        try write(fresh, key: newKey)
        key = newKey
        contents = fresh
        lastError = nil
        state = .unlocked
        onChange?(fresh)
    }

    /// First run on a new iPhone: makes a new key and keeps what came from a backup or a file.
    func restore(_ restored: VaultContents) throws {
        let newKey = try keyStore.createKey()
        var next = restored
        next.checkHerbarium(visit: true)
        try write(next, key: newKey)
        key = newKey
        contents = next
        lastError = nil
        state = .unlocked
        onChange?(next)
    }

    func unlock(reason: String) async {
        guard state == .locked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        do {
            let loaded = try await keyStore.loadKey(reason: reason)
            let sealed = try Data(contentsOf: fileURL)
            let plain = try VaultCrypto.open(sealed, key: loaded)
            let decoded = try VaultCoding.decoder.decode(VaultContents.self, from: plain)
            // Opening counts as a visit; new plants (or a new herbarium) are saved right away.
            var opened = decoded
            opened.checkHerbarium(visit: true)
            if opened != decoded { try? write(opened, key: loaded) }
            contents = opened
            key = loaded
            lastError = nil
            state = .unlocked
            if let contents { onChange?(contents) }
        } catch let error as VaultError {
            lastError = error
        } catch {
            lastError = .corrupted
        }
    }

    func lock() {
        guard state == .unlocked else { return }
        key = nil
        contents = nil
        state = .locked
    }

    /// Changes the contents and saves them encrypted right away.
    func update(_ change: (inout VaultContents) -> Void) throws {
        guard let key, var next = contents else { throw VaultError.noKey }
        change(&next)
        next.checkHerbarium()
        try write(next, key: key)
        contents = next
        onChange?(next)
    }

    /// Deletes the key and the file. Nothing can be recovered afterwards.
    func eraseEverything() throws {
        try keyStore.deleteKey()
        try? FileManager.default.removeItem(at: fileURL)
        key = nil
        contents = nil
        state = .notSetUp
    }

    private func write(_ value: VaultContents, key: SymmetricKey) throws {
        let plain = try VaultCoding.encoder.encode(value)
        let sealed = try VaultCrypto.seal(plain, key: key)
        try sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
