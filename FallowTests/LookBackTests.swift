import Foundation
import Testing
@testable import Fallow

struct LookBackTests {
    let month = MonthID(year: 2026, month: 11)

    func friday(_ day: String, _ before: Int?, _ after: Int?, fit: NoteFit? = nil) -> Note {
        Note(date: day, month: month, kind: .friday, before: before, after: after, fit: fit)
    }

    @Test func onlyRatedFridayNotesOldestFirst() {
        let notes = [
            friday("2026-11-20", 7, 3, fit: .yes),
            friday("2026-11-13", 6, 6, fit: .partly),
            friday("2026-11-27", nil, nil, fit: .yes),
            Note(date: "2026-11-14", month: month, kind: .free, before: 9, after: 1),
        ]
        let points = LookBack.feelings(notes)
        #expect(points.map(\.day) == ["2026-11-13", "2026-11-20"])
        #expect(points.map(\.change) == [0, 4])
        #expect(LookBack.averageChange(points) == 2)
        #expect(LookBack.averageChange([]) == nil)
        #expect(LookBack.fits(notes) == [.yes: 2, .partly: 1])
    }

    @Test func searchIgnoresCaseAndDiacritics() {
        var note = Note(date: "2026-11-13", month: month, kind: .free, text: "Un gând despre ȘCOALĂ")
        #expect(note.matches("gand"))
        #expect(note.matches("scoala gând"))
        #expect(note.matches("  "))
        #expect(!note.matches("munte"))
        note.answers = ["worked": "Plimbările de dimineață"]
        #expect(note.matches("plimbarile"))
        note.worry = WorryList(stone: ["vremea"], clay: ["telefonul mamei"], step: "sun mâine")
        #expect(note.matches("mamei"))
        #expect(note.matches("vremea"))
        #expect(note.matches("sun maine"))
    }

    @Test func mindfulMinutesLeaveOutPausesAndShortTries() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var clock = ExerciseClock(duration: 600, start: start)
        // Under a minute: nothing goes to Health.
        #expect(MindfulHealth.interval(for: clock, finishedAt: start.addingTimeInterval(30)) == nil)

        // Ran to the end; seen later (after Face ID): ends when the time ran out.
        let whole = MindfulHealth.interval(for: clock, finishedAt: start.addingTimeInterval(900))
        #expect(whole == DateInterval(start: start, end: start.addingTimeInterval(600)))

        // Two minutes, a pause, then finished early while paused.
        clock.pause(at: start.addingTimeInterval(120))
        let paused = MindfulHealth.interval(for: clock, finishedAt: start.addingTimeInterval(500))
        #expect(paused?.duration == 120)
        #expect(paused?.end == start.addingTimeInterval(500))
    }
}
