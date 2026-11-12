import UIKit

/// The app icon follows the month's plant from the herbarium. It is only a picture of the
/// season, so the choice lives outside the vault: it has to work before Face ID.
enum SeasonalIcon {
    static let key = "seasonalIcon"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// "Season11" for November, nil for the usual icon.
    static func iconName(on: Bool, date: Date, calendar: Calendar = .current) -> String? {
        guard on else { return nil }
        let month = calendar.component(.month, from: date)
        return String(format: "Season%02d", month)
    }

    /// Changes the icon only when it differs, since iOS tells the person every time it changes.
    @MainActor
    static func apply(now: Date = .now) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        let wanted = iconName(on: isOn, date: now)
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }
}
