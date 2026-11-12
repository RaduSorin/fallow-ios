import AppIntents
import SwiftUI
import WidgetKit

struct FallowEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the snapshot the app left in the App Group. One entry now and one at each of the
/// next two midnights, so "tonight" and "Monday" change with the day.
struct FallowProvider: TimelineProvider {
    func placeholder(in context: Context) -> FallowEntry {
        FallowEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (FallowEntry) -> Void) {
        completion(FallowEntry(date: .now, snapshot: context.isPreview ? .preview : SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FallowEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [FallowEntry(date: .now, snapshot: snapshot)]
        for offset in 1...2 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(FallowEntry(date: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var snapshot = WidgetSnapshot(writtenAt: .now)
        let today = DayKey.string(.now)
        snapshot.fridays = [today]
        snapshot.fridaysWithExercise = [today]
        snapshot.monthFridays = 4
        snapshot.monthFridaysDone = 1
        snapshot.rhythmCount = 3
        snapshot.rhythmDay = today
        snapshot.rhythmsDone = ["a", "b"]
        return snapshot
    }
}

// MARK: Today

/// What tonight holds, the rhythms and the month, never anything the person wrote
/// (unless they chose to show the month's intention).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.fallow.ios.today", provider: FallowProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Today in Fallow"))
        .description(Text("What tonight holds and your rhythms, without anything you wrote."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FallowEntry

    private var day: String { DayKey.string(entry.date) }
    private var focus: WidgetFocus? {
        entry.snapshot.map {
            WidgetFocus.for($0, day: day, isMonday: Calendar.current.component(.weekday, from: entry.date) == 2)
        }
    }

    var body: some View {
        content
            .widgetURL(FallowLink.url(focus?.route ?? "today"))
            .containerBackground(for: .widget) { Palette.paper }
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot, let focus {
            switch family {
            case .accessoryInline:
                Label { Text(title(focus)) } icon: { Image(systemName: "leaf") }
            case .accessoryCircular:
                circular(snapshot)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(label(focus)).font(.caption2.weight(.semibold)).textCase(.uppercase)
                    Text(title(focus)).font(.headline).lineLimit(2)
                    if snapshot.rhythmCount > 0 {
                        Text("\(snapshot.done(on: day).count) of \(snapshot.rhythmCount) rhythms").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf").foregroundStyle(Palette.sage)
                        Text(label(focus))
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    titleText(focus)
                    Spacer(minLength: 0)
                    footer(snapshot)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            Text("Open Fallow once to fill this widget.")
                .font(.footnote)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    @ViewBuilder
    private func titleText(_ focus: WidgetFocus) -> some View {
        let text = Text(title(focus))
        if focus.isIntention {
            text.font(.system(family == .systemSmall ? .headline : .title3, design: .serif).italic())
                .foregroundStyle(Palette.moss)
                .lineLimit(family == .systemSmall ? 4 : 3)
        } else {
            text.font(.system(family == .systemSmall ? .headline : .title3, design: .serif))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if snapshot.rhythmCount > 0 {
                Text("\(snapshot.done(on: day).count) of \(snapshot.rhythmCount) rhythms")
            }
            if snapshot.monthFridays > 0 {
                Text("Fridays \(snapshot.monthFridaysDone)/\(snapshot.monthFridays)")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.inkMuted)
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        let total = max(snapshot.rhythmCount, 1)
        let done = snapshot.done(on: day).count
        return Gauge(value: Double(min(done, total)), in: 0...Double(total)) {
            Image(systemName: "leaf")
        } currentValueLabel: {
            if snapshot.rhythmCount > 0 {
                Text("\(done)")
            } else {
                Image(systemName: "leaf")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private func label(_ focus: WidgetFocus) -> LocalizedStringResource {
        switch focus {
        case .fridayExercise, .freeFriday: "Tonight"
        case .worryList: "Monday"
        case .reflection: "New month"
        case .nextFriday: "Next Friday"
        case .intention: "This month"
        case .quiet: "Fallow"
        }
    }

    private func title(_ focus: WidgetFocus) -> String {
        switch focus {
        case .fridayExercise: String(localized: "Friday exercise")
        case .freeFriday: String(localized: "A free Friday")
        case .worryList: String(localized: "Sort the week's worries")
        case .reflection: String(localized: "Look back on last month")
        case .nextFriday(let day):
            DayKey.date(day)?.formatted(.dateTime.weekday(.wide).day().month(.wide)) ?? day
        case .intention(let text): text
        case .quiet: String(localized: "A quiet day")
        }
    }
}

// MARK: Rhythms

/// Today's rhythms with a button each. Only when the person turned it on in Fallow,
/// because the titles then live outside the vault.
struct RhythmsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.fallow.ios.rhythms", provider: FallowProvider()) { entry in
            RhythmsWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Rhythms"))
        .description(Text("Tick today's small rhythms without opening Fallow."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RhythmsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FallowEntry

    private var day: String { DayKey.string(entry.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "leaf").foregroundStyle(Palette.sage)
                Text("Rhythms")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkMuted)
            }
            if let snapshot = entry.snapshot, let rhythms = snapshot.rhythms {
                if rhythms.isEmpty {
                    Text("No rhythms yet.")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                } else {
                    let done = Set(snapshot.done(on: day))
                    ForEach(rhythms.prefix(family == .systemSmall ? 3 : 4)) { rhythm in
                        Button(intent: ToggleRhythmIntent(rhythmID: rhythm.id, day: day)) {
                            HStack(spacing: 8) {
                                Image(systemName: done.contains(rhythm.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(done.contains(rhythm.id) ? Palette.moss : Palette.sage)
                                Text(rhythm.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Turn on “Show and tick rhythms” in Fallow, under Me.")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Palette.paper }
    }
}

// MARK: Controls (Control Center, Lock Screen, Action button)

struct StartExerciseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.fallow.ios.control.exercise") {
            ControlWidgetButton(action: StartExerciseIntent()) {
                Label { Text("Friday exercise") } icon: { Image(systemName: "leaf") }
            }
        }
        .displayName("Friday exercise")
    }
}

struct WriteNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.fallow.ios.control.note") {
            ControlWidgetButton(action: WriteNoteIntent()) {
                Label { Text("Write a note") } icon: { Image(systemName: "square.and.pencil") }
            }
        }
        .displayName("Write a note")
    }
}

private extension WidgetFocus {
    var isIntention: Bool {
        if case .intention = self { return true }
        return false
    }
}
