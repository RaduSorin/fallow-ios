import SwiftUI

@main
struct FallowApp: App {
    @State private var vault = Vault.live()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .tint(Theme.moss)
                .foregroundStyle(Theme.ink)
        }
        .onChange(of: scenePhase) { _, phase in
            // Lock as soon as the app leaves the screen.
            if phase == .background {
                vault.lock()
            }
        }
    }
}
