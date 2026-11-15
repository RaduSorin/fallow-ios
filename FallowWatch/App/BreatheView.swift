import SwiftUI
import WatchKit

/// Breathing with the wrist: 4 seconds in, 6 out, a tap at each turn. No streaks.
struct BreatheView: View {
    @State private var minutes: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("How long?")
                    .font(.system(.headline, design: .serif))
                ForEach([1, 3, 5], id: \.self) { length in
                    LengthButton(length: length) { minutes = length }
                }
                BreathingTotals()
            }
        }
        .navigationTitle(Text("Breathe"))
        .fullScreenCover(item: Binding(
            get: { minutes.map(BreathingLength.init) },
            set: { minutes = $0?.minutes }
        )) { length in
            BreatheSessionView(minutes: length.minutes)
        }
    }
}

/// Double tap starts the middle length, three minutes.
private struct LengthButton: View {
    let length: Int
    let pick: () -> Void

    var body: some View {
        let button = Button(action: pick) {
            Text("\(length) min").frame(maxWidth: .infinity)
        }
        if length == 3 {
            button.handGestureShortcut(.primaryAction)
        } else {
            button
        }
    }
}

private struct BreathingLength: Identifiable {
    let minutes: Int
    var id: Int { minutes }
}

private struct BreathingTotals: View {
    var body: some View {
        let today = WatchStats.breathingMinutes()
        let week = WatchStats.breathingMinutesThisWeek()
        if week > 0 {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today")
                    Spacer()
                    Text("\(today) min").foregroundStyle(WatchPalette.moss)
                }
                HStack {
                    Text("This week")
                    Spacer()
                    Text("\(week) min").foregroundStyle(WatchPalette.moss)
                }
            }
            .font(.footnote)
            .padding(.top, 6)
        }
    }
}

/// The breathing itself. A mindfulness session keeps it going (and tapping) with the wrist down.
struct BreatheSessionView: View {
    static let inhale: TimeInterval = 4
    static let exhale: TimeInterval = 6

    let minutes: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(WatchModel.self) private var model
    @State private var start = Date.now
    @State private var finishedSeconds: Double?
    @State private var runtime = BreathingRuntime()

    var body: some View {
        Group {
            if let seconds = finishedSeconds {
                BreatheDone(minutes: Int(seconds / 60), savedToHealth: model.snapshot?.healthMindful == true) {
                    dismiss()
                }
            } else {
                TimelineView(.animation) { context in
                    BreathingCircle(elapsed: context.date.timeIntervalSince(start), total: Double(minutes * 60))
                }
                .task { await run() }
            }
        }
    }

    private func run() async {
        start = .now
        runtime.start()
        let total = Double(minutes * 60)
        let device = WKInterfaceDevice.current()
        while Date.now.timeIntervalSince(start) < total, !Task.isCancelled {
            device.play(.directionUp)
            try? await Task.sleep(for: .seconds(Self.inhale))
            guard !Task.isCancelled else { break }
            device.play(.directionDown)
            try? await Task.sleep(for: .seconds(Self.exhale))
        }
        runtime.stop()
        let seconds = min(Date.now.timeIntervalSince(start), total)
        finish(seconds: seconds, end: .now)
        if !Task.isCancelled { device.play(.success) }
    }

    /// Counts the minutes (a minute or more) and, if allowed, sends the interval for Health.
    private func finish(seconds: Double, end: Date) {
        guard seconds >= 60 else {
            finishedSeconds = Task.isCancelled ? nil : seconds
            return
        }
        WatchStats.addBreathing(seconds)
        if model.snapshot?.healthMindful == true {
            PhoneLink.shared.sendMindful(DateInterval(start: end.addingTimeInterval(-seconds), end: end))
        }
        finishedSeconds = seconds
    }
}

private struct BreathingCircle: View {
    let elapsed: TimeInterval
    let total: TimeInterval

    var body: some View {
        let cycle = BreatheSessionView.inhale + BreatheSessionView.exhale
        let phase = elapsed.truncatingRemainder(dividingBy: cycle)
        let inhaling = phase < BreatheSessionView.inhale
        let scale = inhaling
            ? 0.55 + 0.45 * (phase / BreatheSessionView.inhale)
            : 1 - 0.45 * ((phase - BreatheSessionView.inhale) / BreatheSessionView.exhale)
        let left = max(0, Int(total - elapsed))
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(WatchPalette.moss.opacity(0.12))
                Circle().fill(WatchPalette.moss.opacity(0.22)).padding(12)
                Circle().fill(WatchPalette.mossDeep).padding(26)
                if inhaling {
                    Text("Breathe in").font(.system(.headline, design: .serif))
                } else {
                    Text("Breathe out").font(.system(.headline, design: .serif))
                }
            }
            .scaleEffect(scale)
            .frame(width: 130, height: 130)
            Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WatchPalette.inkMuted)
        }
    }
}

private struct BreatheDone: View {
    let minutes: Int
    let savedToHealth: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "leaf")
                .font(.title2)
                .foregroundStyle(WatchPalette.moss)
            if minutes > 0 {
                Text("\(minutes) min")
                    .font(.system(.title2, design: .serif))
            } else {
                Text("Well done")
                    .font(.system(.title3, design: .serif))
            }
            if savedToHealth && minutes > 0 {
                Text("Saved to Health as mindful minutes.")
                    .font(.footnote)
                    .foregroundStyle(WatchPalette.inkMuted)
                    .multilineTextAlignment(.center)
            }
            Button("Done", action: close)
                .handGestureShortcut(.primaryAction)
        }
    }
}

/// Keeps the app running with the wrist down while breathing (watchOS mindfulness session).
@MainActor
final class BreathingRuntime: NSObject, @preconcurrency WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?

    func start() {
        guard session == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        self.session = session
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {}
}
