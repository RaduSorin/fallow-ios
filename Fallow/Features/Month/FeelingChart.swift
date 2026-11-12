import Charts
import SwiftUI

/// How strong the feeling was before and after each Friday exercise this month:
/// a line from "before" down (or up) to "after", one per Friday.
struct FeelingChart: View {
    let notes: [Note]

    private var points: [FeelingPoint] { LookBack.feelings(notes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if points.isEmpty {
                Text("After a Friday exercise, note how strong the feeling was before and after. The change shows here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                chart
                legend
                summary
            }
            fits
        }
    }

    private var chart: some View {
        Chart(points) { point in
            let day = dayLabel(point.day)
            RuleMark(
                x: .value("Friday", day),
                yStart: .value("Before", point.before),
                yEnd: .value("After", point.after)
            )
            .foregroundStyle(Theme.sage)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            PointMark(x: .value("Friday", day), y: .value("Before", point.before))
                .symbol(.circle)
                .symbolSize(70)
                .foregroundStyle(Theme.sage)
            PointMark(x: .value("Friday", day), y: .value("After", point.after))
                .symbol(.circle)
                .symbolSize(70)
                .foregroundStyle(Theme.moss)
        }
        .chartYScale(domain: 0...10)
        .chartYAxis {
            AxisMarks(values: [0, 5, 10]) { _ in
                AxisGridLine().foregroundStyle(Theme.cardBorder)
                AxisValueLabel()
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("How strong the feeling was before and after each Friday exercise"))
        .accessibilityValue(Text(points.map { "\(dayLabel($0.day)): \($0.before) → \($0.after)" }.joined(separator: ", ")))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label { Text("Before") } icon: { Circle().fill(Theme.sage).frame(width: 8, height: 8) }
            Label { Text("After") } icon: { Circle().fill(Theme.moss).frame(width: 8, height: 8) }
            Spacer()
            Text("0 calm · 10 strongest")
        }
        .font(.caption)
        .foregroundStyle(Theme.inkMuted)
    }

    @ViewBuilder
    private var summary: some View {
        if let average = LookBack.averageChange(points) {
            Group {
                if average > 0.05 {
                    Text("After the exercise the feeling eased by \(average, format: .number.precision(.fractionLength(1))) points on average.")
                } else if average < -0.05 {
                    Text("After the exercise the feeling grew by \(-average, format: .number.precision(.fractionLength(1))) points on average. That is worth noticing too.")
                } else {
                    Text("On average the feeling stayed about the same after the exercise.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
        }
    }

    @ViewBuilder
    private var fits: some View {
        let counts = LookBack.fits(notes)
        if !counts.isEmpty {
            HStack(spacing: 12) {
                ForEach(NoteFit.allCases) { fit in
                    HStack(spacing: 4) {
                        Text(fit.label)
                        Text("\(counts[fit] ?? 0)").monospacedDigit().foregroundStyle(Theme.moss)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.inkMuted)
        }
    }

    private func dayLabel(_ key: String) -> String {
        DayKey.date(key)?.formatted(.dateTime.day().month(.abbreviated)) ?? key
    }
}
