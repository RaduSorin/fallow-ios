import SwiftUI

/// The month: its intention, its Fridays, the reflection, and the next month when it is near.
struct MonthView: View {
    @Environment(Vault.self) private var vault
    @Environment(Router.self) private var router
    @State private var planning: MonthPlan?
    @State private var reflecting: MonthID?

    private var month: MonthID { .current() }
    private var contents: VaultContents? { vault.contents }
    private var plan: MonthPlan? { contents?.plan(for: month) }
    private var todayKey: String { DayKey.string(.now) }

    var body: some View {
        NotebookPage {
            Text(month.nameWithYear).specimen()

            intention

            if let plan, !plan.fridays.isEmpty {
                fridays(plan)
            }

            if let plan, !plan.fridays.isEmpty {
                NotebookCard {
                    SpecimenLabel(text: "Fridays so far")
                    FeelingChart(notes: contents?.notes(in: month) ?? [])
                }
            }

            reflectionCard

            if showNextMonth {
                NotebookCard {
                    SpecimenLabel(text: "Coming up")
                    Text("Plan \(month.next.name)")
                        .font(.notebookTitle(.title3))
                    Text("The intention and the Fridays for the month ahead.")
                        .foregroundStyle(Theme.inkMuted)
                    Button {
                        planning = contents?.plan(for: month.next) ?? .blank(month.next)
                    } label: {
                        Text("Plan next month")
                    }
                }
            }
        }
        .sheet(item: $planning) { plan in
            PlannerView(plan: plan)
        }
        .sheet(item: $reflecting) { month in
            ReflectionView(month: month)
        }
        .onChange(of: router.pending, initial: true) { _, route in
            // The first Monday of a month: its notification opens the reflection.
            guard route == .reflection else { return }
            router.pending = nil
            reflecting = reflectionMonth
        }
    }

    @ViewBuilder
    private var intention: some View {
        if let plan, !plan.intention.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SpecimenLabel(text: "Intention")
                IntentionLine(text: plan.intention, sign: plan.success)
                Button {
                    planning = plan
                } label: {
                    Text("Change the plan")
                }
                .font(.subheadline)
            }
        } else {
            NotebookCard {
                Text("No intention yet for \(month.name).")
                    .font(.notebookTitle(.title3))
                Text("Choose one intention, the sign that it went well, and what each Friday is for.")
                    .foregroundStyle(Theme.inkMuted)
                Button {
                    planning = plan ?? .blank(month)
                } label: {
                    Text("Plan the month")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func fridays(_ plan: MonthPlan) -> some View {
        let written = Set(contents?.notes(in: month).filter { $0.kind == .friday }.map(\.date) ?? [])
        let nextDate = plan.fridays.first { $0.date >= todayKey }?.date
        return VStack(alignment: .leading, spacing: 8) {
            SpecimenLabel(text: "Fridays")
            NotebookCard {
                ForEach(plan.fridays) { friday in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(friday.dayName)
                            .font(.specimenLabel)
                            .foregroundStyle(Theme.inkMuted)
                            .frame(width: 92, alignment: .leading)
                        Text(friday.title.isEmpty ? String(localized: "Free") : friday.title)
                            .fontWeight(friday.date == nextDate ? .semibold : .regular)
                            .foregroundStyle(friday.date < todayKey ? Theme.inkMuted : Theme.ink)
                        Spacer(minLength: 0)
                        if written.contains(friday.date) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.moss)
                                .accessibilityLabel(Text("Note written"))
                        }
                    }
                    if friday.id != plan.fridays.last?.id {
                        Divider().overlay(Theme.cardBorder)
                    }
                }
            }
        }
    }

    /// Looking back: the month that just ended during its first week, else this one.
    private var reflectionMonth: MonthID {
        let day = Calendar.current.component(.day, from: .now)
        return day <= 7 && contents?.plan(for: month.previous) != nil ? month.previous : month
    }

    private var reflectionCard: some View {
        let target = reflectionMonth
        let done = contents?.reflection(for: target) != nil
        return NotebookCard {
            SpecimenLabel(text: "Reflection")
            Group {
                if done {
                    Text("Your reflection on \(target.name) is written.")
                } else {
                    Text("Look back on \(target.name).")
                }
            }
            .font(.notebookTitle(.title3))
            Text("Four questions about what changed and what worked, then the next intention.")
                .foregroundStyle(Theme.inkMuted)
            Button {
                reflecting = target
            } label: {
                if done {
                    Text("Read or change it")
                } else {
                    Text("Start the reflection")
                }
            }
        }
    }

    /// The next month can be planned in the last week, or once no Friday is left.
    private var showNextMonth: Bool {
        guard contents?.plan(for: month.next) == nil else { return false }
        let day = Calendar.current.component(.day, from: .now)
        let fridaysLeft = month.fridays().filter { DayKey.string($0) >= todayKey }.count
        return day >= 24 || fridaysLeft == 0
    }
}
