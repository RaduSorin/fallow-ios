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

struct RootView: View {
    @State private var selection: AppTab = .today

    var body: some View {
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
        case .herbarium: HerbariumView()
        case .me: SettingsView()
        }
    }
}

#Preview {
    RootView()
}
