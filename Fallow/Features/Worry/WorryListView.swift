import SwiftUI

/// The weekly worry list, as a guided form: write it down, sort into stone and clay,
/// order the clay, pick one small step, then the Good Parent's three questions.
struct WorryListView: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case list, sort, clay, step, parent
    }

    @State private var step: Step = .list
    @State private var text = ""
    @State private var stoneItems: Set<String> = []
    @State private var clay: [String] = []
    @State private var breakdown: [String] = ["", "", ""]
    @State private var firstStep = ""
    @State private var parent = WorryList.GoodParent()
    @State private var failed = false

    private var items: [String] { WorryList.items(from: text) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Step.allCases, id: \.rawValue) { s in
                        Capsule()
                            .fill(s.rawValue <= step.rawValue ? Theme.moss : Theme.cardBorder)
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityElement()
                .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        page
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                footer.padding(20)
            }
            .background(Theme.paper)
            .navigationTitle(Text("Worry list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
            }
            .alert(Text("The list could not be saved."), isPresented: $failed) {
                Button { } label: { Text("OK") }
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .list:
            Text("What is on your mind?").font(.notebookTitle())
            Text("One thing per line. Short words are enough, like \"the deadline at work\".")
                .foregroundStyle(Theme.inkMuted)
            TextField(text: $text, axis: .vertical) {
                Text("The deadline at work\nThe dentist appointment\nThe weekend weather")
            }
            .lineLimit(6...14)
            .accessibilityIdentifier("worry.text")
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))

        case .sort:
            Text("Stone or clay?").font(.notebookTitle())
            Text("Clay is up to you, stone is not. When unsure, ask: which part of this can I influence?")
                .foregroundStyle(Theme.inkMuted)
            NotebookCard {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)
                        Spacer()
                        Picker(selection: Binding(
                            get: { stoneItems.contains(item) },
                            set: { isStone in
                                if isStone { stoneItems.insert(item) } else { stoneItems.remove(item) }
                            }
                        )) {
                            Text("Clay").tag(false)
                            Text("Stone").tag(true)
                        } label: {
                            Text(item)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
            }

        case .clay:
            Text("The clay, biggest first").font(.notebookTitle())
            Text("Move what weighs most to the top. Then break the biggest one into small steps.")
                .foregroundStyle(Theme.inkMuted)
            if clay.isEmpty {
                Text("Everything is stone this week. That is fine: the Good Parent's questions still help.")
                    .foregroundStyle(Theme.inkMuted)
            } else {
                NotebookCard {
                    ForEach(Array(clay.enumerated()), id: \.element) { index, item in
                        HStack {
                            Text(item).fontWeight(index == 0 ? .semibold : .regular)
                            Spacer()
                            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                                .accessibilityLabel(Text("Move up"))
                            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == clay.count - 1)
                                .accessibilityLabel(Text("Move down"))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                SpecimenLabel(text: "Small steps for the biggest one")
                ForEach(breakdown.indices, id: \.self) { index in
                    TextField(text: $breakdown[index]) { Text("Step \(index + 1)") }
                        .textFieldStyle(.roundedBorder)
                }
            }

        case .step:
            Text("One small step").font(.notebookTitle())
            Text("Something you can do in ten minutes or less, this week.")
                .foregroundStyle(Theme.inkMuted)
            let options = breakdown.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } + clay
            if !options.isEmpty {
                NotebookCard {
                    ForEach(options, id: \.self) { option in
                        Button {
                            firstStep = option
                        } label: {
                            HStack {
                                Image(systemName: firstStep == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(Theme.moss)
                                Text(option).foregroundStyle(Theme.ink)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField(text: $firstStep) { Text("Or write your own") }
                .textFieldStyle(.roundedBorder)

        case .parent:
            Text("The Good Parent").font(.notebookTitle())
            Text("Answer the way a kind, steady parent would answer a child who is worried.")
                .foregroundStyle(Theme.inkMuted)
            parentField("What is happening?", text: Binding(get: { parent.what ?? "" }, set: { parent.what = $0 }))
            parentField("What is hardest about it?", text: Binding(get: { parent.hardest ?? "" }, set: { parent.hardest = $0 }))
            parentField("What do I need right now?", text: Binding(get: { parent.need ?? "" }, set: { parent.need = $0 }))
        }
    }

    private func parentField(_ title: LocalizedStringResource, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextField(text: text, axis: .vertical) { Text("Write as much or as little as you like") }
                .lineLimit(2...6)
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
        }
    }

    private var footer: some View {
        HStack {
            if step != .list {
                Button {
                    if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
                } label: { Text("Back") }
            }
            Spacer()
            if step == .parent {
                Button { save() } label: { Text("Save to journal").padding(.horizontal, 8) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { advance() } label: { Text("Continue").padding(.horizontal, 8) }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == .list && items.isEmpty)
            }
        }
    }

    private func advance() {
        if step == .sort {
            // Keep an order already chosen, add new clay at the end.
            let wanted = items.filter { !stoneItems.contains($0) }
            clay = clay.filter { wanted.contains($0) } + wanted.filter { !clay.contains($0) }
        }
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard clay.indices.contains(target) else { return }
        clay.swapAt(index, target)
    }

    private func save() {
        let clean = { (value: String?) -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let list = WorryList(
            stone: items.filter { stoneItems.contains($0) },
            clay: clay,
            breakdown: breakdown.compactMap(clean),
            step: clean(firstStep),
            parent: .init(what: clean(parent.what), hardest: clean(parent.hardest), need: clean(parent.need))
        )
        var note = Note(date: DayKey.string(.now), month: .current(), kind: .worry)
        note.title = String(localized: "Worry list")
        note.worry = list
        note.text = list.summary()
        do {
            try vault.update { $0.save(note) }
            dismiss()
        } catch {
            failed = true
        }
    }
}
