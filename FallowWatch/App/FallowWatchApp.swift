import SwiftUI
import UserNotifications
import WatchKit

/// Fallow on the Apple Watch. The watch never opens the vault (it has no Face ID): it shows
/// what the iPhone widgets may show, and what it writes goes sealed to the iPhone.
@main
struct FallowWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environment(WatchModel.shared)
                .tint(WatchPalette.moss)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // The same buttons as on the iPhone; reminders from the iPhone show them on the wrist.
        center.setNotificationCategories(ReminderActions.categories())
        PhoneLink.shared.start()
        // Only for "later", which the watch schedules itself. Asked once.
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    }

    func applicationDidBecomeActive() {
        Task { @MainActor in WatchModel.shared.reload() }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case ReminderActions.line:
            if let text = (response as? UNTextInputNotificationResponse)?.userText,
               let entry = ReminderActions.lineEntry(text) {
                try? PhoneLink.shared.send(entry)
            }
        case ReminderActions.later:
            await ReminderActions.snooze(response.notification.request.content)
        default:
            // A tap opens the watch app on Today.
            break
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
