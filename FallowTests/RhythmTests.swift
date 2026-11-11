import Foundation
import Testing
@testable import Fallow

struct RhythmTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }()

    func contents() -> VaultContents {
        VaultContents(createdAt: .now, settings: VaultSettings())
    }

    @Test func addIgnoresBlankTitles() {
        var c = contents()
        c.addRhythm("   ")
        c.addRhythm("  Walk without the phone ")
        #expect(c.rhythms.map(\.title) == ["Walk without the phone"])
    }

    @Test func toggleMarksAndUnmarksADay() {
        var c = contents()
        c.addRhythm("Walk")
        let id = c.rhythms[0].id
        c.toggleRhythm(id, on: "2026-11-11")
        #expect(c.rhythmsDone(on: "2026-11-11") == [id])
        c.toggleRhythm(id, on: "2026-11-11")
        #expect(c.rhythmsDone(on: "2026-11-11").isEmpty)
        #expect(c.rhythmLog["2026-11-11"] == nil)
    }

    @Test func weekShowsTheLastSevenDaysOldestFirst() throws {
        var c = contents()
        c.addRhythm("Walk")
        let id = c.rhythms[0].id
        c.toggleRhythm(id, on: "2026-11-05")
        c.toggleRhythm(id, on: "2026-11-11")
        c.toggleRhythm(id, on: "2026-11-04") // eight days back, outside the week
        let today = try #require(DayKey.date("2026-11-11", calendar: calendar))
        #expect(c.week(for: id, endingOn: today, calendar: calendar) == [true, false, false, false, false, false, true])
    }

    @Test func removingARhythmKeepsOtherRhythms() {
        var c = contents()
        c.addRhythm("Walk")
        c.addRhythm("Read")
        c.removeRhythm(c.rhythms[0].id)
        #expect(c.rhythms.map(\.title) == ["Read"])
    }

    @Test func notesOnADayLeaveOutReflections() {
        var c = contents()
        let month = MonthID(year: 2026, month: 11)
        c.save(Note(date: "2026-11-13", month: month, kind: .friday))
        c.save(Note(date: "2026-11-13", month: month, kind: .reflection))
        c.save(Note(date: "2026-11-12", month: month, kind: .free))
        #expect(c.notes(on: "2026-11-13").map(\.kind) == [.friday])
    }

    @Test func fitKeepsRagazValuesInJSON() throws {
        var note = Note(date: "2026-11-13", month: MonthID(year: 2026, month: 11), kind: .friday)
        note.fit = .partly
        note.before = 7
        note.after = 4
        let json = String(data: try JSONEncoder().encode(note), encoding: .utf8) ?? ""
        #expect(json.contains(#""fit":"partial""#))
        #expect(json.contains(#""kind":"friday""#))
    }

    @Test func deleteNoteRemovesOnlyThatNote() {
        var c = contents()
        let month = MonthID(year: 2026, month: 11)
        let keep = Note(date: "2026-11-13", month: month, kind: .free)
        let drop = Note(date: "2026-11-13", month: month, kind: .free)
        c.save(keep)
        c.save(drop)
        c.deleteNote(drop.id)
        #expect(c.notes.map(\.id) == [keep.id])
    }
}
