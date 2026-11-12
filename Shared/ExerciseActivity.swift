import ActivityKit
import Foundation

/// The Live Activity shown on the Lock Screen and in the Dynamic Island while a guided
/// exercise runs. It never carries the exercise's title or anything the person wrote:
/// only a generic label and the time.
struct ExerciseActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        /// When the time runs out, while the clock is running. Nil while paused or finished.
        var endsAt: Date?
        /// Seconds left, shown while paused.
        var remaining: Double
        var finished: Bool
    }

    /// Texts in the app's own language, so the extension does not need its own translations.
    var label: String
    var pausedLabel: String
    var doneLabel: String
}
