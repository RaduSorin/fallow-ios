import CryptoKit
import Foundation
import Observation

/// Keeps an encrypted copy of the vault in the person's iCloud, a couple of seconds after each
/// change, and brings it back on a new iPhone. The copy is sealed with the backup key from
/// iCloud Keychain, so neither Apple nor we can read it.
@MainActor
@Observable
final class Backup {
    enum Status: Equatable {
        case off
        case waiting
        case saving
        case saved(Date)
        case unavailable
        case failed
    }

    private(set) var status: Status
    /// Seconds to wait after a change, so a burst of edits makes one backup.
    @ObservationIgnored var delay: Duration = .seconds(2)
    @ObservationIgnored private let store: any BackupStore
    @ObservationIgnored private let keys: any BackupKeyStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: (contents: VaultContents, task: Task<Void, Never>)?

    private static let lastBackupKey = "lastICloudBackup"

    init(store: any BackupStore, keys: any BackupKeyStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.keys = keys
        self.defaults = defaults
        if let last = defaults.object(forKey: Self.lastBackupKey) as? Date {
            status = .saved(last)
        } else {
            status = .waiting
        }
    }

    static func live() -> Backup {
        Backup(store: ICloudBackupStore(), keys: ICloudKeychainBackupKey())
    }

    var lastBackup: Date? {
        if case .saved(let date) = status { return date }
        return defaults.object(forKey: Self.lastBackupKey) as? Date
    }

    /// After every change: backs up shortly, if the person wants a backup.
    func schedule(_ contents: VaultContents) {
        pending?.task.cancel()
        guard contents.settings.iCloudBackup else {
            pending = nil
            status = .off
            return
        }
        let delay = delay
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.backUp(contents)
        }
        pending = (contents, task)
    }

    /// The app is leaving the screen: write a waiting backup now instead of later.
    func flush() async {
        guard let waiting = pending else { return }
        waiting.task.cancel()
        pending = nil
        await backUp(waiting.contents)
    }

    func backUp(_ contents: VaultContents) async {
        guard contents.settings.iCloudBackup else { status = .off; return }
        status = .saving
        do {
            let key = try keys.keyCreatingIfMissing()
            let sealed = try VaultCrypto.seal(VaultCoding.encoder.encode(contents), key: key)
            try await store.write(sealed)
            let now = Date.now
            defaults.set(now, forKey: Self.lastBackupKey)
            status = .saved(now)
        } catch BackupError.unavailable {
            status = .unavailable
        } catch {
            status = .failed
        }
    }

    /// Whether iCloud holds a backup (looked for on the first run, before starting fresh).
    func hasBackup() async -> Bool {
        (try? await store.read()) != nil
    }

    /// The backup from iCloud, opened with the key from iCloud Keychain.
    func restore() async throws -> VaultContents {
        guard let sealed = try await store.read() else { throw BackupError.notFound }
        guard let key = try keys.key() else { throw BackupError.noKey }
        let plain: Data
        do {
            plain = try VaultCrypto.open(sealed, key: key)
        } catch VaultError.wrongKey {
            throw BackupError.wrongKey
        } catch {
            throw BackupError.unreadable
        }
        do {
            return try VaultCoding.decoder.decode(VaultContents.self, from: plain)
        } catch {
            throw BackupError.unreadable
        }
    }

    /// Erase everything: the backup and its key go too.
    func deleteBackup() async throws {
        pending?.task.cancel()
        pending = nil
        try await store.delete()
        try keys.deleteKey()
        defaults.removeObject(forKey: Self.lastBackupKey)
        status = .waiting
    }
}
