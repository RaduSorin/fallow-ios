import SwiftUI

/// Temporary screens. Each one is replaced by its own feature PR.
struct TodayView: View {
    var body: some View {
        ComingSoon(text: "Your intention for the month and today's rhythm will live here.")
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

struct ComingSoon: View {
    let text: LocalizedStringResource

    var body: some View {
        ContentUnavailableView {
            Label { Text("Coming soon") } icon: { Image(systemName: "leaf") }
        } description: {
            Text(text)
        }
    }
}
