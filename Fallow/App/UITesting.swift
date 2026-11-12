import Foundation

/// Launched by the UI tests ("-ui-testing"): a fresh vault in a temporary folder with its key in
/// memory (no Face ID, no Keychain), a backup in a local folder, and no notification prompt
/// (a system alert would cover the screen the test is reading).
enum UITesting {
    static let argument = "-ui-testing"

    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    private static var folder: URL {
        URL.temporaryDirectory.appending(path: "fallow-ui-testing", directoryHint: .isDirectory)
    }

    @MainActor
    static func vault() -> Vault {
        // Every launch starts from nothing: the key lived only in the last run's memory.
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return Vault(keyStore: InMemoryKeyStore(), fileURL: folder.appending(path: "vault.fallow"))
    }

    @MainActor
    static func backup() -> Backup {
        let defaults = UserDefaults(suiteName: "fallow-ui-testing") ?? .standard
        defaults.removePersistentDomain(forName: "fallow-ui-testing")
        return Backup(
            store: FolderBackupStore(url: folder.appending(path: "backup.fallowbackup")),
            keys: InMemoryBackupKey(),
            defaults: defaults,
            photos: PhotoStore(folder: folder.appending(path: "Photos", directoryHint: .isDirectory))
        )
    }
}
