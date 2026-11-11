import Foundation

/// Everything private that Fallow keeps. Stored only as one encrypted file.
/// Fields added in later versions decode as empty from older files.
struct VaultContents: Codable, Equatable, Sendable {
    var version = 1
    var createdAt: Date
    var settings: VaultSettings
    var months: [MonthPlan] = []
    var notes: [Note] = []
    var rhythms: [Rhythm] = []
    /// Day ("2026-11-13") to the ids of the rhythms kept that day.
    var rhythmLog: [String: [String]] = [:]
    var exercises: [Exercise] = []

    init(createdAt: Date, settings: VaultSettings) {
        self.createdAt = createdAt
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        settings = try c.decodeIfPresent(VaultSettings.self, forKey: .settings) ?? VaultSettings()
        months = try c.decodeIfPresent([MonthPlan].self, forKey: .months) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        rhythms = try c.decodeIfPresent([Rhythm].self, forKey: .rhythms) ?? []
        rhythmLog = try c.decodeIfPresent([String: [String]].self, forKey: .rhythmLog) ?? [:]
        exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
    }

    func plan(for month: MonthID) -> MonthPlan? {
        months.first { $0.id == month }
    }

    mutating func save(_ plan: MonthPlan) {
        if let index = months.firstIndex(where: { $0.id == plan.id }) {
            months[index] = plan
        } else {
            months.append(plan)
            months.sort { $0.id < $1.id }
        }
    }

    func notes(in month: MonthID) -> [Note] {
        notes.filter { $0.month == month }.sorted { $0.date > $1.date }
    }

    func reflection(for month: MonthID) -> Note? {
        notes.first { $0.month == month && $0.kind == .reflection }
    }

    mutating func save(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
    }
}

struct VaultSettings: Codable, Equatable, Sendable {
    /// Minutes after midnight, or nil when that reminder is off.
    var morningReminder: Int? = 8 * 60 + 30
    var eveningReminder: Int? = 21 * 60
    /// Encrypted copy in the person's own iCloud. On by default.
    var iCloudBackup = true
    /// Friday 20:00 on planned Fridays.
    var fridayReminder = true
    /// Monday 8:30, the weekly worry list.
    var worryReminder = true
    /// First Monday of the month, 8:30, the monthly reflection.
    var reflectionReminder = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        morningReminder = try c.decodeIfPresent(Int.self, forKey: .morningReminder)
        eveningReminder = try c.decodeIfPresent(Int.self, forKey: .eveningReminder)
        iCloudBackup = try c.decodeIfPresent(Bool.self, forKey: .iCloudBackup) ?? true
        fridayReminder = try c.decodeIfPresent(Bool.self, forKey: .fridayReminder) ?? true
        worryReminder = try c.decodeIfPresent(Bool.self, forKey: .worryReminder) ?? true
        reflectionReminder = try c.decodeIfPresent(Bool.self, forKey: .reflectionReminder) ?? true
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}
