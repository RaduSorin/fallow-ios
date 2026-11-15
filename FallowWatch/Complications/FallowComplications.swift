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
}

/// One entry now and one at each of the next two midnights, like the iPhone widget.
struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: .complicationPreview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: .now, snapshot: context.isPreview ? .complicationPreview : SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [ComplicationEntry(date: .now, snapshot: snapshot)]
        for offset in 1...2 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(ComplicationEntry(date: day, snapshot: snapshot))
            }
        }
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
