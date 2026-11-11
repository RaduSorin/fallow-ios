import SwiftUI

/// Today's small rhythms: tap to mark one kept. The dots show the last seven days, nothing more.
struct RhythmsCard: View {
    @Environment(Vault.self) private var vault
    @State private var editing = false

    private var todayKey: String { DayKey.string(.now) }
    private var rhythms: [Rhythm] { vault.contents?.rhythms ?? [] }

    var body: some View {
        NotebookCard {
            HStack {
                SpecimenLabel(text: "Rhythms")
                Spacer()
                Button {
                    editing = true
                } label: {
                    if rhythms.isEmpty { Text("Add") } else { Text("Edit") }
                }
                .font(.subheadline)
            }
            if rhythms.isEmpty {
                Text("A few small things you want to do most days, like a walk without the phone. Missing a day costs nothing.")
                    .foregroundStyle(Theme.inkMuted)
            }
            ForEach(rhythms) { rhythm in
                row(rhythm)
            }
        }
        .sheet(isPresented: $editing) {
            RhythmsEditor()
        }
    }

    private func row(_ rhythm: Rhythm) -> some View {
        let done = vault.contents?.rhythmsDone(on: todayKey).contains(rhythm.id) ?? false
        let week = vault.contents?.week(for: rhythm.id, endingOn: .now) ?? []
        return Button {
            try? vault.update { $0.toggleRhythm(rhythm.id, on: todayKey) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Theme.moss : Theme.sage)
                Text(rhythm.title)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, kept in
                        Circle()
                            .strokeBorder(Theme.sage, lineWidth: 1)
                            .background(Circle().fill(kept ? Theme.sage : .clear))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(done ? Text("Done today") : Text("Not yet today"))
    }
}

/// Adds and removes rhythms.
struct RhythmsEditor: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vault.contents?.rhythms ?? []) { rhythm in
                        Text(rhythm.title)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { vault.contents?.rhythms[$0].id }
                        try? vault.update { contents in ids.forEach { contents.removeRhythm($0) } }
                    }
                    HStack {
                        TextField(text: $newTitle) { Text("e.g. Walk without the phone") }
                            .onSubmit(add)
                        Button(action: add) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(Text("Add"))
                    }
                } footer: {
                    Text("Keep it to two or three. Swipe left to remove one.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(Text("Rhythms"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
    }

    private func add() {
        let title = newTitle
        try? vault.update { $0.addRhythm(title) }
        newTitle = ""
    }
}
