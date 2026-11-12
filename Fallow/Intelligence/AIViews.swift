import SwiftUI

/// In the reflection: "Summarize my month" with Apple Intelligence, made on this iPhone.
struct MonthSummarySection: View {
    let plan: MonthPlan?
    let notes: [Note]
    /// Adds the summary to the "What changed?" answer.
    let onUse: (String) -> Void

    @State private var summary: String?
    @State private var working = false
    @State private var failed = false

    var body: some View {
        Section {
            if let summary {
                Text(summary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { onUse(summary) } label: {
                    Label { Text("Add to “What changed?”") } icon: { Image(systemName: "text.badge.plus") }
                }
            }
            Button {
                Task { await run() }
            } label: {
                HStack {
                    Label {
                        if summary == nil { Text("Summarize my month") } else { Text("Try again") }
                    } icon: {
                        Image(systemName: "apple.intelligence")
                    }
                    if working {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(working || notes.isEmpty)
            if failed {
                Text("Apple Intelligence could not help this time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Made on this iPhone from your notes. Nothing leaves it.")
        }
    }

    private func run() async {
        working = true
        failed = false
        defer { working = false }
        do {
            summary = try await OnDeviceAI.monthSummary(plan: plan, notes: notes)
        } catch {
            failed = true
        }
    }
}

/// In the planner: three ideas for the intention, from the month before.
struct IntentionIdeasRow: View {
    let plan: MonthPlan?
    let notes: [Note]
    let onPick: (String) -> Void

    @State private var ideas: [String] = []
    @State private var working = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await run() }
            } label: {
                HStack {
                    Label { Text("Suggest intentions") } icon: { Image(systemName: "apple.intelligence") }
                    if working {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(working)
            ForEach(ideas, id: \.self) { idea in
                Button { onPick(idea) } label: {
                    Text(idea)
                        .font(.notebookTitle(.subheadline).italic())
                        .foregroundStyle(Theme.moss)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            if failed {
                Text("Apple Intelligence could not help this time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func run() async {
        working = true
        failed = false
        defer { working = false }
        do {
            ideas = try await OnDeviceAI.intentionIdeas(plan: plan, notes: notes)
        } catch {
            failed = true
        }
    }
}
