import SwiftUI

/// The four main sections of the app, shown as tabs at the bottom.
enum AppTab: String, CaseIterable, Identifiable {
    case today, month, herbarium, me

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .today: "Today"
        case .month: "Month"
        case .herbarium: "Herbarium"
        case .me: "Me"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.horizon"
        case .month: "moon"
        case .herbarium: "leaf"
        case .me: "person.crop.circle"
        }
    }
}

/// Decides what to show: first-run setup, the lock screen or the app.
struct RootView: View {
    @Environment(Vault.self) private var vault

    var body: some View {
        switch vault.state {
        case .notSetUp: SetupFlow()
        case .locked: LockView()
        case .unlocked: MainTabs()
        }
    }
}

struct MainTabs: View {
    @Environment(Vault.self) private var vault
    @State private var selection: AppTab = .today
    /// The plant chosen in the moment, to land in the herbarium.
    @State private var landing: String?
    /// Plants put off with "Later" while the app is open: they wait in the herbarium.
    @State private var later: Set<String> = []

    /// The plant to show in the moment now, if any.
    private var coming: Herb? {
        guard selection != .herbarium, landing == nil,
              let book = vault.contents?.herbarium, book.quiet != true,
              let id = book.pending.first(where: { !later.contains($0) }) else { return nil }
        return Herb.find(id)
    }

    var body: some View {
        tabs
            .overlay {
                if let herb = coming {
                    HerbMoment(herb: herb) {
                        landing = herb.id
                        selection = .herbarium
                    } onLater: {
                        withAnimation { _ = later.insert(herb.id) }
                    }
                    .id(herb.id)
                    .transition(.opacity)
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(Text(tab.title))
                }
                .tabItem { Label { Text(tab.title) } icon: { Image(systemName: tab.systemImage) } }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .month: MonthView()
        case .herbarium: HerbariumView(landing: $landing)
        case .me: SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environment(Vault(keyStore: InMemoryKeyStore(), fileURL: URL.temporaryDirectory.appending(path: "preview.fallow")))
        .environment(Backup(store: FolderBackupStore(url: URL.temporaryDirectory.appending(path: "preview.backup")), keys: InMemoryBackupKey()))
}
