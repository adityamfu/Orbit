import Foundation

/// Plain description of a habit, enough for every rule below.
public struct HabitRule: Sendable, Equatable {
    public enum Schedule: Sendable, Equatable {
        case daily
        /// `Calendar` weekdays: 1 = Sunday … 7 = Saturday.
        case weekdays(Set<Int>)
        /// Not tied to a day; tracked per week.
        case timesPerWeek(Int)
        /// Every N days counted from the start day.
        case everyNDays(Int)
    }

    public var schedule: Schedule
    /// Value needed for a day to count as done (1 for check habits).
    public var target: Int
    /// `yyyyMMdd` of the first day the habit exists.
    public var startDay: Int

    public init(schedule: Schedule, target: Int = 1, startDay: Int) {
        self.schedule = schedule
        self.target = max(target, 1)
        self.startDay = startDay
    }

    public var isWeekly: Bool {
        if case .timesPerWeek = schedule { true } else { false }
    }

    public var timesPerWeek: Int? {
        if case .timesPerWeek(let n) = schedule { n } else { nil }
    }
}

/// One day's log.
public struct HabitDay: Sendable, Equatable {
    public var value: Int
    public var isSkipped: Bool

    public init(value: Int, isSkipped: Bool = false) {
        self.value = value
        self.isSkipped = isSkipped
    }
}

public struct HabitStreak: Sendable, Equatable {
    public var current: Int
    public var best: Int
    /// true for "X times per week" habits: the numbers count weeks, not days.
    public var inWeeks: Bool

    public init(current: Int, best: Int, inWeeks: Bool) {
        self.current = current
        self.best = best
        self.inWeeks = inWeeks
    }
}

/// Habit rules from PRD §4.3. Days are `yyyyMMdd` keys.
/// - A skipped day counts as done (max one skip per week, see `canSkip`).
/// - Unscheduled days never break a streak.
/// - Today (or the current week) not being done yet never breaks a streak.
public struct HabitCalculator: Sendable {
    public let calendar: Calendar
    /// `Calendar` weekday the week starts on (2 = Monday).
    public let firstWeekday: Int

    public init(calendar: Calendar = .current, firstWeekday: Int) {
        var cal = calendar
        cal.firstWeekday = firstWeekday
        cal.minimumDaysInFirstWeek = 4
        self.calendar = cal
        self.firstWeekday = firstWeekday
    }

    // MARK: Days

    public func isScheduled(_ rule: HabitRule, on day: Int) -> Bool {
        guard day >= rule.startDay else { return false }
        switch rule.schedule {
        case .daily: return true
        case .weekdays(let days): return days.contains(calendar.component(.weekday, from: date(day)))
        case .timesPerWeek: return false
        case .everyNDays(let n): return n > 0 && daysBetween(rule.startDay, day) % n == 0
        }
    }

    public func isDone(_ rule: HabitRule, _ entry: HabitDay?) -> Bool {
        guard let entry else { return false }
        return entry.isSkipped || entry.value >= rule.target
    }

    /// Done / total for habits scheduled on `day` (weekly habits are left out).
    public func dayProgress(_ habits: [(rule: HabitRule, logs: [Int: HabitDay])], on day: Int) -> (done: Int, total: Int) {
        let scheduled = habits.filter { isScheduled($0.rule, on: day) }
        return (scheduled.count { isDone($0.rule, $0.logs[day]) }, scheduled.count)
    }

    /// What a calendar cell shows for one day.
    public enum DayStatus: Sendable, Equatable {
        /// Before the start day, after today, or not scheduled (and nothing logged).
        case none
        case done
        /// Count habit started but below target: share of the target reached (0–1).
        case partial(Double)
        case skipped
        /// Scheduled, in the past, not done.
        case missed
        /// Scheduled today, not done yet.
        case pending
    }

    public func status(_ rule: HabitRule, _ entry: HabitDay?, on day: Int, today: Int) -> DayStatus {
        if let entry {
            if entry.isSkipped { return .skipped }
            if entry.value >= rule.target { return .done }
            if entry.value > 0 { return .partial(Double(entry.value) / Double(rule.target)) }
        }
        guard day <= today, isScheduled(rule, on: day) else { return .none }
        return day == today ? .pending : .missed
    }

