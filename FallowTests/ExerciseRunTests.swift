import Foundation
import Testing
@testable import Fallow

struct ExerciseClockTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func countsDownFromTheStart() {
        let clock = ExerciseClock(duration: 600, start: start)
        #expect(clock.remaining(at: start) == 600)
        #expect(clock.remaining(at: start.addingTimeInterval(150)) == 450)
        #expect(clock.progress(at: start.addingTimeInterval(150)) == 0.25)
        #expect(!clock.isOver(at: start.addingTimeInterval(599)))
        #expect(clock.isOver(at: start.addingTimeInterval(600)))
        #expect(clock.remaining(at: start.addingTimeInterval(900)) == 0)
    }

    @Test func pauseKeepsTheTimeLeft() {
        var clock = ExerciseClock(duration: 600, start: start)
        clock.pause(at: start.addingTimeInterval(100))
        #expect(clock.isPaused)
        // Time passing while paused changes nothing.
        #expect(clock.remaining(at: start.addingTimeInterval(1000)) == 500)
        clock.resume(at: start.addingTimeInterval(1000))
        #expect(!clock.isPaused)
        #expect(clock.remaining(at: start.addingTimeInterval(1100)) == 400)
        #expect(clock.isOver(at: start.addingTimeInterval(1500)))
    }

    @Test func pausingTwiceOrResumingWhileRunningDoesNothing() {
        var clock = ExerciseClock(duration: 300, start: start)
        clock.resume(at: start.addingTimeInterval(50))
        #expect(clock.remaining(at: start.addingTimeInterval(100)) == 200)
        clock.pause(at: start.addingTimeInterval(100))
        clock.pause(at: start.addingTimeInterval(200))
        #expect(clock.remaining(at: start.addingTimeInterval(200)) == 200)
    }

    @Test func liveActivityNeverCountsWhilePausedOrDone() {
        var clock = ExerciseClock(duration: 300, start: start)
        let running = clock.activityState(finished: false, at: start)
        #expect(running.endsAt == start.addingTimeInterval(300))
        #expect(!running.finished)

        clock.pause(at: start.addingTimeInterval(60))
        let paused = clock.activityState(finished: false, at: start.addingTimeInterval(60))
        #expect(paused.endsAt == nil)
        #expect(paused.remaining == 240)

        let done = clock.activityState(finished: true, at: start.addingTimeInterval(400))
        #expect(done.endsAt == nil)
        #expect(done.remaining == 0)
        #expect(done.finished)
    }

    @Test func stepsAreTheParagraphs() {
        let exercise = Exercise(title: "Breathing", steps: "Sit down.\n\n  Breathe in for four.  \n\n\n\nBreathe out for six.\n")
        #expect(exercise.stepList == ["Sit down.", "Breathe in for four.", "Breathe out for six."])
        #expect(Exercise(title: "Empty").stepList.isEmpty)
    }
}

@MainActor
struct ExerciseRunTests {
    @Test func anExerciseWithoutALengthHasNoTimer() {
        let run = ExerciseRun()
        run.start(Exercise(title: "Free", minutes: nil, steps: "One"))
        #expect(run.session?.isTimed == false)
        run.startClock()
        #expect(run.session?.clock == nil)
        run.finish(early: true)
        #expect(run.session?.finished == true)
        run.close()
        #expect(run.session == nil)
    }

    @Test func stepsAndClockMoveTogether() {
        let run = ExerciseRun()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        run.start(Exercise(title: "Timed", minutes: 5, steps: "One\n\nTwo"))
        run.show(step: 1)
        #expect(run.session?.step == 1)
        run.show(step: -3)
        #expect(run.session?.step == 0)

        run.startClock(now: now)
        #expect(run.session?.clock?.remaining(at: now) == 300)
        run.pause(now: now.addingTimeInterval(60))
        #expect(run.session?.clock?.isPaused == true)
        run.resume(now: now.addingTimeInterval(120))
        #expect(run.session?.clock?.remaining(at: now.addingTimeInterval(120)) == 240)
        run.close()
    }

    @Test func startingAnotherExerciseReplacesTheFirst() {
        let run = ExerciseRun()
        run.start(Exercise(id: "a", title: "A", steps: "x"))
        let first = run.session?.id
        run.start(Exercise(id: "b", title: "B", steps: "y"))
        #expect(run.session?.exerciseID == "b")
        #expect(run.session?.id != first)
        run.close()
    }
}

struct AppRouteTests {
    @Test func everyReminderOpensTheRightScreen() {
        #expect(AppRoute(reminder: .morning) == .today)
        #expect(AppRoute(reminder: .evening) == .today)
        #expect(AppRoute(reminder: .friday) == .friday)
        #expect(AppRoute(reminder: .worry) == .worry)
        #expect(AppRoute(reminder: .reflection) == .reflection)
        #expect(AppRoute.reflection.tab == .month)
        #expect(AppRoute.worry.tab == .today)
    }

    @Test func readsTheRouteFromANotification() {
        #expect(AppRoute(userInfo: [AppRoute.key: "worry"]) == .worry)
        #expect(AppRoute(userInfo: [AppRoute.key: "nonsense"]) == nil)
        #expect(AppRoute(userInfo: [:]) == nil)
    }

    @Test func theBellIsNotARemindersID() {
        // Rescheduling reminders removes everything with this prefix; the bell must survive it.
        #expect(!ExerciseBell.identifier.hasPrefix(ReminderScheduler.prefix))
    }
}
