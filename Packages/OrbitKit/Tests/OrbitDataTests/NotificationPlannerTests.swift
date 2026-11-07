import Foundation
import Testing
import OrbitEngine
@testable import OrbitData

struct NotificationPlannerTests {
    let calc: HabitCalculator = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return HabitCalculator(calendar: c, firstWeekday: 2)
    }()
    let noSaver = SettingsSnapshot(language: .id, appearance: .system, firstWeekday: 2, cycleStartDay: 1,
                                   weightIncrement: 2.5, streakSaverEnabled: false)

    /// Sat 7 Nov 2026 at the given time, Jakarta.
    func now(_ hour: Int, _ minute: Int = 0) -> Date {
        calc.calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: hour, minute: minute))!
    }

    func habit(_ name: String, schedule: HabitRule.Schedule = .daily, reminders: [Int] = [21 * 60]) -> Habit {
        Habit(name: name, iconName: "star", schedule: schedule, reminderMinutes: reminders,
              startDate: calc.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!)
    }

    @Test func remindersOnlyOnScheduledDaysAndInTheFuture() {
        // Mon/Wed/Fri at 21:00. Now is Sat 22:00 → next ones: Mon 9, Wed 11, Fri 13.
        let h = habit("Lari", schedule: .weekdays([2, 4, 6]))
        let plan = NotificationPlanner.plan(habits: [h], calculator: calc, settings: noSaver, now: now(22))
        let days = plan.map { calc.calendar.component(.day, from: $0.date) }
        #expect(days == [9, 11, 13])
        #expect(plan.allSatisfy { calc.calendar.component(.hour, from: $0.date) == 21 })
        #expect(plan.first?.kind == .reminder(habitName: "Lari"))
    }

    @Test func doneTodaySkipsTodaysReminder() throws {
        let ctx = try freshContext()
        let h = habit("Baca")
        ctx.insert(h)
        HabitRepository.toggle(h, day: 20261107, in: ctx)
        let plan = NotificationPlanner.plan(habits: [h], calculator: calc, settings: noSaver, now: now(9))
        #expect(plan.first.map { calc.calendar.component(.day, from: $0.date) } == 8)
    }

    @Test func streakSaverCountsWhatsLeft() throws {
        let ctx = try freshContext()
        let a = habit("A", reminders: []), b = habit("B", reminders: [])
        ctx.insert(a)
        ctx.insert(b)
        HabitRepository.toggle(a, day: 20261107, in: ctx)
        let settings = SettingsSnapshot.defaults  // saver on at 20:00
        let plan = NotificationPlanner.plan(habits: [a, b], calculator: calc, settings: settings, now: now(9), days: 2)
        #expect(plan.map(\.id) == ["streak-20261107", "streak-20261108"])
        #expect(plan.first?.kind == .streakSaver(pending: 1))
        #expect(plan.last?.kind == .streakSaver(pending: 2))

        // Everything done today → no nudge tonight.
        HabitRepository.toggle(b, day: 20261107, in: ctx)
        let after = NotificationPlanner.plan(habits: [a, b], calculator: calc, settings: settings, now: now(9), days: 2)
        #expect(after.map(\.id) == ["streak-20261108"])
    }

    @Test func weeklyHabitStopsOnceWeekIsMet() throws {
        let ctx = try freshContext()
        let h = habit("Masak", schedule: .timesPerWeek(2), reminders: [18 * 60])
        ctx.insert(h)
        HabitRepository.toggle(h, day: 20261103, in: ctx)
        HabitRepository.toggle(h, day: 20261105, in: ctx)
        // Week of 2–8 Nov is met → next reminder is Monday 9 Nov.
        let plan = NotificationPlanner.plan(habits: [h], calculator: calc, settings: noSaver, now: now(9))
        #expect(plan.first.map { calc.calendar.component(.day, from: $0.date) } == 9)
    }

    @Test func keepsOnlyNearest64() {
        let many = (0..<20).map { habit("H\($0)", reminders: [8 * 60, 12 * 60, 20 * 60]) }
        let plan = NotificationPlanner.plan(habits: many, calculator: calc, settings: .defaults, now: now(0))
        #expect(plan.count == NotificationPlanner.limit)
        #expect(plan == plan.sorted { $0.date < $1.date })
    }

    @Test func archivedHabitsAreIgnored() {
        let h = habit("Old")
        h.isArchived = true
        #expect(NotificationPlanner.plan(habits: [h], calculator: calc, settings: noSaver, now: now(9)).isEmpty)
    }
}
