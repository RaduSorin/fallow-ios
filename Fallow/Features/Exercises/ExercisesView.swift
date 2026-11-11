import SwiftUI
import UniformTypeIdentifiers

/// The person's own exercise bank: packs they imported (and maybe changed) and their own.
struct ExercisesView: View {
    @Environment(Vault.self) private var vault
    @State private var editing: Exercise?
    @State private var importing = false
    @State private var importMessage: LocalizedStringResource?

    private struct BankGroup: Identifiable {
        let title: String?
        let items: [Exercise]
        var id: String { title ?? "" }
    }

    private var groups: [BankGroup] {
        let all = vault.contents?.sortedExercises ?? []
        var order: [String?] = []
        for exercise in all where !order.contains(exercise.packTitle) { order.append(exercise.packTitle) }
        return order.map { title in BankGroup(title: title, items: all.filter { $0.packTitle == title }) }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Section {
                    Text("Your bank is empty. Write your own exercises, or import a pack file someone shared with you.")
                        .foregroundStyle(Theme.inkMuted)
                }
                .listRowBackground(Theme.card)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { exercise in
                        NavigationLink {
                            ExerciseDetail(exerciseID: exercise.id)
                        } label: {
                            ExerciseRow(exercise: exercise)
                        }
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    if let title = group.title { Text(title) } else { Text("My own") }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(Text("Exercises"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = Exercise(title: "")
                    } label: {
                        Label { Text("Write an exercise") } icon: { Image(systemName: "square.and.pencil") }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label { Text("Import a pack file") } icon: { Image(systemName: "square.and.arrow.down") }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add"))
            }
        }
        .sheet(item: $editing) { exercise in
            ExerciseEditor(exercise: exercise, isNew: true)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert(
            Text(importMessage ?? ""),
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
        ) {
            Button { } label: { Text("OK") }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let pack = try ExercisePack.decode(try Data(contentsOf: url))
            var added = 0
            try vault.update { added = $0.importPack(pack) }
            importMessage = "Imported \(pack.title): \(added) new exercises."
        } catch ExercisePack.PackError.empty {
            importMessage = "This pack has no exercises."
        } catch {
            importMessage = "This file is not an exercise pack."
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.title).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                if let category = exercise.category { Text(category) }
                if let minutes = exercise.minutes { Text("\(minutes) min") }
                if exercise.edited == true { Text("Changed") }
            }
            .font(.specimenLabel)
            .foregroundStyle(Theme.inkMuted)
        }
    }
}

/// Reads one exercise. The steps are shown as written, one paragraph at a time.
struct ExerciseDetail: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    let exerciseID: String
    @State private var editing = false

    private var exercise: Exercise? { vault.contents?.exercise(exerciseID) }

    var body: some View {
        NotebookPage {
            if let exercise {
                HStack(spacing: 8) {
                    if let category = exercise.category { Text(category).specimen() }
                    if let minutes = exercise.minutes { Text("\(minutes) min").specimen() }
                }
                Text(exercise.title).font(.notebookTitle())
                ForEach(Array(paragraphs(exercise.steps).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let pack = exercise.packTitle {
                    Text("From \(pack)").specimen()
                }
            } else {
                Text("This exercise is no longer in your bank.")
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .toolbar {
            if exercise != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = true } label: { Text("Edit") }
                }
            }
        }
        .sheet(isPresented: $editing) {
            if let exercise {
                ExerciseEditor(exercise: exercise, isNew: false)
            }
        }
    }

    private func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Writes or changes one exercise.
struct ExerciseEditor: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Exercise
    @State private var failed = false
    @State private var confirmDelete = false
    private let isNew: Bool

    init(exercise: Exercise, isNew: Bool) {
        _draft = State(initialValue: exercise)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft.title) { Text("Title") }
                    TextField(text: Binding(
                        get: { draft.category ?? "" },
                        set: { draft.category = $0.isEmpty ? nil : $0 }
                    )) { Text("Category, e.g. Self-compassion") }
                    Stepper(value: Binding(
                        get: { draft.minutes ?? 0 },
                        set: { draft.minutes = $0 == 0 ? nil : $0 }
                    ), in: 0...120, step: 5) {
                        if let minutes = draft.minutes { Text("\(minutes) min") } else { Text("No duration") }
                    }
                }
                Section {
                    TextField(text: $draft.steps, axis: .vertical) {
                        Text("What to do. Leave an empty line between steps.")
                    }
                    .lineLimit(8...30)
                } header: {
                    Text("Steps")
                } footer: {
                    if draft.packId != nil {
                        Text("Changed exercises stay as you wrote them when the pack is imported again.")
                    }
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: { Text("Delete exercise") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(isNew ? Text("New exercise") : Text("Edit exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog(Text("Delete this exercise?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(role: .destructive) { delete() } label: { Text("Delete exercise") }
            } message: {
                Text("Fridays that used it keep its title.")
            }
            .alert(Text("The exercise could not be saved."), isPresented: $failed) {
                Button { } label: { Text("OK") }
            }
        }
    }

    private func save() {
        var exercise = draft
        exercise.title = exercise.title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try vault.update { $0.save(exercise) }
            dismiss()
        } catch {
            failed = true
        }
    }

    private func delete() {
        do {
            try vault.update { $0.deleteExercise(draft.id) }
            dismiss()
        } catch {
            failed = true
        }
    }
}
