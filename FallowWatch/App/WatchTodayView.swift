import SwiftUI

/// Today on the wrist: what the day holds and the rhythms to tick.
struct WatchTodayView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let snapshot = model.snapshot {
                        // The day changes at midnight even while the app stays open.
                        TimelineView(.everyMinute) { context in
                            TodayContent(snapshot: snapshot, now: context.date)
                        }
                    } else {
                        Text("Open Fallow on your iPhone once to fill this.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text(verbatim: "Fallow"))
        }
    }
}

private struct TodayContent: View {
    @Environment(WatchModel.self) private var model
    let snapshot: WidgetSnapshot
    let now: Date

    private var day: String { DayKey.string(now) }

    var body: some View {
        let focus = snapshot.focus(on: now)
        VStack(alignment: .leading, spacing: 10) {
            Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(WatchPalette.inkMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(focus.label)
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(WatchPalette.moss)
                Text(focus.title)
                    .font(.system(.headline, design: .serif))
                    .italic(focus.isIntention)
                    .foregroundStyle(WatchPalette.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchPalette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WatchPalette.cardBorder))

            HStack(spacing: 8) {
                NavigationLink {
                    WatchNoteView()
                } label: {
                    Label("Note", systemImage: "mic")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Quick note"))
                NavigationLink {
                    BreatheView()
                } label: {
                    Label("Breathe", systemImage: "wind")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Breathe"))
            }
            .tint(WatchPalette.mossDeep)

            rhythms
        }
    }

    @ViewBuilder
    private var rhythms: some View {
        let list = snapshot.watchRhythms
        if snapshot.rhythmCount > 0 {
            HStack(alignment: .firstTextBaseline) {
                Text("Rhythms")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(WatchPalette.inkMuted)
                Spacer()
                Text("\(snapshot.done(on: day).count) of \(snapshot.rhythmCount)")
                    .font(.caption2)
                    .foregroundStyle(WatchPalette.moss)
            }
            ForEach(list) { rhythm in
                let done = model.isDone(rhythm, on: day)
                Button {
                    model.toggle(rhythm, on: day)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? WatchPalette.moss : WatchPalette.inkMuted)
                        if let title = rhythm.title {
                            Text(title).lineLimit(2)
                        } else {
                            Text("Rhythm \(rhythm.number)")
                        }
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityValue(done ? Text("Done") : Text("Not done"))
            }
            if let problem = model.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.inkMuted)
            } else if !model.canWrite {
                Text("Open Fallow on your iPhone once, then you can tick here.")
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.inkMuted)
            }
        }
    }
}
