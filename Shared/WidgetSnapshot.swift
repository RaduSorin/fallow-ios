import Foundation

/// What the widgets may know, written by the app each time the vault changes.
/// By default it holds no words the person wrote: only dates and counts.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct SharedRhythm: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
    }

    var writtenAt: Date
    /// Planned Fridays of this month and the next ("2026-11-13").
    var fridays: [String] = []
    /// The planned Fridays that have an exercise.
    var fridaysWithExercise: [String] = []
    /// This month: Fridays planned and Fridays with a note.
    var monthFridays: Int = 0
    var monthFridaysDone: Int = 0
    /// While the last month's reflection is not written: the last day it is suggested ("2026-12-07").
    var reflectionUntil: String?
    /// How many rhythms there are, and which were kept on `rhythmDay`.
    var rhythmCount: Int = 0
    var rhythmDay: String = ""
    var rhythmsDone: [String] = []
    /// Only when the person turned these on in Settings.
    var intention: String?
    var rhythms: [SharedRhythm]?

    /// The rhythms kept on a day, as far as the widget knows.
    func done(on day: String) -> [String] {
        day == rhythmDay ? rhythmsDone : []
    }

    /// Marks a rhythm kept or not on a day (used by the widget button, before the vault knows).
    mutating func set(_ rhythm: String, done: Bool, on day: String) {
        var kept = Set(self.done(on: day))
        if done { kept.insert(rhythm) } else { kept.remove(rhythm) }
        rhythmDay = day
        rhythmsDone = kept.sorted()
    }
}

/// What the main widget leads with on a given day.
enum WidgetFocus: Equatable, Sendable {
    case fridayExercise
    case freeFriday
    case worryList
    case reflection
    case nextFriday(String)
    case intention(String)
    case quiet

    static func `for`(_ snapshot: WidgetSnapshot, day: String, isMonday: Bool) -> WidgetFocus {
        if snapshot.fridaysWithExercise.contains(day) { return .fridayExercise }
        if snapshot.fridays.contains(day) { return .freeFriday }
        if let until = snapshot.reflectionUntil, day <= until { return .reflection }
        if isMonday { return .worryList }
        if let intention = snapshot.intention, !intention.isEmpty { return .intention(intention) }
        if let next = snapshot.fridays.sorted().first(where: { $0 > day }) { return .nextFriday(next) }
        return .quiet
    }

    /// Where a tap on the widget goes.
    var route: String {
        switch self {
        case .fridayExercise, .freeFriday: "friday"
        case .worryList: "worry"
        case .reflection: "reflection"
        case .nextFriday, .intention, .quiet: "today"
        }
    }
}
