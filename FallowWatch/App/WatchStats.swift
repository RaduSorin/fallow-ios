import Foundation

/// What the watch remembers for itself: counts and minutes, never words. A note is sealed and
/// gone the moment it is sent; only "2 notes today" stays.
enum WatchStats {
    private static let notesDayKey = "stats.notes.day"
    private static let notesCountKey = "stats.notes.count"
    private static let lastNoteKey = "stats.notes.last"
    private static let breathingKey = "stats.breathing"

    static func notes(on day: String) -> Int {
        UserDefaults.standard.string(forKey: notesDayKey) == day ? UserDefaults.standard.integer(forKey: notesCountKey) : 0
    }

    static var lastNote: Date? {
        UserDefaults.standard.object(forKey: lastNoteKey) as? Date
    }

    static func addNote(at date: Date = .now) {
        let day = DayKey.string(date)
        let count = notes(on: day) + 1
        UserDefaults.standard.set(day, forKey: notesDayKey)
        UserDefaults.standard.set(count, forKey: notesCountKey)
        UserDefaults.standard.set(date, forKey: lastNoteKey)
    }

    /// Seconds of breathing per day ("2026-11-20": 180), the last two weeks only.
    private static var breathing: [String: Double] {
        UserDefaults.standard.dictionary(forKey: breathingKey) as? [String: Double] ?? [:]
    }

    static func addBreathing(_ seconds: Double, at date: Date = .now, calendar: Calendar = .current) {
        var days = breathing
        let day = DayKey.string(date, calendar: calendar)
        days[day, default: 0] += seconds
        let oldest = DayKey.string(calendar.date(byAdding: .day, value: -14, to: date) ?? date, calendar: calendar)
        days = days.filter { $0.key >= oldest }
        UserDefaults.standard.set(days, forKey: breathingKey)
    }

    static func breathingMinutes(on date: Date = .now, calendar: Calendar = .current) -> Int {
        Int((breathing[DayKey.string(date, calendar: calendar)] ?? 0) / 60)
    }

    /// Since the start of this week (the phone's calendar decides the first day).
    static func breathingMinutesThisWeek(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let first = DayKey.string(start, calendar: calendar)
        let today = DayKey.string(now, calendar: calendar)
        let seconds = breathing.filter { $0.key >= first && $0.key <= today }.values.reduce(0, +)
        return Int(seconds / 60)
    }

    /// "Erase everything" on the iPhone.
    static func reset() {
        for key in [notesDayKey, notesCountKey, lastNoteKey, breathingKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
