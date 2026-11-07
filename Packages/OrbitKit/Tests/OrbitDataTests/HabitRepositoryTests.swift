import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

struct HabitRepositoryTests {
    let calc = HabitCalculator(firstWeekday: 2)
    let day = 20261107

    @Test func toggleCheckHabit() throws {
        let ctx = try freshContext()
        let h = Habit(name: "Baca", iconName: "book")
        ctx.insert(h)
        HabitRepository.toggle(h, day: day, in: ctx)
        #expect(h.log(on: day)?.value == 1)
        HabitRepository.toggle(h, day: day, in: ctx)
        try ctx.save()
        #expect(h.log(on: day) == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<HabitLog>()) == 0)
    }

    @Test func incrementCountHabitPastTarget() throws {
        let ctx = try freshContext()
        let h = Habit(name: "Air", iconName: "drop", type: .count, targetCount: 2)
        ctx.insert(h)
        HabitRepository.increment(h, day: day, in: ctx)
        HabitRepository.increment(h, day: day, in: ctx)
        HabitRepository.increment(h, day: day, in: ctx)
        #expect(h.log(on: day)?.value == 3)
        #expect(h.logs.count == 1)
        // Toggling a finished count habit resets it.
        HabitRepository.toggle(h, day: day, in: ctx)
        #expect(h.log(on: day) == nil)
    }

    @Test func oneLogPerDayIsEnforcedByStore() throws {
        let ctx = try freshContext()
        let h = Habit(name: "Air", iconName: "drop")
        ctx.insert(h)
        for value in [1, 2] {
            let log = HabitLog(habit: h, dayKey: day, value: value)
            ctx.insert(log)
            log.habit = h
        }
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<HabitLog>()) == 1)
    }

    @Test func skipLimitedToOncePerWeek() throws {
        let ctx = try freshContext()
        let h = Habit(name: "Lari", iconName: "figure.run", startDate: .distantPast)
        ctx.insert(h)
        #expect(HabitRepository.setSkipped(true, for: h, day: 20261103, calculator: calc, in: ctx))
        #expect(!HabitRepository.setSkipped(true, for: h, day: 20261105, calculator: calc, in: ctx))
        #expect(h.log(on: 20261105) == nil)
        // Un-skipping frees the week again.
        HabitRepository.setSkipped(false, for: h, day: 20261103, calculator: calc, in: ctx)
        #expect(h.log(on: 20261103) == nil)
        #expect(HabitRepository.setSkipped(true, for: h, day: 20261105, calculator: calc, in: ctx))
    }

    @Test func moveRewritesSortOrder() throws {
        let ctx = try freshContext()
        let habits = (0..<4).map { Habit(name: "H\($0)", iconName: "star", sortOrder: $0) }
        habits.forEach(ctx.insert)
        HabitRepository.move(habits, fromOffsets: [0], toOffset: 3)  // H0 goes after H2
        #expect(habits.sorted { $0.sortOrder < $1.sortOrder }.map(\.name) == ["H1", "H2", "H0", "H3"])
    }

    @Test func scheduleRoundTripsThroughStorage() {
        let h = Habit(name: "X", iconName: "star", schedule: .weekdays([6, 2]))
        #expect(h.schedule == .weekdays([2, 6]))
        #expect(h.scheduleWeekdays == [2, 6])
        h.schedule = .everyNDays(3)
        #expect(h.schedule == .everyNDays(3))
        #expect(h.scheduleWeekdays.isEmpty)
    }

    @Test @MainActor func previewDataLoads() throws {
        let container = OrbitData.makePreviewContainer()  // keep it alive: mainContext doesn't retain it
        let ctx = container.mainContext
        #expect(try ctx.fetchCount(FetchDescriptor<Habit>()) == 7)
        #expect(try ctx.fetchCount(FetchDescriptor<HabitLog>()) > 50)
    }
}
