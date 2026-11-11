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
        let fresh = VaultContents(createdAt: .now, settings: settings)
        try write(fresh, key: newKey)
        key = newKey
        contents = fresh
        lastError = nil
        state = .unlocked
    }

    func unlock(reason: String) async {
        guard state == .locked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        do {
            let loaded = try await keyStore.loadKey(reason: reason)
            let sealed = try Data(contentsOf: fileURL)
            let plain = try VaultCrypto.open(sealed, key: loaded)
            contents = try Self.decoder.decode(VaultContents.self, from: plain)
            key = loaded
            lastError = nil
            state = .unlocked
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
        try write(next, key: key)
        contents = next
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
        let plain = try Self.encoder.encode(value)
        let sealed = try VaultCrypto.seal(plain, key: key)
        try sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
