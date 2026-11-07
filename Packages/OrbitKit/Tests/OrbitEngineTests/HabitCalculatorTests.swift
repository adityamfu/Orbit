import Foundation
import Testing
@testable import OrbitEngine

/// Reference: Sat 7 Nov 2026 is "today"; its Monday-started week runs 2–8 Nov.
struct HabitCalculatorTests {
    let calc: HabitCalculator = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return HabitCalculator(calendar: c, firstWeekday: 2)
    }()
    let today = 20261107

    func day(_ offset: Int) -> Int { DayKey.adding(offset, to: today, calendar: calc.calendar) }

    /// Logs with value 1 on the given offsets from today.
    func done(_ offsets: [Int], value: Int = 1) -> [Int: HabitDay] {
        Dictionary(uniqueKeysWithValues: offsets.map { (day($0), HabitDay(value: value)) })
    }

    // MARK: Schedule

    @Test func weekdaysSchedule() {
        // Mon, Wed, Fri
        let rule = HabitRule(schedule: .weekdays([2, 4, 6]), startDay: 20261001)
        #expect(calc.isScheduled(rule, on: 20261106))   // Fri
        #expect(!calc.isScheduled(rule, on: 20261107))  // Sat
        #expect(calc.isScheduled(rule, on: 20261102))   // Mon
    }

    @Test func everyNDaysCountsFromStart() {
        let rule = HabitRule(schedule: .everyNDays(3), startDay: 20261101)
        #expect(calc.isScheduled(rule, on: 20261101))
        #expect(!calc.isScheduled(rule, on: 20261102))
        #expect(calc.isScheduled(rule, on: 20261104))
        #expect(!calc.isScheduled(rule, on: 20261031))  // before start
    }

    @Test func weeklyHabitIsNeverDayScheduled() {
        let rule = HabitRule(schedule: .timesPerWeek(3), startDay: 20261001)
        #expect(!calc.isScheduled(rule, on: today))
    }

    // MARK: Daily streaks

    @Test func todayNotDoneDoesNotBreakStreak() {
        let rule = HabitRule(schedule: .daily, startDay: day(-30))
        let logs = done([-5, -4, -3, -2, -1])
        #expect(calc.streak(rule, logs: logs, today: today) == HabitStreak(current: 5, best: 5, inWeeks: false))
        let withToday = logs.merging(done([0])) { a, _ in a }
        #expect(calc.streak(rule, logs: withToday, today: today).current == 6)
    }

    @Test func missedDayBreaksStreakButKeepsBest() {
        let rule = HabitRule(schedule: .daily, startDay: day(-30))
        let logs = done([-10, -9, -8, -7, -2, -1])  // -6…-3 missed
        let s = calc.streak(rule, logs: logs, today: today)
        #expect(s.current == 2)
        #expect(s.best == 4)
    }

    @Test func unscheduledDaysDoNotBreakStreak() {
        // Mon/Wed/Fri habit done on 26, 28, 30 Oct and 2, 4, 6 Nov.
        let rule = HabitRule(schedule: .weekdays([2, 4, 6]), startDay: 20261026)
        let logs = Dictionary(uniqueKeysWithValues: [20261026, 20261028, 20261030, 20261102, 20261104, 20261106]
            .map { ($0, HabitDay(value: 1)) })
        #expect(calc.streak(rule, logs: logs, today: today).current == 6)
    }

    @Test func skippedDayCountsAsDone() {
        let rule = HabitRule(schedule: .daily, startDay: day(-30))
        var logs = done([-3, -1])
        logs[day(-2)] = HabitDay(value: 0, isSkipped: true)
        #expect(calc.streak(rule, logs: logs, today: today).current == 3)
    }

    @Test func countHabitNeedsTarget() {
        let rule = HabitRule(schedule: .daily, target: 8, startDay: day(-30))
        var logs = done([-2], value: 8)
        logs[day(-1)] = HabitDay(value: 5)  // partial: not done, breaks the streak
        #expect(!calc.isDone(rule, logs[day(-1)]))
        #expect(calc.streak(rule, logs: logs, today: today).current == 0)
        #expect(calc.streak(rule, logs: logs, today: today).best == 1)
    }

    @Test func futureStartHasNoStreak() {
        let rule = HabitRule(schedule: .daily, startDay: day(3))
        #expect(calc.streak(rule, logs: [:], today: today) == HabitStreak(current: 0, best: 0, inWeeks: false))
    }

    // MARK: Weekly streaks

    @Test func weeklyStreakCountsWeeks() {
        // 3× per week; weeks of 19 Oct, 26 Oct met; current week (2 Nov) has 1 so far.
        let rule = HabitRule(schedule: .timesPerWeek(3), startDay: 20261019)
        let logs = Dictionary(uniqueKeysWithValues: [20261019, 20261021, 20261023, 20261026, 20261027, 20261030, 20261103]
            .map { ($0, HabitDay(value: 1)) })
        #expect(calc.streak(rule, logs: logs, today: today) == HabitStreak(current: 2, best: 2, inWeeks: true))
        #expect(calc.doneInWeek(rule, logs: logs, containing: today) == 1)
    }

    @Test func missedWeekBreaksWeeklyStreak() {
        let rule = HabitRule(schedule: .timesPerWeek(2), startDay: 20261012)
        // week 12 Oct met, week 19 Oct only 1, week 26 Oct met
        let logs = Dictionary(uniqueKeysWithValues: [20261012, 20261013, 20261020, 20261026, 20261028]
            .map { ($0, HabitDay(value: 1)) })
        let s = calc.streak(rule, logs: logs, today: today)
        #expect(s.current == 1)
        #expect(s.best == 1)
    }

    // MARK: Skips

    @Test func oneSkipPerWeek() {
        let rule = HabitRule(schedule: .daily, startDay: 20261001)
        let logs = [20261103: HabitDay(value: 0, isSkipped: true)]
        #expect(!calc.canSkip(rule, logs: logs, on: 20261105))  // same week
        #expect(calc.canSkip(rule, logs: logs, on: 20261103))   // re-skipping the same day is fine
        #expect(calc.canSkip(rule, logs: logs, on: 20261109))   // next week
    }

    // MARK: Rates & progress

    @Test func completionRateIgnoresUnfinishedToday() {
        let rule = HabitRule(schedule: .daily, startDay: day(-100))
        let logs = done(Array(-29 ... -15))  // 15 of the 29 finished days
        let rate = calc.completionRate(rule, logs: logs, today: today, days: 30)!
        #expect(abs(rate - 15.0 / 29.0) < 0.0001)
    }

    @Test func completionRateRespectsStartDay() {
        let rule = HabitRule(schedule: .daily, startDay: day(-1))
        #expect(calc.completionRate(rule, logs: done([-1]), today: today, days: 30) == 1)
        #expect(calc.completionRate(HabitRule(schedule: .daily, startDay: today), logs: [:], today: today, days: 30) == nil)
    }

    @Test func dayProgressSkipsWeeklyHabits() {
        let daily = HabitRule(schedule: .daily, startDay: 20261001)
        let weekly = HabitRule(schedule: .timesPerWeek(3), startDay: 20261001)
        let p = calc.dayProgress([(daily, done([0])), (daily, [:]), (weekly, done([0]))], on: today)
        #expect(p.done == 1)
        #expect(p.total == 2)
    }

    @Test func weekDaysStartOnConfiguredDay() {
        #expect(calc.weekDays(containing: today) == [20261102, 20261103, 20261104, 20261105, 20261106, 20261107, 20261108])
    }
}
