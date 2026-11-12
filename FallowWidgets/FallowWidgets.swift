import ActivityKit
import SwiftUI
import WidgetKit
import UIKit

@main
struct FallowWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RhythmsWidget()
        ExerciseLiveActivity()
        StartExerciseControl()
        WriteNoteControl()
    }
}

/// The guided exercise on the Lock Screen and in the Dynamic Island: a leaf, a generic label
/// and the time left. Never the exercise's title.
struct ExerciseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExerciseActivityAttributes.self) { context in
            LockScreenExercise(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.paper)
                .activitySystemActionForegroundColor(Palette.moss)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "leaf")
                        .font(.title2)
                        .foregroundStyle(Palette.sage)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(caption(context.attributes, context.state))
                        .font(.system(.headline, design: .serif))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeft(state: context.state)
                        .font(.system(.title3, design: .monospaced))
                }
            } compactLeading: {
                Image(systemName: "leaf")
                    .foregroundStyle(Palette.sage)
            } compactTrailing: {
                TimeLeft(state: context.state)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.state.finished ? "checkmark" : "leaf")
                    .foregroundStyle(Palette.sage)
            }
        }
    }
}

private func caption(_ attributes: ExerciseActivityAttributes, _ state: ExerciseActivityAttributes.ContentState) -> String {
    if state.finished { return attributes.doneLabel }
    if state.endsAt == nil { return attributes.pausedLabel }
    return attributes.label
}

private struct LockScreenExercise: View {
    let attributes: ExerciseActivityAttributes
    let state: ExerciseActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.finished ? "checkmark.circle" : "leaf")
                .font(.title)
                .foregroundStyle(Palette.sage)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fallow")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkMuted)
                Text(caption(attributes, state))
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            if !state.finished {
                TimeLeft(state: state)
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(Palette.moss)
            }
        }
        .padding(16)
    }
}

/// Counts down by itself while running; a still time while paused.
private struct TimeLeft: View {
    let state: ExerciseActivityAttributes.ContentState

    var body: some View {
        if state.finished {
            Image(systemName: "checkmark")
        } else if let endsAt = state.endsAt {
            let now = Date.now
            Text(timerInterval: now...max(now, endsAt), countsDown: true)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        } else {
            Text(Duration.seconds(Int(state.remaining.rounded(.up))), format: .time(pattern: .minuteSecond))
                .monospacedDigit()
        }
    }
}

/// The app's "field notebook" colours (the extension has no asset catalog of its own).
enum Palette {
    static let paper = Color(light: (0xEE, 0xF0, 0xE6), dark: (0x15, 0x19, 0x12))
    static let ink = Color(light: (0x23, 0x30, 0x1F), dark: (0xE3, 0xE8, 0xDA))
    static let inkMuted = ink.opacity(0.65)
    static let moss = Color(light: (0x4F, 0x6B, 0x4A), dark: (0xA9, 0xC4, 0x93))
    static let sage = Color(red: 0x8A / 255, green: 0xA0 / 255, blue: 0x70 / 255)
}

private extension Color {
    init(light: (Int, Int, Int), dark: (Int, Int, Int)) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        })
    }
}
