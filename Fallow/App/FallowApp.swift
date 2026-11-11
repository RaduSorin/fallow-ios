import SwiftUI

@main
struct FallowApp: App {
    @State private var vault: Vault
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyBarAppearance()
        let vault = Vault.live()
        vault.onChange = { contents in
            Task.detached {
                // The permission prompt shows only the first time.
                await ReminderScheduler.requestPermission()
                await ReminderScheduler.reschedule(contents)
            }
        }
        _vault = State(initialValue: vault)
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
