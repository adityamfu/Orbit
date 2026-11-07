import Foundation

/// Integer keys for days and weeks, so data can be grouped and queried without time zones leaking in.
public enum DayKey {
    /// `yyyyMMdd`, e.g. 20261107.
    public static func day(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10_000 + c.month! * 100 + c.day!
    }

    /// Start of the day a `yyyyMMdd` key points to, or nil for an impossible date.
    public static func date(fromDay key: Int, calendar: Calendar = .current) -> Date? {
        let comps = DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100)
        guard comps.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: comps)
    }

    /// `yyyyWW` using ISO-style week numbering (min. 4 days in week 1) with a configurable first weekday
    /// (1 = Sunday … 7 = Saturday, as in `Calendar`). The year is the week-based year, so 31 Dec can be week 1.
    public static func week(_ date: Date, firstWeekday: Int, calendar: Calendar = .current) -> Int {
        var cal = calendar
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 4
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return c.yearForWeekOfYear! * 100 + c.weekOfYear!
    }
}
