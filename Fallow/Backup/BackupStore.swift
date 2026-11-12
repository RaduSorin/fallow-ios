import CryptoKit
import Foundation
import Security

enum BackupError: Error, Equatable {
    /// iCloud is off, or the app has no iCloud container.
    case unavailable
    /// No backup in iCloud yet.
    case notFound
    /// The backup is there but its key is not on this iPhone (iCloud Keychain off).
    case noKey
    case wrongKey
    case unreadable
}

/// The key for the iCloud backup. Unlike the vault key, it travels to the person's other
/// devices through iCloud Keychain (end-to-end encrypted), so a new iPhone can open the backup.
protocol BackupKeyStore: Sendable {
    func key() throws -> SymmetricKey?
    func createKey() throws -> SymmetricKey
    func deleteKey() throws
}

extension BackupKeyStore {
    func keyCreatingIfMissing() throws -> SymmetricKey {
        try key() ?? createKey()
    }
}

struct ICloudKeychainBackupKey: BackupKeyStore {
    var service = "app.fallow.ios.backup"
    var account = "backup-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
    }

    func key() throws -> SymmetricKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else { throw BackupError.unreadable }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw VaultError.keychain(status)
        }
    }

    func createKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        var query = baseQuery
        query[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        // Synced items cannot be "this device only".
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return key
    }

    func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }
}

/// Where the sealed backup is kept.
protocol BackupStore: Sendable {
    func write(_ data: Data) async throws
    /// The backup, or nil when there is none.
    func read() async throws -> Data?
    func delete() async throws

    /// Sealed photo files, next to the backup (the same bytes as on the phone).
    func photoIDs() async throws -> Set<String>
    func writePhoto(_ data: Data, id: String) async throws
    func readPhoto(_ id: String) async throws -> Data?
    func deletePhoto(_ id: String) async throws
}

/// The backup as one file in the app's own iCloud Drive container (not shown in the Files app).
struct ICloudBackupStore: BackupStore {
    static let fileName = "vault.fallowbackup"

    /// Must not run on the main thread: the first call can take a while.
    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw BackupError.unavailable
        }
        let folder = container.appending(path: "Backup", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: fileName)
    }

    func write(_ data: Data) async throws {
        try await Task.detached {
            let url = try Self.fileURL()
            try Self.coordinate(writing: url) { try data.write(to: $0, options: .atomic) }
        }.value
    }

    func read() async throws -> Data? {
        try await Task.detached { () async throws -> Data? in
            let url = try Self.fileURL()
            // On a new iPhone the file may be known but not downloaded yet.
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                return nil
            }
            for _ in 0..<60 {
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if values?.ubiquitousItemDownloadingStatus == .current { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            var result: Data?
            try Self.coordinate(reading: url) { result = try Data(contentsOf: $0) }
            return result
        }.value
    }

    func delete() async throws {
        try await Task.detached {
            let url = try Self.fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try Self.coordinate(writing: url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
        }.value
    }

    private static func photoFolder() throws -> URL {
        let folder = try fileURL().deletingLastPathComponent().appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func photoURL(_ id: String) throws -> URL {
        try photoFolder().appending(path: "\(id).\(PhotoStore.fileExtension)")
    }

    func photoIDs() async throws -> Set<String> {
        try await Task.detached {
            let folder = try Self.photoFolder()
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            // Files not downloaded yet show as ".name.fphoto.icloud".
            return Set(files.compactMap { url -> String? in
                var name = url.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    name = String(name.dropFirst().dropLast(".icloud".count))
                }
                let suffix = ".\(PhotoStore.fileExtension)"
                guard name.hasSuffix(suffix) else { return nil }
                return String(name.dropLast(suffix.count))
            })
        }.value
    }

    func writePhoto(_ data: Data, id: String) async throws {
        try await Task.detached {
            let url = try Self.photoURL(id)
            try Self.coordinate(writing: url) { try data.write(to: $0, options: .atomic) }
        }.value
    }

    func readPhoto(_ id: String) async throws -> Data? {
        try await Task.detached { () async throws -> Data? in
            let url = try Self.photoURL(id)
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                return nil
            }
            for _ in 0..<60 {
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if values?.ubiquitousItemDownloadingStatus == .current { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            var result: Data?
            try Self.coordinate(reading: url) { result = try Data(contentsOf: $0) }
            return result
        }.value
    }

    func deletePhoto(_ id: String) async throws {
        try await Task.detached {
            let url = try Self.photoURL(id)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try Self.coordinate(writing: url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
        }.value
    }

    private static func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions = .forReplacing, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
            do { try body(target) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    private static func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do { try body(target) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
}

/// For tests and previews: the backup in a local folder, the key in memory.
struct FolderBackupStore: BackupStore {
    let url: URL

    func write(_ data: Data) async throws { try data.write(to: url, options: .atomic) }

    func read() async throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    func delete() async throws { try? FileManager.default.removeItem(at: url) }

    private var photos: PhotoStore {
        PhotoStore(folder: url.deletingLastPathComponent().appending(path: "BackupPhotos", directoryHint: .isDirectory))
    }

    func photoIDs() async throws -> Set<String> { photos.ids() }
    func writePhoto(_ data: Data, id: String) async throws { try photos.write(data, id: id) }
    func readPhoto(_ id: String) async throws -> Data? { photos.read(id) }
    func deletePhoto(_ id: String) async throws { photos.delete(id) }
}

final class InMemoryBackupKey: BackupKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SymmetricKey?

    init() {}

    func key() throws -> SymmetricKey? { lock.withLock { stored } }

    func createKey() throws -> SymmetricKey {
        let new = SymmetricKey(size: .bits256)
        lock.withLock { stored = new }
        return new
    }

    func deleteKey() throws { lock.withLock { stored = nil } }
}
