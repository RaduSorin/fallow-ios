import ActivityKit
import Foundation
import Observation
import UserNotifications

/// The identifier of the bell that rings when a guided exercise's time is up.
/// Kept apart from the reminders' "fallow." prefix, so rescheduling reminders never removes it.
enum ExerciseBell {
    static let identifier = "fallow-exercise-end"
}

/// The guided exercise in progress, if any. Lives for the whole app, outside the vault views,
/// so it survives the vault locking while the phone is locked: after Face ID the exercise
/// screen comes back where it was. It keeps only the exercise's id and the timing, never its text.
@MainActor
@Observable
final class ExerciseRun {
    struct Session: Identifiable, Equatable {
        let id = UUID()
        let exerciseID: String
        /// The planned length; nil for an exercise without a duration (no timer then).
        let minutes: Int?
        var step = 0
        var clock: ExerciseClock?
        var finished = false
        var stepCount = 0
        /// The steps' text, only when the person chose to show them on the Apple Watch.
        var watchStepTexts: [String]?
        /// The feeling rated on the watch, 0 to 10, put in the note's draft at the end.
        var before: Int?
        var after: Int?

        var isTimed: Bool { (minutes ?? 0) > 0 }
    }

    private(set) var session: Session?
    private var activityID: String?
    /// Whether the steps' text may go to the Apple Watch (a setting, off by default).
    var showStepsOnWatch = false
    /// Called after every change, with what the Apple Watch may mirror (nil when no exercise runs).
    @ObservationIgnored var onWatchChange: ((WatchExercise?) -> Void)?

    func start(_ exercise: Exercise) {
        close()
        var next = Session(exerciseID: exercise.id, minutes: exercise.minutes)
        next.stepCount = exercise.stepList.count
        if showStepsOnWatch { next.watchStepTexts = exercise.stepList }
        session = next
        publishToWatch()
    }

    func show(step: Int) {
        session?.step = max(0, step)
        publishToWatch()
    }

    /// A feeling rated on the watch, for the run it was rated on.
    func rate(session id: String, before: Int?, after: Int?) {
        guard session?.id.uuidString == id else { return }
        if let before { session?.before = before }
        if let after { session?.after = after }
        publishToWatch()
    }

    /// What the watch may show now. Pure, so it can be tested.
    func watchState(at now: Date = .now) -> WatchExercise? {
        guard let session else { return nil }
        let clock = session.clock
        let running = clock != nil && clock?.isPaused == false && !session.finished
        let texts = session.watchStepTexts ?? []
        return WatchExercise(
            session: session.id.uuidString,
            endsAt: running ? clock?.endsAt : nil,
            remaining: session.finished ? 0 : clock?.remaining(at: now) ?? Double((session.minutes ?? 0) * 60),
            duration: Double((session.minutes ?? 0) * 60),
            started: clock != nil,
            finished: session.finished,
            step: session.step,
            stepCount: session.stepCount,
            stepText: texts.indices.contains(session.step) ? texts[session.step] : nil,
            before: session.before,
            after: session.after
        )
    }

    private func publishToWatch() {
        onWatchChange?(watchState())
    }

    func startClock(now: Date = .now) {
        guard var current = session, current.clock == nil, !current.finished,
              let minutes = current.minutes, minutes > 0 else { return }
        let clock = ExerciseClock(duration: TimeInterval(minutes * 60), start: now)
        current.clock = clock
        session = current
        scheduleBell(after: clock.remaining(at: now))
        startActivity(clock.activityState(finished: false, at: now))
        publishToWatch()
    }

    func pause(now: Date = .now) {
        guard var clock = session?.clock, !clock.isPaused, session?.finished == false else { return }
        clock.pause(at: now)
        session?.clock = clock
        cancelBell()
        pushActivity(clock.activityState(finished: false, at: now))
        publishToWatch()
    }

    func resume(now: Date = .now) {
        guard var clock = session?.clock, clock.isPaused, session?.finished == false else { return }
        clock.resume(at: now)
        session?.clock = clock
        scheduleBell(after: clock.remaining(at: now))
        pushActivity(clock.activityState(finished: false, at: now))
        publishToWatch()
    }

    /// The time ran out (or the person finished early). The bell has rung or is ringing now.
    func finish(early: Bool = false, now: Date = .now) {
        guard let current = session, !current.finished else { return }
        session?.finished = true
        if early { cancelBell() }
        let state = current.clock?.activityState(finished: true, at: now)
            ?? .init(endsAt: nil, remaining: 0, finished: true)
        endActivity(state, immediately: false)
        publishToWatch()
    }

    /// Leaves the exercise: stops the bell and takes the Live Activity away.
    func close() {
        guard session != nil else { return }
        cancelBell()
        endActivity(.init(endsAt: nil, remaining: 0, finished: true), immediately: true)
        session = nil
        publishToWatch()
    }

    // MARK: The bell (a local notification, so it rings with the phone locked)

    private func scheduleBell(after seconds: TimeInterval) {
        guard seconds >= 1 else { return }
        let title = String(localized: "Time is up")
        let body = String(localized: "Take a breath, then write how it went.")
        Task {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = "fallow"
            content.userInfo = [AppRoute.key: AppRoute.exercise.rawValue]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            let request = UNNotificationRequest(identifier: ExerciseBell.identifier, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancelBell() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ExerciseBell.identifier])
    }

    // MARK: Live Activity

    private func startActivity(_ state: ExerciseActivityAttributes.ContentState) {
        endActivity(state, immediately: true)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ExerciseActivityAttributes(
            label: String(localized: "Exercise"),
            pausedLabel: String(localized: "Paused"),
            doneLabel: String(localized: "Time is up")
        )
        activityID = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        ).id
    }

    private func pushActivity(_ state: ExerciseActivityAttributes.ContentState) {
        guard let id = activityID else { return }
        Task.detached {
            guard let activity = Activity<ExerciseActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endActivity(_ state: ExerciseActivityAttributes.ContentState, immediately: Bool) {
        guard let id = activityID else { return }
        activityID = nil
        Task.detached {
            guard let activity = Activity<ExerciseActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(.now.addingTimeInterval(5 * 60))
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy)
        }
    }

    /// Ends Live Activities left over from a run the system closed (the app was quit meanwhile).
    nonisolated static func endLeftovers() {
        Task.detached {
            for activity in Activity<ExerciseActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
