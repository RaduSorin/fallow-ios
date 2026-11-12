import Foundation
import Observation
import UIKit
import UserNotifications

/// Where a tapped notification should take the person, once Face ID has opened the vault.
enum AppRoute: String, Sendable, CaseIterable {
    case today, friday, worry, reflection, exercise, note

    /// The key in a notification's userInfo.
    static let key = "route"

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo[Self.key] as? String, let route = AppRoute(rawValue: raw) else { return nil }
        self = route
    }

    /// "fallow://friday", from a widget, a control or Siri.
    init?(url: URL) {
        guard url.scheme == FallowLink.scheme, let host = url.host(), let route = AppRoute(rawValue: host) else { return nil }
        self = route
    }

    init(reminder kind: PlannedReminder.Kind) {
        switch kind {
        case .morning, .evening: self = .today
        case .friday: self = .friday
        case .worry: self = .worry
        case .reflection: self = .reflection
        }
    }

    /// The tab that holds the screen.
    var tab: AppTab {
        switch self {
        case .reflection: .month
        case .today, .friday, .worry, .exercise, .note: .today
        }
    }
}

/// Holds the route from a tapped notification until the screen that answers it is on screen.
/// The vault may be locked when the tap arrives; the route waits until it opens.
@MainActor
@Observable
final class Router {
    static let shared = Router()

    var pending: AppRoute?
}

/// Receives notification taps, including the one that launched the app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = AppRoute(userInfo: response.notification.request.content.userInfo) ?? .today
        await MainActor.run { Router.shared.pending = route }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // While the app is open the exercise screen already shows the end: only the bell rings.
        if notification.request.identifier == ExerciseBell.identifier { return [.sound] }
        return [.banner, .list, .sound]
    }
}
