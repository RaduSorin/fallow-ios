import Foundation
import UserNotifications

/// The buttons on Fallow's reminders, on the iPhone and on the Apple Watch (each registers
/// the same categories). Neither button opens the vault: a line written in the notification
/// goes sealed into the inbox, and "later" shows the same reminder once more.
enum ReminderActions {
    static let line = "fallow.action.line"
    static let later = "fallow.action.later"
    /// Snoozed copies. Not "fallow." so that rescheduling the plan leaves them alone.
    static let snoozePrefix = "fallow-later."

    enum Category: String, CaseIterable, Sendable {
        /// The evening reminder: write a line, or later.
        case line = "fallow.category.line"
        /// Morning, Monday and new-month reminders: in an hour.
        case later = "fallow.category.later"
        /// Friday evening: in 15 minutes.
        case friday = "fallow.category.friday"

        var snoozeMinutes: Int {
            self == .friday ? 15 : 60
        }
    }

    static func categories() -> Set<UNNotificationCategory> {
        let write = UNTextInputNotificationAction(
            identifier: line,
            title: String(localized: "Write a line"),
            options: [],
            textInputButtonTitle: String(localized: "Save"),
            textInputPlaceholder: String(localized: "A line is enough")
        )
        let hour = UNNotificationAction(identifier: later, title: String(localized: "In an hour"), options: [])
        let quarter = UNNotificationAction(identifier: later, title: String(localized: "In 15 minutes"), options: [])
        return [
            UNNotificationCategory(identifier: Category.line.rawValue, actions: [write, hour], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.later.rawValue, actions: [hour], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.friday.rawValue, actions: [quarter], intentIdentifiers: []),
        ]
    }

    /// A line typed or dictated in the notification, as an inbox entry. Nil when empty.
    static func lineEntry(_ text: String, at date: Date = .now, calendar: Calendar = .current) -> InboxEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return .note(trimmed, day: DayKey.string(date, calendar: calendar), at: date)
    }

    /// Shows the same reminder again, once, on this device.
    static func snooze(_ content: UNNotificationContent) async {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let minutes = Category(rawValue: content.categoryIdentifier)?.snoozeMinutes ?? 60
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: snoozePrefix + UUID().uuidString, content: copy, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
