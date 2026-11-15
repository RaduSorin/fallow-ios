import SwiftUI
import WatchKit

/// The exercise running on the iPhone, on the wrist: the feeling before, the time and the step,
/// the end, and the feeling after. The iPhone keeps the exercise; the watch only mirrors it.
struct WatchExerciseView: View {
    @Environment(WatchModel.self) private var model
    @State private var skippedBefore = false

    var body: some View {
        Group {
            if let exercise = model.exercise {
                if exercise.finished {
                    ExerciseEnd(exercise: exercise)
                } else if exercise.before == nil && !skippedBefore && !exercise.started {
                    FeelingScale(prompt: "How strong is the feeling now?") { value in
                        model.rate(before: value)
                    } skip: {
                        skippedBefore = true
                    }
                } else {
                    ExerciseClockView(exercise: exercise)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "leaf").foregroundStyle(WatchPalette.moss)
                    Text("The exercise has ended on your iPhone.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WatchPalette.inkMuted)
                }
            }
        }
        .navigationTitle(Text("Exercise"))
    }
}

private struct ExerciseClockView: View {
    let exercise: WatchExercise

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if exercise.stepCount > 0 {
                    Text("Step \(exercise.step + 1) of \(exercise.stepCount)")
                        .font(.system(.caption2, design: .monospaced).weight(.medium))
                        .textCase(.uppercase)
                        .foregroundStyle(WatchPalette.inkMuted)
                }
                if exercise.duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ClockRing(exercise: exercise, now: context.date)
                    }
                }
                if let text = exercise.stepText {
                    Text(text)
                        .font(.system(.body, design: .serif))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if exercise.duration <= 0 {
                    Text("Follow the steps on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(WatchPalette.inkMuted)
                }
            }
        }
    }
}

private struct ClockRing: View {
    let exercise: WatchExercise
    let now: Date

    var body: some View {
        let left = exercise.remaining(at: now)
        let progress = exercise.duration > 0 ? 1 - left / exercise.duration : 1
        ZStack {
            Circle().stroke(WatchPalette.cardBorder, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(WatchPalette.moss, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(Duration.seconds(Int(left.rounded(.up))).formatted(.time(pattern: .minuteSecond)))
                    .font(.title2.monospacedDigit())
                if exercise.isPaused {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.inkMuted)
                } else if !exercise.started {
                    Text("Start it on your iPhone")
                        .font(.caption2)
                        .foregroundStyle(WatchPalette.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(width: 120, height: 120)
    }
}

private struct ExerciseEnd: View {
    @Environment(WatchModel.self) private var model
    let exercise: WatchExercise
    @State private var skippedAfter = false

    var body: some View {
        if exercise.after == nil && !skippedAfter {
            FeelingScale(prompt: "Time is up. How strong is the feeling now?") { value in
                model.rate(after: value)
            } skip: {
                skippedAfter = true
            }
            // The bell on the wrist, also when the iPhone is silent.
            .onAppear { WKInterfaceDevice.current().play(.notification) }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "bell")
                    .font(.title2)
                    .foregroundStyle(WatchPalette.moss)
                Text("Done")
                    .font(.system(.title3, design: .serif))
                Text("Write how it went on your iPhone when you are ready.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WatchPalette.inkMuted)
            }
        }
    }
}

/// 0 to 10 with the Digital Crown, the same scale as on the iPhone (0 is calm).
private struct FeelingScale: View {
    let prompt: LocalizedStringResource
    let save: (Int) -> Void
    let skip: () -> Void
    @State private var value = 5.0

    var body: some View {
        VStack(spacing: 6) {
            Text(prompt)
                .font(.system(.footnote, design: .serif))
                .multilineTextAlignment(.center)
            Text(verbatim: "\(Int(value))")
                .font(.system(size: 44, weight: .medium).monospacedDigit())
                .foregroundStyle(WatchPalette.moss)
                .focusable()
                .digitalCrownRotation($value, from: 0, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel(Text("Feeling, 0 to 10"))
                .accessibilityValue(Text(verbatim: "\(Int(value))"))
            Text("0 is calm, 10 is as strong as it gets.")
                .font(.caption2)
                .foregroundStyle(WatchPalette.inkMuted)
                .multilineTextAlignment(.center)
            HStack {
                Button("Skip", action: skip)
                Button("Save") { save(Int(value)) }
                    .tint(WatchPalette.mossDeep)
                    .handGestureShortcut(.primaryAction)
            }
        }
    }
}
