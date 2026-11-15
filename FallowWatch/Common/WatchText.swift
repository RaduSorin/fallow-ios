import Foundation

/// A rhythm the watch can tick: its title only when the person chose to show rhythms outside
/// the vault (Me › Widgets on the iPhone), otherwise just its number.
struct WatchRhythm: Identifiable, Equatable, Sendable {
    let id: String
    let number: Int
    let title: String?
}

extension WidgetSnapshot {
    var watchRhythms: [WatchRhythm] {
        if let rhythms {
            return rhythms.enumerated().map { WatchRhythm(id: $1.id, number: $0 + 1, title: $1.title) }
        }
        return (rhythmIDs ?? []).enumerated().map { WatchRhythm(id: $1, number: $0 + 1, title: nil) }
    }

    func focus(on date: Date, calendar: Calendar = .current) -> WidgetFocus {
        WidgetFocus.for(self, day: DayKey.string(date, calendar: calendar), isMonday: calendar.component(.weekday, from: date) == 2)
    }
}

/// The words for what the day holds, the same as the iPhone widget's.
extension WidgetFocus {
    var label: LocalizedStringResource {
        switch self {
        case .fridayExercise, .freeFriday: "Tonight"
        case .worryList: "Monday"
        case .reflection: "New month"
        case .nextFriday: "Next Friday"
        case .intention: "This month"
        case .quiet: "Fallow"
        }
    }

    var title: String {
        switch self {
        case .fridayExercise: String(localized: "Friday exercise")
        case .freeFriday: String(localized: "A free Friday")
        case .worryList: String(localized: "Sort the week's worries")
        case .reflection: String(localized: "Look back on last month")
        case .nextFriday(let day):
            DayKey.date(day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day
        case .intention(let text): text
        case .quiet: String(localized: "A quiet day")
        }
    }

    var isIntention: Bool {
        if case .intention = self { return true }
        return false
    }
}
