import SwiftUI

/// Today: the month intention on top, then what today holds.
struct TodayView: View {
    @Environment(Vault.self) private var vault
    @State private var planning: MonthPlan?

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
                }
            }

            NotebookCard {
                SpecimenLabel(text: "Today")
                Text("Your small rhythms for the day will live here.")
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .sheet(item: $planning) { plan in
            PlannerView(plan: plan)
        }
    }
}
