import Foundation
import SwiftData
import OrbitEngine

/// Every habit write goes through here so views, widgets and intents behave the same.
/// Each write saves right away: widgets read the store from another process, and autosave may come too late.
public enum HabitRepository {
    /// Sets the day's value; 0 removes the log.
    public static func setValue(_ value: Int, for habit: Habit, day: Int, in context: ModelContext) {
        if let log = habit.log(on: day) {
            if value <= 0 {
                delete(log, from: habit, in: context)
            } else {
                log.value = value
                log.isSkipped = false
                log.loggedAt = .now
            }
        } else if value > 0 {
            insertLog(habit: habit, day: day, value: value, skipped: false, in: context)
        }
        habit.updatedAt = .now
        save(context)
    }

    /// Check habits: done ↔ not done. Count habits: target reached ↔ 0.
    public static func toggle(_ habit: Habit, day: Int, in context: ModelContext) {
        let log = habit.log(on: day)
        let done = log.map { $0.isSkipped || $0.value >= habit.targetCount } ?? false
        setValue(done ? 0 : habit.targetCount, for: habit, day: day, in: context)
    }

    /// Count habits: +1 (may go past the target).
    public static func increment(_ habit: Habit, day: Int, in context: ModelContext) {
        setValue((habit.log(on: day)?.value ?? 0) + 1, for: habit, day: day, in: context)
    }

    /// Marks a day as a rest day. Returns false when this week's skip is already used (HAB-04).
    @discardableResult
    public static func setSkipped(_ skipped: Bool, for habit: Habit, day: Int, calculator: HabitCalculator,
                                  in context: ModelContext) -> Bool {
        let log = habit.log(on: day)
        if skipped {
            guard calculator.canSkip(habit.rule(calendar: calculator.calendar), logs: habit.dayLogs, on: day) else { return false }
            if let log {
                log.isSkipped = true
                log.loggedAt = .now
            } else {
                insertLog(habit: habit, day: day, value: 0, skipped: true, in: context)
            }
        } else if let log {
            if log.value > 0 { log.isSkipped = false } else { delete(log, from: habit, in: context) }
        }
        habit.updatedAt = .now
        save(context)
        return true
    }

    /// Persists a manual order after a drag in a list.
    public static func move(_ habits: [Habit], fromOffsets source: IndexSet, toOffset destination: Int) {
        // Same semantics as SwiftUI's Array.move(fromOffsets:toOffset:), without importing SwiftUI.
        let moving = source.map { habits[$0] }
        var ordered = habits.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        ordered.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        for (index, habit) in ordered.enumerated() where habit.sortOrder != index {
            habit.sortOrder = index
        }
        habits.first?.modelContext.map(save)
    }

    /// Used habits are archived, never deleted (CLAUDE.md data rule).
    public static func setArchived(_ archived: Bool, _ habit: Habit) {
        habit.isArchived = archived
        habit.updatedAt = .now
        habit.modelContext.map(save)
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Saving habits failed: \(error)")
        }
    }

    /// Also drops it from `habit.logs` right away; SwiftData would otherwise keep it there until the next save.
    private static func delete(_ log: HabitLog, from habit: Habit, in context: ModelContext) {
        habit.logs.removeAll { $0.persistentModelID == log.persistentModelID }
        context.delete(log)
    }

    private static func insertLog(habit: Habit, day: Int, value: Int, skipped: Bool, in context: ModelContext) {
        let log = HabitLog(habit: habit, dayKey: day, value: value, isSkipped: skipped)
        context.insert(log)
        // Append on the habit side: setting only `log.habit` updates the inverse silently,
        // so views observing `habit.logs` wouldn't redraw.
        habit.logs.append(log)
    }
}
