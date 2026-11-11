import SwiftUI

/// Plans one month: intention, the sign of success, how many Fridays make it good, and each Friday.
struct PlannerView: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MonthPlan
    @State private var failed = false

    init(plan: MonthPlan) {
        _draft = State(initialValue: plan)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(text: $draft.intention, axis: .vertical) {
                        Text("e.g. Make room for slowness")
                    }
                    .font(.notebookTitle(.title3))
                    .lineLimit(2...5)
                } header: {
                    Text("Intention")
                } footer: {
                    Text("One sentence you will see every day this month.")
                }

                Section {
                    TextField(text: Binding(
                        get: { draft.success ?? "" },
                        set: { draft.success = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical) {
                        Text("e.g. I'm in bed before 11")
                    }
                    if !draft.fridays.isEmpty {
                        Stepper(value: Binding(
                            get: { draft.target ?? 0 },
                            set: { draft.target = $0 == 0 ? nil : $0 }
                        ), in: 0...draft.fridays.count) {
                            if let target = draft.target {
                                Text("A good month: \(target) of \(draft.fridays.count) Fridays")
                            } else {
                                Text("No Friday target")
                            }
                        }
                    }
                } header: {
                    Text("The sign")
                } footer: {
                    Text("How will you know the month went well? You will be asked at the end.")
                }

                if !draft.fridays.isEmpty {
                    Section {
                        ForEach($draft.fridays) { $friday in
                            LabeledContent {
                                TextField(text: $friday.title) {
                                    Text("Free")
                                }
                                .multilineTextAlignment(.trailing)
                            } label: {
                                Text(friday.dayName)
                            }
                        }
                    } header: {
                        Text("Fridays")
                    } footer: {
                        Text("A theme or an exercise for each Friday evening. Leave one empty to keep it free.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(Text(draft.id.nameWithYear))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                        .disabled(draft.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(Text("The plan could not be saved."), isPresented: $failed) {
                Button { } label: { Text("OK") }
            }
        }
    }

    private func save() {
        var plan = draft
        plan.intention = plan.intention.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.savedAt = .now
        do {
            try vault.update { $0.save(plan) }
            dismiss()
        } catch {
            failed = true
        }
    }
}
