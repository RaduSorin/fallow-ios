import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

/// "Moments from your days": Apple's journaling suggestions (photos, walks, places, music).
/// Apple shows them in its own sheet; Fallow only gets the one the person picks, and keeps
/// just its title as a starting line. Not available in the Simulator, so nothing shows there.
struct MomentsPicker: View {
    let onPick: @MainActor (String) -> Void

    var body: some View {
        #if canImport(JournalingSuggestions)
        Section {
            JournalingSuggestionsPicker {
                Label { Text("Moments from your days") } icon: { Image(systemName: "sparkles") }
            } onCompletion: { suggestion in
                let title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                await MainActor.run { onPick(title) }
            }
        } footer: {
            Text("Apple suggests moments from your photos, walks and places. Only the one you pick comes into the note.")
        }
        #else
        EmptyView()
        #endif
    }
}
