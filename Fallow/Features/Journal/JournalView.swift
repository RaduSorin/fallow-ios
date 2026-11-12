import SwiftUI

/// Every note, newest first, grouped by month.
struct JournalView: View {
    @Environment(Vault.self) private var vault
    @State private var editing: Note?
    @State private var query = ""

    private struct MonthGroup: Identifiable {
        let month: MonthID
        let notes: [Note]
        var id: MonthID { month }
    }

    private var groups: [MonthGroup] {
        let notes = (vault.contents?.notes ?? []).filter { $0.matches(query) }
        let byMonth = Dictionary(grouping: notes, by: \.month)
        return byMonth.keys.sorted(by: >).map { month in
            MonthGroup(
                month: month,
                notes: (byMonth[month] ?? []).sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            )
        }
    }

    var body: some View {
        List {
            if groups.isEmpty {
                Group {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("No notes yet. They appear here after you write one.")
                    } else {
                        Text("Nothing found for “\(query)”.")
                    }
                }
                .foregroundStyle(Theme.inkMuted)
                .listRowBackground(Theme.card)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.notes) { note in
                        Button {
                            editing = note
                        } label: {
                            NoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    Text(group.month.nameWithYear)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(Text("Journal"))
        .searchable(text: $query, prompt: Text("Search your notes"))
        .sheet(item: $editing) { note in
            if note.kind == .reflection {
                ReflectionView(month: note.month)
            } else {
                NoteEditor(note: note, isNew: false)
            }
        }
    }
}