    // MARK: Weeks

    /// Done days in the week containing `day` (for "2/3" on weekly habits).
    public func doneInWeek(_ rule: HabitRule, logs: [Int: HabitDay], containing day: Int) -> Int {
        weekDays(containing: day).count { $0 >= rule.startDay && isDone(rule, logs[$0]) }
    }

    /// The 7 day keys of the week containing `day`, in order.
    public func weekDays(containing day: Int) -> [Int] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date(day))!.start
        return (0..<7).map { DayKey.day(calendar.date(byAdding: .day, value: $0, to: start)!, calendar: calendar) }
    }

    /// Only one skip per habit per week (HAB-04).
    public func canSkip(_ rule: HabitRule, logs: [Int: HabitDay], on day: Int) -> Bool {
        let week = weekKey(day)
        return !logs.contains { $0.key != day && $0.value.isSkipped && weekKey($0.key) == week }
    }

    // MARK: Streaks & rates

    public func streak(_ rule: HabitRule, logs: [Int: HabitDay], today: Int) -> HabitStreak {
        var run = 0, best = 0
        if let perWeek = rule.timesPerWeek {
            let current = weekKey(today)
            for (week, count) in weekCounts(rule, logs: logs, from: rule.startDay, through: today) {
                if count >= perWeek {
                    run += 1
                    best = max(best, run)
                } else if week != current {
                    run = 0
                }
            }
            return HabitStreak(current: run, best: best, inWeeks: true)
        }
        for day in days(from: rule.startDay, through: today) where isScheduled(rule, on: day) {
            if isDone(rule, logs[day]) {
                run += 1
                best = max(best, run)
            } else if day != today {
                run = 0
            }
        }
        return HabitStreak(current: run, best: best, inWeeks: false)
    }

    /// Share of the last `days` days (ending today) that were done, 0–1. Today / the current week only
    /// count once done. nil when nothing was due in the window.
    public func completionRate(_ rule: HabitRule, logs: [Int: HabitDay], today: Int, days: Int) -> Double? {
        let from = max(rule.startDay, DayKey.adding(-(days - 1), to: today, calendar: calendar))
        if let perWeek = rule.timesPerWeek {
            let current = weekKey(today)
            let weeks = weekCounts(rule, logs: logs, from: from, through: today)
                .filter { $0.week != current || $0.count >= perWeek }
            guard !weeks.isEmpty else { return nil }
            let done = weeks.reduce(0) { $0 + min($1.count, perWeek) }
            return Double(done) / Double(weeks.count * perWeek)
        }
        let due = self.days(from: from, through: today).filter {
            isScheduled(rule, on: $0) && ($0 != today || isDone(rule, logs[$0]))
        }
        guard !due.isEmpty else { return nil }
        return Double(due.count { isDone(rule, logs[$0]) }) / Double(due.count)
    }

    // MARK: Helpers

    public func weekKey(_ day: Int) -> Int {
        DayKey.week(date(day), firstWeekday: firstWeekday, calendar: calendar)
    }

    func days(from: Int, through: Int) -> [Int] {
        guard from <= through else { return [] }
        var result: [Int] = []
        var d = date(from)
        while true {
            let key = DayKey.day(d, calendar: calendar)
            if key > through { break }
            result.append(key)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return result
    }

    private func weekCounts(_ rule: HabitRule, logs: [Int: HabitDay], from: Int, through: Int) -> [(week: Int, count: Int)] {
        var result: [(week: Int, count: Int)] = []
        for day in days(from: from, through: through) {
            let week = weekKey(day)
            let done = isDone(rule, logs[day]) ? 1 : 0
            if result.last?.week == week {
                result[result.count - 1].count += done
            } else {
                result.append((week, done))
            }
        }
        return result
    }

    private func date(_ day: Int) -> Date {
        DayKey.date(fromDay: day, calendar: calendar)!
    }

    private func daysBetween(_ a: Int, _ b: Int) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day!
    }
}
