import Foundation

/// One reminder Fallow wants on the phone. Texts never include anything the person wrote,
/// because notifications show on the lock screen.
struct PlannedReminder: Equatable, Sendable {
    enum Kind: String, Sendable {
        case morning, evening, friday, worry, reflection
    }

    var id: String
    var kind: Kind
    var components: DateComponents
    var repeats: Bool
}

/// Works out the reminders from the settings and the month plans. Pure, so it can be tested.
enum ReminderPlan {
    static let fridayMinutes = 20 * 60
    static let mondayMinutes = 8 * 60 + 30

    static func reminders(for contents: VaultContents, now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        let settings = contents.settings
        var out: [PlannedReminder] = []

        if let minutes = settings.morningReminder {
            out.append(.init(id: "morning", kind: .morning, components: time(minutes), repeats: true))
        }
        if let minutes = settings.eveningReminder {
            out.append(.init(id: "evening", kind: .evening, components: time(minutes), repeats: true))
        }
        if settings.worryReminder {
            var monday = time(mondayMinutes)
            monday.weekday = 2
            out.append(.init(id: "worry", kind: .worry, components: monday, repeats: true))
        }

        let thisMonth = MonthID(now, calendar: calendar)
        let todayKey = DayKey.string(now, calendar: calendar)
        let nowMinutes = VaultSettings.minutes(from: now, calendar: calendar)

        if settings.fridayReminder {
            // Planned Fridays of this month and the next one that are still ahead.
            for month in [thisMonth, thisMonth.next] {
                for friday in contents.plan(for: month)?.fridays ?? [] {
                    guard friday.date > todayKey || (friday.date == todayKey && nowMinutes < fridayMinutes),
                          let parts = dayParts(friday.date) else { continue }
                    var components = parts
                    components.hour = fridayMinutes / 60
                    components.minute = fridayMinutes % 60
                    out.append(.init(id: "friday-\(friday.date)", kind: .friday, components: components, repeats: false))
                }
            }
        }

        if settings.reflectionReminder {
            // The first Monday of the next three months (and this one, if still ahead).
            for month in [thisMonth, thisMonth.next, thisMonth.next.next] {
                guard let monday = firstMonday(of: month, calendar: calendar) else { continue }
                let key = DayKey.string(monday, calendar: calendar)
                guard key > todayKey || (key == todayKey && nowMinutes < mondayMinutes),
                      var components = dayParts(key) else { continue }
                components.hour = mondayMinutes / 60
                components.minute = mondayMinutes % 60
                out.append(.init(id: "reflection-\(month)", kind: .reflection, components: components, repeats: false))
            }
        }
        return out
    }

    static func firstMonday(of month: MonthID, calendar: Calendar = .current) -> Date? {
        let start = month.firstDay(calendar: calendar)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if calendar.component(.weekday, from: day) == 2 { return day }
        }
        return nil
    }

    private static func time(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    private static func dayParts(_ key: String) -> DateComponents? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}
