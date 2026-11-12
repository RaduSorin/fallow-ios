import Foundation
import Testing
@testable import Fallow

struct ReminderPlanTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return calendar
    }()

    func date(_ text: String) -> Date {
        let parts = text.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
    }

    func contents(planned: Bool) -> VaultContents {
        var c = VaultContents(createdAt: .now, settings: VaultSettings())
        if planned {
            var plan = MonthPlan.blank(MonthID(year: 2026, month: 11), calendar: calendar)
            plan.intention = "Slowness"
            c.save(plan)
        }
        return c
    }

    @Test func defaultsGiveDailyWeeklyAndMonthlyReminders() {
        let ids = ReminderPlan.reminders(for: contents(planned: false), now: date("2026-11-11 21:00"), calendar: calendar).map(\.id)
        #expect(ids.contains("morning"))
        #expect(ids.contains("evening"))
        #expect(ids.contains("worry"))
        #expect(ids.contains("reflection-2026-12"))
        #expect(!ids.contains { $0.hasPrefix("friday-") })
    }

    @Test func onlyFridaysStillAheadAreScheduled() {
        let reminders = ReminderPlan.reminders(for: contents(planned: true), now: date("2026-11-13 21:00"), calendar: calendar)
        let fridays = reminders.filter { $0.id.hasPrefix("friday-") }.map(\.id)
        #expect(fridays == ["friday-2026-11-20", "friday-2026-11-27"])
    }

    @Test func todaysFridayCountsUntilEightInTheEvening() {
        let reminders = ReminderPlan.reminders(for: contents(planned: true), now: date("2026-11-13 19:00"), calendar: calendar)
        let first = reminders.first { $0.id.hasPrefix("friday-") }
        #expect(first?.id == "friday-2026-11-13")
        #expect(first?.components.hour == 20)
        #expect(first?.repeats == false)
    }

    @Test func worryListIsMondayAtEightThirty() {
        let worry = ReminderPlan.reminders(for: contents(planned: false), now: .now, calendar: calendar).first { $0.kind == .worry }
        #expect(worry?.components.weekday == 2)
        #expect(worry?.components.hour == 8)
        #expect(worry?.components.minute == 30)
        #expect(worry?.repeats == true)
    }

    @Test func switchedOffRemindersAreLeftOut() {
        var c = contents(planned: true)
        c.settings.morningReminder = nil
        c.settings.eveningReminder = nil
        c.settings.fridayReminder = false
        c.settings.worryReminder = false
        c.settings.reflectionReminder = false
        #expect(ReminderPlan.reminders(for: c, now: date("2026-11-02 07:00"), calendar: calendar).isEmpty)
    }

    @Test func firstMondayOfDecember2026IsTheSeventh() throws {
        let monday = try #require(ReminderPlan.firstMonday(of: MonthID(year: 2026, month: 12), calendar: calendar))
        #expect(DayKey.string(monday, calendar: calendar) == "2026-12-07")
    }

    @Test func olderSettingsTurnNewRemindersOn() throws {
        let json = #"{"morningReminder":510,"iCloudBackup":false}"#
        let settings = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))
        #expect(settings.morningReminder == 510)
        #expect(settings.eveningReminder == nil)
        #expect(settings.iCloudBackup == false)
        #expect(settings.fridayReminder && settings.worryReminder && settings.reflectionReminder)
    }
}

struct WorryListTests {
    @Test func splitsLinesAndDropsBulletsAndDuplicates() {
        let items = WorryList.items(from: "- The deadline\n• Dentist\n\n1. The deadline\n  Weather  ")
        #expect(items == ["The deadline", "Dentist", "Weather"])
    }

    @Test func keepsRagazFieldNames() throws {
        let list = WorryList(stone: ["Weather"], clay: ["Deadline"], breakdown: ["Email Ana"], step: "Email Ana",
                             parent: .init(what: "A lot", hardest: nil, need: "Rest"))
        let json = String(data: try JSONEncoder().encode(list), encoding: .utf8) ?? ""
        for key in ["\"stone\"", "\"clay\"", "\"breakdown\"", "\"step\"", "\"parent\"", "\"need\""] {
            #expect(json.contains(key))
        }
    }
}
