import Foundation

/// A calendar month, stored as "2026-11" (the same id Răgaz used, so imports line up).
struct MonthID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        // Normalise 0 and 13 so arithmetic can step over year ends.
        let index = year * 12 + (month - 1)
        self.year = Int((Double(index) / 12).rounded(.down))
        self.month = index - self.year * 12 + 1
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1)
    }

    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        self.init(year: parts[0], month: parts[1])
    }

    static func current(calendar: Calendar = .current) -> MonthID { MonthID(.now, calendar: calendar) }

    var description: String { String(format: "%04d-%02d", year, month) }
    var next: MonthID { MonthID(year: year, month: month + 1) }
    var previous: MonthID { MonthID(year: year, month: month - 1) }

    func firstDay(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
    }

    /// Every Friday in the month, as start-of-day dates.
    func fridays(calendar: Calendar = .current) -> [Date] {
        let start = firstDay(calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { day -> Date? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            return calendar.component(.weekday, from: date) == 6 ? date : nil
        }
    }

    static func < (lhs: MonthID, rhs: MonthID) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let id = MonthID(string: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad month id \(text)"))
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// One Friday of the month and what it is for.
struct FridayPlan: Codable, Equatable, Sendable, Identifiable {
    /// "2026-11-13"
    var date: String
    var exerciseId: String?
    var title: String

    var id: String { date }
}

/// The month's plan: an intention, the sign that it went well, and the Fridays.
struct MonthPlan: Codable, Equatable, Sendable, Identifiable {
    var id: MonthID
    var intention: String
    /// What success looks like, e.g. "I'm in bed before 11".
    var success: String?
    /// How many Fridays make it a good month.
    var target: Int?
    var fridays: [FridayPlan]
    var savedAt: Date
    /// When the month was first planned; later edits keep it. Older files have none (savedAt then).
    var plannedAt: Date? = nil

    static func blank(_ month: MonthID, calendar: Calendar = .current) -> MonthPlan {
        MonthPlan(
            id: month,
            intention: "",
            success: nil,
            target: nil,
            fridays: month.fridays(calendar: calendar).map {
                FridayPlan(date: DayKey.string($0, calendar: calendar), exerciseId: nil, title: "")
            },
            savedAt: .now
        )
    }
}

enum NoteKind: String, Codable, Sendable {
    case friday, free, worry, reflection
}

/// A note in the journal: after a Friday exercise, a free note, a worry list or the monthly reflection.
struct Note: Codable, Equatable, Sendable, Identifiable {
    var id: String = UUID().uuidString
    /// The day it is about, "2026-11-13".
    var date: String
    var month: MonthID
    var kind: NoteKind
    var exerciseId: String?
    var title: String?
    /// How strong the feeling was before and after, 0 to 10.
    var before: Int?
    var after: Int?
    var fit: NoteFit?
    var text: String = ""
    /// Reflection answers by question key (see ReflectionQuestion).
    var answers: [String: String]?
    /// The worry list's parts (kind .worry).
    var worry: WorryList?
    /// Photos kept with the note, by id (sealed files, see PhotoStore).
    var photos: [String]?
    var createdAt: Date = .now
}

/// The four questions at the end of a month, plus the sign.
enum ReflectionQuestion: String, CaseIterable, Identifiable, Sendable {
    case changed, worked, avoid, keep

    var id: String { rawValue }

    var prompt: LocalizedStringResource {
        switch self {
        case .changed: "What changed this month?"
        case .worked: "What worked?"
        case .avoid: "What am I avoiding?"
        case .keep: "What do I keep, and what do I change next month?"
        }
    }

    /// Answer key for "Did you see the sign?": "yes" or "no".
    static let signKey = "sign"
}

/// What the month looked like, computed only from the plan and the notes.
struct MonthSummary: Equatable, Sendable {
    var fridays: Int
    var fridaysDone: Int
    var target: Int?
    var notes: Int

    var reachedTarget: Bool {
        guard let target, target > 0 else { return false }
        return fridaysDone >= target
    }

    init(plan: MonthPlan?, notes: [Note]) {
        let fridayDates = Set(plan?.fridays.map(\.date) ?? [])
        fridays = fridayDates.count
        fridaysDone = Set(notes.filter { $0.kind == .friday && fridayDates.contains($0.date) }.map(\.date)).count
        target = plan?.target
        self.notes = notes.filter { $0.kind != .reflection }.count
    }
}

extension MonthID: Identifiable {
    var id: String { description }

    /// "November", in the app's language.
    var name: String { firstDay().formatted(.dateTime.month(.wide)) }
    /// "November 2026", in the app's language.
    var nameWithYear: String { firstDay().formatted(.dateTime.month(.wide).year()) }
}

extension FridayPlan {
    /// "13 November", in the app's language.
    var dayName: String {
        guard let day = DayKey.date(date) else { return date }
        return day.formatted(.dateTime.day().month(.wide))
    }
}
