import Foundation
import Testing
@testable import Fallow

struct SeasonalIconTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        return c
    }()

    func date(_ month: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
    }

    @Test func offKeepsTheUsualIcon() {
        #expect(SeasonalIcon.iconName(on: false, date: date(11), calendar: calendar) == nil)
    }

    @Test func eachMonthHasItsIcon() {
        #expect(SeasonalIcon.iconName(on: true, date: date(1), calendar: calendar) == "Season01")
        #expect(SeasonalIcon.iconName(on: true, date: date(11), calendar: calendar) == "Season11")
        #expect(SeasonalIcon.iconName(on: true, date: date(12), calendar: calendar) == "Season12")
    }

}
