import Foundation
import Testing
@testable import OrbitEngine

struct DayKeyTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    @Test func dayKeyFormat() {
        #expect(DayKey.day(date(2026, 11, 7), calendar: cal) == 20261107)
        #expect(DayKey.day(date(2026, 1, 1, hour: 0), calendar: cal) == 20260101)
        #expect(DayKey.day(date(2026, 12, 31, hour: 23), calendar: cal) == 20261231)
    }

    @Test func dayKeyRoundTrip() {
        let d = DayKey.date(fromDay: 20260228, calendar: cal)!
        #expect(DayKey.day(d, calendar: cal) == 20260228)
        #expect(DayKey.date(fromDay: 20260230, calendar: cal) == nil)
    }

    @Test func weekStartsMonday() {
        // Sun 8 Nov 2026 belongs to the Monday-started week of 2 Nov (ISO week 45).
        #expect(DayKey.week(date(2026, 11, 8), firstWeekday: 2, calendar: cal) == 202645)
        #expect(DayKey.week(date(2026, 11, 9), firstWeekday: 2, calendar: cal) == 202646)
    }

    @Test func weekStartsSunday() {
        // With Sunday first, Sun 8 Nov starts a new week.
        let sat = DayKey.week(date(2026, 11, 7), firstWeekday: 1, calendar: cal)
        let sun = DayKey.week(date(2026, 11, 8), firstWeekday: 1, calendar: cal)
        #expect(sun == sat + 1)
    }

    @Test func weekUsesWeekBasedYear() {
        // Thu 31 Dec 2026 is in ISO week 53 of 2026; Fri 1 Jan 2027 too.
        #expect(DayKey.week(date(2026, 12, 31), firstWeekday: 2, calendar: cal) == 202653)
        #expect(DayKey.week(date(2027, 1, 1), firstWeekday: 2, calendar: cal) == 202653)
        // Mon 29 Dec 2025 is ISO week 1 of 2026.
        #expect(DayKey.week(date(2025, 12, 29), firstWeekday: 2, calendar: cal) == 202601)
    }
}
