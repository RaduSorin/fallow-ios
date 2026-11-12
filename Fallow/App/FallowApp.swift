import SwiftUI

@main
struct FallowApp: App {
    @State private var vault: Vault
    @State private var backup: Backup
    @State private var run = ExerciseRun()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyBarAppearance()
        ExerciseRun.endLeftovers()
        let vault = Vault.live()
        let backup = Backup.live()
        vault.onChange = { contents in
            Task { @MainActor in
                backup.schedule(contents)
                SharedBridge.publish(contents)
            }
            Task.detached {
                // The permission prompt shows only the first time.
                await ReminderScheduler.requestPermission()
                await ReminderScheduler.reschedule(contents)
            }
        }
        _vault = State(initialValue: vault)
        _backup = State(initialValue: backup)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vault)
                .environment(backup)
                .environment(run)
                .environment(Router.shared)
                .onOpenURL { url in
                    if let route = AppRoute(url: url) { Router.shared.pending = route }
                }
                .tint(Theme.moss)
                .foregroundStyle(Theme.ink)
        }
        .onChange(of: scenePhase) { _, phase in
            // Lock as soon as the app leaves the screen.
            if phase == .background {
                vault.lock()
                Task { await backup.flush() }
            }
            if phase == .active { SeasonalIcon.apply() }
        }
    }
}
