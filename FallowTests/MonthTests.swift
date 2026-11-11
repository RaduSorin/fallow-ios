import Foundation
import Testing
@testable import Fallow

struct MonthIDTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }()

    @Test func formatsAndParsesLikeRagaz() {
        #expect(MonthID(year: 2026, month: 11).description == "2026-11")
        #expect(MonthID(string: "2026-03") == MonthID(year: 2026, month: 3))
        #expect(MonthID(string: "2026-13") == nil)
        #expect(MonthID(string: "nonsense") == nil)
    }

    @Test func stepsOverYearEnds() {
        #expect(MonthID(year: 2026, month: 12).next == MonthID(year: 2027, month: 1))
        #expect(MonthID(year: 2027, month: 1).previous == MonthID(year: 2026, month: 12))
    }

    @Test func findsTheFridaysOfNovember2026() {
        let days = MonthID(year: 2026, month: 11).fridays(calendar: calendar).map { DayKey.string($0, calendar: calendar) }
        #expect(days == ["2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27"])
    }

    @Test func blankPlanHasOneEntryPerFriday() {
        let plan = MonthPlan.blank(MonthID(year: 2027, month: 1), calendar: calendar)
        #expect(plan.fridays.map(\.date) == ["2027-01-01", "2027-01-08", "2027-01-15", "2027-01-22", "2027-01-29"])
        #expect(plan.intention.isEmpty)
    }

    @Test func encodesAsAPlainString() throws {
        let data = try JSONEncoder().encode([MonthID(year: 2026, month: 11)])
        #expect(String(data: data, encoding: .utf8) == #"["2026-11"]"#)
    }
}

struct MonthSummaryTests {
    let month = MonthID(year: 2026, month: 11)

    func plan(target: Int?) -> MonthPlan {
        MonthPlan(
            id: month,
            intention: "Make room for slowness",
            success: "In bed before 11",
            target: target,
            fridays: ["2026-11-06", "2026-11-13", "2026-11-20", "2026-11-27"].map {
                FridayPlan(date: $0, exerciseId: nil, title: "")
            },
            savedAt: .now
        )
    }

    @Test func countsOnlyFridayNotesOnPlannedFridays() {
        let notes = [
            Note(date: "2026-11-06", month: month, kind: .friday),
            Note(date: "2026-11-06", month: month, kind: .friday),
            Note(date: "2026-11-13", month: month, kind: .free),
            Note(date: "2026-11-20", month: month, kind: .friday),
            Note(date: "2026-11-30", month: month, kind: .reflection),
        ]
        let summary = MonthSummary(plan: plan(target: 2), notes: notes)
        #expect(summary.fridays == 4)
        #expect(summary.fridaysDone == 2)
        #expect(summary.reachedTarget)
        #expect(summary.notes == 4)
    }

    @Test func noTargetIsNeverReached() {
        let summary = MonthSummary(plan: plan(target: nil), notes: [])
        #expect(!summary.reachedTarget)
    }
}

struct VaultContentsTests {
    @Test func olderVaultFilesWithoutMonthsStillOpen() throws {
        let json = #"{"version":1,"createdAt":"2026-11-11T12:00:00Z","settings":{"iCloudBackup":true}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contents = try decoder.decode(VaultContents.self, from: Data(json.utf8))
        #expect(contents.months.isEmpty)
        #expect(contents.notes.isEmpty)
        #expect(contents.settings.iCloudBackup)
    }

    @Test func savingAPlanReplacesTheSameMonth() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        var plan = MonthPlan.blank(MonthID(year: 2026, month: 11))
        plan.intention = "First"
        contents.save(plan)
        plan.intention = "Second"
        contents.save(plan)
        contents.save(MonthPlan.blank(MonthID(year: 2026, month: 10)))

        #expect(contents.months.count == 2)
        #expect(contents.months.first?.id == MonthID(year: 2026, month: 10))
        #expect(contents.plan(for: MonthID(year: 2026, month: 11))?.intention == "Second")
    }

    @Test func reflectionIsFoundByMonth() {
        var contents = VaultContents(createdAt: .now, settings: VaultSettings())
        let month = MonthID(year: 2026, month: 11)
        var note = Note(date: "2026-11-30", month: month, kind: .reflection)
        note.answers = ["worked": "Walking", ReflectionQuestion.signKey: "yes"]
        contents.save(note)
        #expect(contents.reflection(for: month)?.answers?["sign"] == "yes")
        #expect(contents.reflection(for: month.next) == nil)
    }
}
