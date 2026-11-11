import SwiftUI

/// Temporary screens. Each one is replaced by its own feature PR.
struct TodayView: View {
    var body: some View {
        NotebookPage {
            SpecimenLabel(text: "This month")
            Text("Your intention for the month will be written here.")
                .font(.notebookTitle(.title2).italic())
                .foregroundStyle(Theme.moss)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.sage).frame(width: 2)
                }
            NotebookCard {
                SpecimenLabel(text: "Today")
                Text("Your small rhythms for the day will live here.")
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

struct MonthView: View {
    var body: some View {
        ComingSoon(text: "Plan the month, set an intention and reflect at the end.")
    }
}

struct HerbariumView: View {
    var body: some View {
        ComingSoon(text: "Pressed plants you collect along the way.")
    }
}

/// A scrolling page on notebook paper.
struct NotebookPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
    }
}

struct ComingSoon: View {
    let text: LocalizedStringResource

    var body: some View {
        ContentUnavailableView {
            Label { Text("Coming soon").font(.notebookTitle(.title2)) } icon: {
                Image(systemName: "leaf").foregroundStyle(Theme.sage)
            }
        } description: {
            Text(text).foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
