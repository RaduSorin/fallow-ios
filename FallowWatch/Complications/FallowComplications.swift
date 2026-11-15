import SwiftUI
import WidgetKit

/// Complications for the watch face. They read the copy of the iPhone's snapshot that the watch
/// app keeps, so they show only dates and counts, plus the month's intention when the person
/// turned it on for widgets.
@main
struct FallowComplicationsBundle: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var relevance: TimelineEntryRelevance? {
        snapshot.map { TimelineEntryRelevance(score: SmartStack.score($0, at: date)) }
    }
}

/// When the Smart Stack should lift Fallow up: Friday evening with an exercise, Monday morning
/// with the worry list, the first week's reflection, and evenings with rhythms still open.
enum SmartStack {
    static func score(_ snapshot: WidgetSnapshot, at date: Date, calendar: Calendar = .current) -> Float {
        let hour = calendar.component(.hour, from: date)
        let evening = (18..<22).contains(hour)
        switch snapshot.focus(on: date, calendar: calendar) {
        case .fridayExercise where evening: return 80
        case .worryList where (8..<12).contains(hour): return 60
        case .reflection where evening: return 50
        default: break
        }
        let open = snapshot.rhythmCount - snapshot.done(on: DayKey.string(date, calendar: calendar)).count
        return evening && open > 0 ? 30 : 1
    }

    /// The hours the score can change at, from now until two days on.
    static func turns(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        var out: [Date] = []
        for day in 0...2 {
            guard let start = calendar.date(byAdding: .day, value: day, to: today) else { continue }
            for hour in [0, 8, 12, 18, 22] {
                if let turn = calendar.date(byAdding: .hour, value: hour, to: start), turn > now { out.append(turn) }
            }
        }
        return out
    }
}

/// One entry now and one at each turn of the Smart Stack score (midnight included) for two days.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .complicationPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? .complicationPreview : SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let now = Date.now
        let entries = [ComplicationEntry(date: now, snapshot: snapshot)]
            + SmartStack.turns(from: now).map { ComplicationEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    static var complicationPreview: WidgetSnapshot {
        var snapshot = WidgetSnapshot(writtenAt: .now)
        let today = DayKey.string(.now)
        snapshot.fridays = [today]
        snapshot.fridaysWithExercise = [today]
        snapshot.rhythmCount = 3
        snapshot.rhythmDay = today
        snapshot.rhythmsDone = ["a", "b"]
        return snapshot
    }
}

struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.fallow.watch.today", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName(Text("Today in Fallow"))
        .description(Text("Your rhythms and what the day holds, without anything you wrote."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var day: String { DayKey.string(entry.date) }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            let focus = snapshot.focus(on: entry.date)
            let done = snapshot.done(on: day).count
            switch family {
            case .accessoryCircular:
                ring(done: done, total: snapshot.rhythmCount)
            case .accessoryCorner:
                Image(systemName: "leaf")
                    .font(.title3)
                    .foregroundStyle(WatchPalette.moss)
                    .widgetLabel {
                        if snapshot.rhythmCount > 0 {
                            Gauge(value: Double(min(done, snapshot.rhythmCount)), in: 0...Double(snapshot.rhythmCount)) {
                                Text(verbatim: "")
                            } currentValueLabel: {
                                Text(verbatim: "\(done)/\(snapshot.rhythmCount)")
                            }
                            .tint(WatchPalette.moss)
                        } else {
                            Text(focus.label)
                        }
                    }
            case .accessoryInline:
                // The intention when it may show, else what the day holds.
                Label {
                    Text(snapshot.intention.flatMap { $0.isEmpty ? nil : $0 } ?? focus.title)
                } icon: {
                    Image(systemName: "leaf")
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf")
                        Text(focus.label).textCase(.uppercase)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WatchPalette.moss)
                    Text(focus.title)
                        .font(.headline)
                        .italic(focus.isIntention)
                        .lineLimit(2)
                    if snapshot.rhythmCount > 0 {
                        Text("\(done) of \(snapshot.rhythmCount) rhythms").font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryCircular, .accessoryCorner:
                Image(systemName: "leaf")
            default:
                Text("Open Fallow on your iPhone")
            }
        }
    }

    private func ring(done: Int, total: Int) -> some View {
        Gauge(value: Double(min(done, max(total, 1))), in: 0...Double(max(total, 1))) {
            Image(systemName: "leaf")
        } currentValueLabel: {
            if total > 0 {
                Text(verbatim: "\(done)")
            } else {
                Image(systemName: "leaf")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(WatchPalette.moss)
    }
}
