import SwiftUI
import UIKit

/// "Field notebook" identity: pale sage paper, ink green, botanical serif titles.
/// Every colour has a light and a dark variant in the asset catalog.
enum Theme {
    static let paper = Color("Paper")
    static let card = Color("Card")
    static let cardBorder = Color("CardBorder")
    static let ink = Color("Ink")
    static let inkMuted = Color("InkMuted")
    static let sage = Color("Sage")
    static let moss = Color("Moss")

    /// Navigation and tab bars use the paper colour and serif titles.
    /// Called once at launch, before the first view is drawn.
    @MainActor
    static func applyBarAppearance() {
        let ink = UIColor(named: "Ink") ?? .label
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(named: "Paper")
        nav.largeTitleTextAttributes = [.font: serifFont(.largeTitle), .foregroundColor: ink]
        nav.titleTextAttributes = [.font: serifFont(.headline), .foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(named: "Paper")
        tab.shadowColor = UIColor(named: "CardBorder")
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    /// The system serif (New York), scaled with Dynamic Type.
    private static func serifFont(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        let serif = base.withDesign(.serif) ?? base
        return UIFont(descriptor: serif, size: 0)
    }
}

extension Font {
    /// Serif title, like a heading in a botanist's notebook.
    static func notebookTitle(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif)
    }

    /// Small monospaced label, like a specimen tag.
    static let specimenLabel = Font.system(.caption2, design: .monospaced).weight(.medium)
}

/// A card on the notebook page: lighter paper with a thin border.
struct NotebookCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
    }
}

/// Uppercase specimen-tag label.
struct SpecimenLabel: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(.specimenLabel)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Theme.inkMuted)
    }
}
