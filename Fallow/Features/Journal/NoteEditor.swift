import SwiftUI

/// Writes or changes one note. A Friday note also asks how strong the feeling was
/// before and after (0 to 10) and whether the exercise fitted.
struct NoteEditor: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Note
    @State private var rated: Bool
    @State private var failed = false
    private let isNew: Bool

    init(note: Note, isNew: Bool) {
        _draft = State(initialValue: note)
        _rated = State(initialValue: note.before != nil || note.after != nil)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.kind == .friday {
                    if let title = draft.title, !title.isEmpty {
                        Section {
                            Text(title).font(.notebookTitle(.title3))
                        } header: {
                            Text("Tonight's exercise")
                        }
                    }

                    Section {
                        Toggle(isOn: $rated) { Text("Note how strong the feeling was") }
                        if rated {
                            scale(title: "Before", value: $draft.before)
                            scale(title: "After", value: $draft.after)
                        }
                    } footer: {
                        Text("0 is calm, 10 is as strong as it gets.")
                    }

                    Section {
                        Picker(selection: $draft.fit) {
                            Text("Not answered").tag(NoteFit?.none)
                            ForEach(NoteFit.allCases) { fit in
                                Text(fit.label).tag(NoteFit?.some(fit))
                            }
                        } label: {
                            Text("Did it fit?")
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Did it fit?")
                    }
                }

                Section {
                    TextField(text: $draft.text, axis: .vertical) {
                        Text("What do you want to remember?")
                    }
                    .lineLimit(5...20)
                } header: {
                    Text("Note")
                }

                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            delete()
                        } label: {
                            Text("Delete note")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(Text(DayKey.date(draft.date)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? draft.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        .disabled(!canSave)
                }
            }
            .alert(Text("The note could not be saved."), isPresented: $failed) {
                Button { } label: { Text("OK") }
            }
        }
    }

    private var canSave: Bool {
        !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (draft.kind == .friday && (rated || draft.fit != nil))
    }

    private func scale(title: LocalizedStringResource, value: Binding<Int?>) -> some View {
        let current = value.wrappedValue ?? 5
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(current)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.moss)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue ?? 5) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...10,
                step: 1
            ) {
                Text(title)
            }
        }
        .onAppear {
            if value.wrappedValue == nil { value.wrappedValue = 5 }
        }
    }

    private func save() {
        var note = draft
        note.text = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rated {
            note.before = nil
            note.after = nil
        }
        do {
            try vault.update { $0.save(note) }
            dismiss()
        } catch {
            failed = true
        }
    }

    private func delete() {
        do {
            try vault.update { $0.deleteNote(draft.id) }
            dismiss()
        } catch {
            failed = true
        }
    }
}

/// One note as a row: the kind, the first lines, the before/after change.
struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Group {
                    switch note.kind {
                    case .friday: Text("Friday")
                    case .free: Text("Note")
                    case .worry: Text("Worry list")
                    case .reflection: Text("Reflection")
                    }
                }
                .font(.specimenLabel)
                .textCase(.uppercase)
                .foregroundStyle(Theme.inkMuted)
                if let before = note.before, let after = note.after {
                    Text("\(before) → \(after)")
                        .font(.specimenLabel)
                        .foregroundStyle(Theme.moss)
                }
            }
            if let title = note.title, !title.isEmpty, note.kind == .friday {
                Text(title).font(.notebookTitle(.headline))
            }
            if !note.text.isEmpty {
                Text(note.text)
                    .lineLimit(3)
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
