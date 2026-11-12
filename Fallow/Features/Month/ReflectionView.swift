import SwiftUI

/// The monthly reflection: a short summary, the sign, four questions.
struct ReflectionView: View {
    @Environment(Vault.self) private var vault
    @Environment(\.dismiss) private var dismiss

    let month: MonthID
    @State private var answers: [String: String] = [:]
    @State private var loaded = false
    @State private var failed = false

    private var plan: MonthPlan? { vault.contents?.plan(for: month) }
    private var summary: MonthSummary {
        MonthSummary(plan: plan, notes: vault.contents?.notes(in: month) ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                if let plan, !plan.intention.isEmpty {
                    Section {
                        IntentionLine(text: plan.intention, sign: plan.success)
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Your intention")
                    }
                }

                Section {
                    if summary.fridays > 0 {
                        LabeledContent {
                            Text("\(summary.fridaysDone) of \(summary.fridays)")
                                .monospacedDigit()
                        } label: {
                            Text("Fridays with a note")
                        }
                    }
                    if summary.reachedTarget {
                        Label { Text("You reached the target you set.") } icon: {
                            Image(systemName: "leaf.fill").foregroundStyle(Theme.sage)
                        }
                    }
                    LabeledContent {
                        Text("\(summary.notes)").monospacedDigit()
                    } label: {
                        Text("Notes this month")
                    }
                } header: {
                    Text("In short")
                }

                if summary.fridays > 0 {
                    Section {
                        FeelingChart(notes: vault.contents?.notes(in: month) ?? [])
                    } header: {
                        Text("Before and after")
                    }
                }

                if let sign = plan?.success, !sign.isEmpty {
                    Section {
                        Picker(selection: binding(ReflectionQuestion.signKey)) {
                            Text("Not answered").tag("")
                            Text("Yes").tag("yes")
                            Text("Not yet").tag("no")
                        } label: {
                            Text(sign)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } header: {
                        Text("Did you see the sign?")
                    } footer: {
                        Text("The sign: \(sign)")
                    }
                }

                ForEach(ReflectionQuestion.allCases) { question in
                    Section {
                        TextField(text: binding(question.rawValue), axis: .vertical) {
                            Text("Write as much or as little as you like")
                        }
                        .lineLimit(3...10)
                    } header: {
                        Text(question.prompt)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(Text("Reflection: \(month.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Text("Cancel") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Text("Save") }
                }
            }
            .alert(Text("The reflection could not be saved."), isPresented: $failed) {
                Button { } label: { Text("OK") }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                answers = vault.contents?.reflection(for: month)?.answers ?? [:]
            }
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { answers[key] ?? "" }, set: { answers[key] = $0 })
    }

    private func save() {
        let cleaned = answers
            .mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        let text = ReflectionQuestion.allCases.compactMap { question -> String? in
            guard let answer = cleaned[question.rawValue] else { return nil }
            return "\(String(localized: question.prompt))\n\(answer)"
        }.joined(separator: "\n\n")

        var note = vault.contents?.reflection(for: month)
            ?? Note(date: DayKey.string(.now), month: month, kind: .reflection)
        note.answers = cleaned
        note.text = text
        note.title = String(localized: "Reflection: \(month.name)")
        do {
            try vault.update { $0.save(note) }
            dismiss()
        } catch {
            failed = true
        }
    }
}
