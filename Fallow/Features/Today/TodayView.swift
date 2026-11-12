import SwiftUI

/// Today: the month intention on top, then what today holds.
struct TodayView: View {
    @Environment(Vault.self) private var vault
    @Environment(ExerciseRun.self) private var run
    @Environment(Router.self) private var router
    @State private var planning: MonthPlan?
    @State private var writing: Note?
    @State private var worrying = false

    private var month: MonthID { .current() }
    private var plan: MonthPlan? { vault.contents?.plan(for: month) }
    private var todayKey: String { DayKey.string(.now) }
    private var todaysFriday: FridayPlan? { plan?.fridays.first { $0.date == todayKey } }

    var body: some View {
        NotebookPage {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide)).specimen()

            if let plan, !plan.intention.isEmpty {
                IntentionLine(text: plan.intention, sign: plan.success)
            } else {
                NotebookCard {
                    Text("No intention yet for \(month.name).")
                        .font(.notebookTitle(.title3))
                    Text("One sentence is enough: what do you want to give yourself this month?")
                        .foregroundStyle(Theme.inkMuted)
                    Button {
                        planning = plan ?? .blank(month)
                    } label: {
                        Text("Plan the month")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let friday = todaysFriday {
                NotebookCard {
                    SpecimenLabel(text: "Tonight")
                    Text(friday.title.isEmpty ? String(localized: "A free Friday") : friday.title)
                        .font(.notebookTitle(.title3))
                    if let exercise = vault.contents?.exercise(friday.exerciseId) {
                        Button {
                            run.start(exercise)
                        } label: {
                            Label { Text("Start the exercise") } icon: { Image(systemName: "play.fill") }
                        }
                        .buttonStyle(.borderedProminent)
                        NavigationLink {
                            ExerciseDetail(exerciseID: exercise.id)
                        } label: {
                            Text("Read it first")
                        }
                    }
                    Button {
                        writeFridayNote(friday)
                    } label: {
                        Text("Write after the exercise")
                    }
                }
            }

            RhythmsCard()

            worryCard

            notesToday
        }
        .sheet(item: $planning) { plan in
            PlannerView(plan: plan)
        }
        .sheet(isPresented: $worrying) {
            WorryListView()
        }
        .sheet(item: $writing) { note in
            let exists = vault.contents?.notes.contains { $0.id == note.id } ?? false
            NoteEditor(note: note, isNew: !exists)
        }
        .onChange(of: router.pending, initial: true) { _, route in
            follow(route)
        }
    }

    private func writeFridayNote(_ friday: FridayPlan) {
        writing = Note(
            date: todayKey, month: month, kind: .friday,
            exerciseId: friday.exerciseId, title: friday.title.isEmpty ? nil : friday.title
        )
    }

    /// Answers a tapped notification: Friday opens tonight's exercise (or the note when there is
    /// no exercise), Monday opens the worry list.
    private func follow(_ route: AppRoute?) {
        switch route {
        case .friday:
            router.pending = nil
            guard let friday = todaysFriday else { return }
            if let exercise = vault.contents?.exercise(friday.exerciseId) {
                if run.session == nil { run.start(exercise) }
            } else {
                writeFridayNote(friday)
            }
        case .worry:
            router.pending = nil
            worrying = true
        case .note:
            router.pending = nil
            writing = Note(date: todayKey, month: month, kind: .free)
        default:
            break
        }
    }

    private var worryCard: some View {
        let isMonday = Calendar.current.component(.weekday, from: .now) == 2
        return NotebookCard {
            SpecimenLabel(text: "Worry list")
            if isMonday {
                Text("Monday: sort the week's worries").font(.notebookTitle(.title3))
            }
            Text("Write down what weighs on you, then sort it into stone and clay.")
                .foregroundStyle(Theme.inkMuted)
            Button {
                worrying = true
            } label: {
                Text("Start the worry list")
            }
        }
    }

    private var notesToday: some View {
        let notes = vault.contents?.notes(on: todayKey) ?? []
        return NotebookCard {
            HStack {
                SpecimenLabel(text: "Notes")
                Spacer()
                NavigationLink {
                    JournalView()
                } label: {
                    Text("Journal")
                }
                .font(.subheadline)
            }
            ForEach(notes) { note in
                Button {
                    writing = note
                } label: {
                    NoteRow(note: note)
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.cardBorder)
            }
            Button {
                writing = Note(date: todayKey, month: month, kind: .free)
            } label: {
                Label { Text("Write a note") } icon: { Image(systemName: "square.and.pencil") }
            }
        }
    }
}
