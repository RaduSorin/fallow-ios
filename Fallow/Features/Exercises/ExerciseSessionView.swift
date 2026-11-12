import SwiftUI
import UIKit

/// A guided exercise: one step at a time, a gentle countdown when the exercise has a length,
/// the screen kept awake, and a bell at the end (it rings with the phone locked too).
/// At the end it opens the note: how strong the feeling was before and after.
struct ExerciseSessionView: View {
    @Environment(Vault.self) private var vault
    @Environment(ExerciseRun.self) private var run
    @State private var writing: Note?
    @State private var confirmStop = false

    private var session: ExerciseRun.Session? { run.session }
    private var exercise: Exercise? { vault.contents?.exercise(session?.exerciseID) }
    private var steps: [String] { exercise?.stepList ?? [] }
    private var isRunning: Bool {
        guard let clock = session?.clock, session?.finished == false else { return false }
        return !clock.isPaused
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if exercise == nil {
                missing
            } else if session?.finished == true {
                finished
            } else {
                pager
                controls
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .task(id: session?.clock) { await waitForTheEnd() }
        .sensoryFeedback(.selection, trigger: session?.step)
        .sensoryFeedback(.success, trigger: session?.finished == true) { _, isDone in isDone }
        .onChange(of: session?.finished == true) { _, isDone in
            guard isDone, vault.contents?.settings.healthMindful == true,
                  let clock = session?.clock,
                  let interval = MindfulHealth.interval(for: clock, finishedAt: .now) else { return }
            Task { await MindfulHealth.save(interval) }
        }
        .sheet(item: $writing, onDismiss: { run.close() }) { note in
            NoteEditor(note: note, isNew: true)
        }
        .confirmationDialog(Text("Stop the exercise?"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(role: .destructive) { run.close() } label: { Text("Stop") }
            Button(role: .cancel) { } label: { Text("Keep going") }
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SpecimenLabel(text: "Exercise")
                if let exercise {
                    Text(exercise.title)
                        .font(.notebookTitle(.title2))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                if isRunning { confirmStop = true } else { run.close() }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.cardBorder))
            }
            .foregroundStyle(Theme.inkMuted)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var pager: some View {
        TabView(selection: Binding(get: { session?.step ?? 0 }, set: { run.show(step: $0) })) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step \(index + 1) of \(steps.count)").specimen()
                        Text(text)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var controls: some View {
        VStack(spacing: 16) {
            if session?.isTimed == true {
                timer
            }
            stepButtons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var timer: some View {
        HStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let clock = session?.clock
                let left = clock?.remaining(at: context.date) ?? TimeInterval((session?.minutes ?? 0) * 60)
                ZStack {
                    Circle().stroke(Theme.cardBorder, lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: 1 - (clock?.progress(at: context.date) ?? 0))
                        .stroke(Theme.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    Text(Duration.seconds(Int(left.rounded(.up))), format: .time(pattern: .minuteSecond))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Time left"))
                .accessibilityValue(Text(Duration.seconds(Int(left.rounded(.up))), format: .units(allowed: [.minutes, .seconds], width: .wide)))
            }

            VStack(alignment: .leading, spacing: 8) {
                if let clock = session?.clock {
                    if clock.isPaused {
                        Button { run.resume() } label: {
                            Label { Text("Resume") } icon: { Image(systemName: "play.fill") }
                        }
                        .buttonStyle(.borderedProminent)
                        Text("Paused").specimen()
                    } else {
                        Button { run.pause() } label: {
                            Label { Text("Pause") } icon: { Image(systemName: "pause.fill") }
                        }
                        .buttonStyle(.bordered)
                        Text("A bell rings at the end, even with the phone locked.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkMuted)
                    }
                } else {
                    Button { run.startClock() } label: {
                        Label { Text("Start the timer") } icon: { Image(systemName: "timer") }
                    }
                    .buttonStyle(.borderedProminent)
                    Text("Or read the steps first, at your own pace.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.cardBorder))
    }

    private var stepButtons: some View {
        let step = session?.step ?? 0
        let isLast = step >= steps.count - 1
        return HStack {
            Button {
                withAnimation { run.show(step: step - 1) }
            } label: {
                Label { Text("Back") } icon: { Image(systemName: "chevron.left") }
            }
            .disabled(step == 0)
            Spacer()
            if isLast {
                Button {
                    run.finish(early: true)
                } label: {
                    Text("I'm done")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    withAnimation { run.show(step: step + 1) }
                } label: {
                    Label { Text("Next") } icon: { Image(systemName: "chevron.right") }
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "leaf")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.sage)
            Text("The exercise is done.")
                .font(.notebookTitle(.title))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Take a breath. How strong is the feeling now?")
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
            Button {
                writeNote()
            } label: {
                Text("Write how it went").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            Button {
                run.close()
            } label: {
                Text("Close")
            }
            .foregroundStyle(Theme.inkMuted)
            Spacer()
        }
        .padding(24)
    }

    private var missing: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("This exercise is no longer in your bank.")
                .foregroundStyle(Theme.inkMuted)
            Button { run.close() } label: { Text("Close") }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: Actions

    /// Sleeps until the time runs out, then marks the exercise done. Started again whenever
    /// the clock changes (start, pause, resume) and when the screen comes back after Face ID.
    private func waitForTheEnd() async {
        guard let clock = session?.clock, !clock.isPaused, session?.finished == false else { return }
        let left = clock.remaining(at: .now)
        if left > 0 {
            try? await Task.sleep(for: .seconds(left))
        }
        guard !Task.isCancelled else { return }
        run.finish()
    }

    private func writeNote() {
        guard let exercise else { return }
        let today = Date.now
        writing = Note(
            date: DayKey.string(today),
            month: MonthID(today),
            kind: .friday,
            exerciseId: exercise.id,
            title: exercise.title
        )
    }
}

/// "Next ›": the icon after the text.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
