import Foundation

/// Everything private that Fallow keeps. Stored only as one encrypted file.
/// Later PRs add the month, rhythms, worries, exercises and herbarium here.
struct VaultContents: Codable, Equatable, Sendable {
    var version = 1
    var createdAt: Date
    var settings: VaultSettings
}

struct VaultSettings: Codable, Equatable, Sendable {
    /// Minutes after midnight, or nil when that reminder is off.
    var morningReminder: Int? = 8 * 60 + 30
    var eveningReminder: Int? = 21 * 60
    /// Encrypted copy in the person's own iCloud. On by default.
    var iCloudBackup = true

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
}
