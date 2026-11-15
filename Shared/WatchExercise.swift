import Foundation

/// The guided exercise as the Apple Watch mirrors it, while it runs on the iPhone. Timing and
/// step numbers only; the step's text only when the person chose to show steps on the watch.
/// Kept in memory on the watch, never saved there.
struct WatchExercise: Codable, Equatable, Sendable {
    /// The run on the iPhone, so a feeling sent from the watch lands on the right one.
    var session: String
    /// When the time runs out, while the clock is running.
    var endsAt: Date?
    var remaining: Double
    /// The planned length in seconds; 0 for an exercise without a timer.
    var duration: Double
    var started: Bool
    var finished: Bool
    var step: Int
    var stepCount: Int
    var stepText: String?
    /// How strong the feeling was before and after, 0 to 10, as rated so far.
    var before: Int?
    var after: Int?

    var isPaused: Bool { started && !finished && endsAt == nil }

    func remaining(at now: Date) -> Double {
        guard let endsAt else { return remaining }
        return max(0, endsAt.timeIntervalSince(now))
    }
}

extension WatchPayload {
    static let exerciseKey = "exercise"
    static let feelingSessionKey = "feelingSession"
    static let feelingBeforeKey = "feelingBefore"
    static let feelingAfterKey = "feelingAfter"

    static func exercise(in context: [String: Any]) -> WatchExercise? {
        guard let data = context[exerciseKey] as? Data else { return nil }
        return try? JSONDecoder.shared.decode(WatchExercise.self, from: data)
    }

    /// A feeling rated on the watch: plain numbers for the run in memory on the iPhone, which
    /// puts them in the note's draft. They reach the vault only when the note is saved.
    struct Feeling: Equatable, Sendable {
        var session: String
        var before: Int?
        var after: Int?
    }

    static func feeling(_ feeling: Feeling) -> [String: Any] {
        var out: [String: Any] = [feelingSessionKey: feeling.session]
        if let before = feeling.before { out[feelingBeforeKey] = min(10, max(0, before)) }
        if let after = feeling.after { out[feelingAfterKey] = min(10, max(0, after)) }
        return out
    }

    static func feeling(in info: [String: Any]) -> Feeling? {
        guard let session = info[feelingSessionKey] as? String else { return nil }
        let clamp: (Int?) -> Int? = { $0.map { min(10, max(0, $0)) } }
        return Feeling(session: session, before: clamp(info[feelingBeforeKey] as? Int), after: clamp(info[feelingAfterKey] as? Int))
    }
}
