import Foundation
import UserNotifications

/// Puts the planned reminders on the phone. Nothing about them leaves the device.
enum ReminderScheduler {
    static let prefix = "fallow."

    /// Asks once for permission. Returns whether reminders may show.
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces every Fallow reminder with the ones the plan wants now.
    static func reschedule(_ contents: VaultContents, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for reminder in ReminderPlan.reminders(for: contents, now: now) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: title(for: reminder.kind))
            content.body = String(localized: body(for: reminder.kind))
            content.sound = .default
            content.threadIdentifier = "fallow"
            content.userInfo = [AppRoute.key: AppRoute(reminder: reminder.kind).rawValue]
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.components, repeats: reminder.repeats)
            let request = UNNotificationRequest(identifier: prefix + reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func title(for kind: PlannedReminder.Kind) -> LocalizedStringResource {
        switch kind {
        case .morning: "Good morning"
        case .evening: "A quiet minute"
        case .friday: "Friday evening"
        case .worry: "Monday worry list"
        case .reflection: "A new month"
        }
    }

    static func body(for kind: PlannedReminder.Kind) -> LocalizedStringResource {
        switch kind {
        case .morning: "Your intention for the month is waiting."
        case .evening: "How did today go? A line is enough."
        case .friday: "Tonight's exercise is ready when you are."
        case .worry: "Sort what weighs on you into stone and clay."
        case .reflection: "Look back on last month and choose the next intention."
        }
    }
}
