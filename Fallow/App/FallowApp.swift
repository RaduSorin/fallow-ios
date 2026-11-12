import SwiftUI
import UIKit
import WidgetKit

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
        let testing = UITesting.isOn
        let vault = testing ? UITesting.vault() : Vault.live()
        let backup = testing ? UITesting.backup() : Backup.live()
        vault.onChange = { contents in
            Task { @MainActor in
                backup.schedule(contents)
                SharedBridge.publish(contents)
            }
            guard !testing else { return }
            Task.detached {
                // The permission prompt shows only the first time.
                await ReminderScheduler.requestPermission()
                await ReminderScheduler.reschedule(contents)
            }
        }
        vault.onErase = {
            // Nothing of the old journal may keep showing: reminders, widgets, the Claude sign-in.
            guard !testing else { return }
            CoachClient.live().signOut()
            WidgetCenter.shared.reloadAllTimelines()
            Task.detached { await ReminderScheduler.removeAll() }
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
                // Ask iOS for a few seconds, so the last change still reaches iCloud
                // before the app is suspended.
                let work = BackgroundWork.begin("Fallow backup")
                Task {
                    await backup.flush()
                    work.end()
                }
            }
            if phase == .active { SeasonalIcon.apply() }
        }
    }
}

/// A little time in the background (iOS ends it on its own after about 30 seconds).
@MainActor
final class BackgroundWork {
    private var id: UIBackgroundTaskIdentifier = .invalid

    static func begin(_ name: String) -> BackgroundWork {
        let work = BackgroundWork()
        work.id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak work] in
            MainActor.assumeIsolated { work?.end() }
        }
        return work
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
