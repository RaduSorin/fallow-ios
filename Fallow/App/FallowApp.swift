import SwiftUI

@main
struct FallowApp: App {
    init() {
        Theme.applyBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.moss)
                .foregroundStyle(Theme.ink)
        }
    }
}
