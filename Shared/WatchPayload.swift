import Foundation

/// What travels between the iPhone and the Apple Watch (WatchConnectivity dictionaries).
///
/// Phone → watch: the neutral widget snapshot and the inbox's public key, as the application
/// context (only the latest one counts). Never anything from the vault itself.
/// Watch → phone: sealed inbox boxes, which only the vault can open. A rhythm tick also carries
/// its rhythm id, done flag and day in the clear (no title), the same facts the widget's button
/// writes to the snapshot, so the phone's widgets can follow before Face ID.
enum WatchPayload {
    static let snapshotKey = "snapshot"
    static let publicKeyKey = "publicKey"
    static let erasedKey = "erased"
    static let boxKey = "box"
    static let rhythmIDKey = "rhythmID"
    static let rhythmDoneKey = "rhythmDone"
    static let dayKey = "day"
    static let mindfulStartKey = "mindfulStart"
    static let mindfulEndKey = "mindfulEnd"

    /// A rhythm tick as the snapshot needs it.
    struct Tick: Equatable, Sendable {
        var rhythmID: String
        var done: Bool
        var day: String
    }

    // MARK: Phone → watch

    /// The application context. With neither a snapshot nor a key (after "Erase everything")
    /// it tells the watch to forget what it holds.
    static func context(snapshot: WidgetSnapshot?, publicKey: Data?) -> [String: Any] {
        var out: [String: Any] = [:]
        if let snapshot, let data = try? JSONEncoder.shared.encode(snapshot) { out[snapshotKey] = data }
        if let publicKey { out[publicKeyKey] = publicKey }
        if out.isEmpty { out[erasedKey] = true }
        return out
    }

    static func isErased(_ context: [String: Any]) -> Bool {
        context[erasedKey] as? Bool == true
    }

    static func snapshot(in context: [String: Any]) -> WidgetSnapshot? {
        guard let data = context[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder.shared.decode(WidgetSnapshot.self, from: data)
    }

    static func publicKey(in context: [String: Any]) -> Data? {
        context[publicKeyKey] as? Data
    }

    // MARK: Watch → phone

    /// A sealed box for the phone's inbox, with the tick in the clear when it is a rhythm.
    static func outgoing(_ entry: InboxEntry, box: Data) -> [String: Any] {
        var out: [String: Any] = [boxKey: box]
        if entry.kind == .rhythm, let id = entry.rhythmID {
            out[rhythmIDKey] = id
            out[rhythmDoneKey] = entry.done ?? true
            out[dayKey] = entry.day
        }
        return out
    }

    /// A breathing session from the watch, for Apple Health: only its start and end.
    static func mindful(_ interval: DateInterval) -> [String: Any] {
        [mindfulStartKey: interval.start.timeIntervalSince1970, mindfulEndKey: interval.end.timeIntervalSince1970]
    }

    static func mindful(in info: [String: Any]) -> DateInterval? {
        guard let start = info[mindfulStartKey] as? Double, let end = info[mindfulEndKey] as? Double, end > start else { return nil }
        return DateInterval(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
    }

    static func box(in info: [String: Any]) -> Data? {
        guard let box = info[boxKey] as? Data, box.starts(with: Inbox.header) else { return nil }
        return box
    }

    static func tick(in info: [String: Any]) -> Tick? {
        guard let id = info[rhythmIDKey] as? String, let day = info[dayKey] as? String else { return nil }
        return Tick(rhythmID: id, done: info[rhythmDoneKey] as? Bool ?? true, day: day)
    }
}
