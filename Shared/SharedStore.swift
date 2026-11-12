import Foundation

/// Files shared between the app, its widgets and its Siri actions, in the App Group.
/// Nothing here is private: the snapshot holds only neutral facts (and, if the person
/// turned it on, the month's intention and rhythm titles), the inbox holds sealed boxes
/// that only the vault can open.
enum SharedStore {
    static let appGroup = "group.app.fallow.ios"

    /// The App Group folder. Unsigned builds (CI, tests) have no group: they use a folder of
    /// their own, which is enough for one process.
    static var folder: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Shared", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var snapshotURL: URL { folder.appending(path: "widget-snapshot.json") }
    static var publicKeyURL: URL { folder.appending(path: "inbox-public.key") }
    static var inboxFolder: URL {
        let url = folder.appending(path: "Inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Readable while the phone is locked (Lock Screen widgets), after the first unlock since restart.
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    static func readSnapshot() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder.shared.decode(WidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder.shared.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: writeOptions)
    }

    static func readPublicKey() -> Data? {
        try? Data(contentsOf: publicKeyURL)
    }

    static func writePublicKey(_ key: Data) {
        guard readPublicKey() != key else { return }
        try? key.write(to: publicKeyURL, options: writeOptions)
    }

    /// Used by "Erase everything": the widgets go blank and the inbox is dropped.
    static func eraseAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: snapshotURL)
        try? fm.removeItem(at: publicKeyURL)
        try? fm.removeItem(at: folder.appending(path: "Inbox", directoryHint: .isDirectory))
    }
}

extension JSONEncoder {
    static var shared: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var shared: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Links into the app ("fallow://friday"), used by widgets, controls and Siri.
enum FallowLink {
    static let scheme = "fallow"

    static func url(_ route: String) -> URL {
        URL(string: "\(scheme)://\(route)")!
    }
}
