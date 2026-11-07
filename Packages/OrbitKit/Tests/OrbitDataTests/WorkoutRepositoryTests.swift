import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

struct WorkoutRepositoryTests {
    func library(_ ctx: ModelContext) throws -> [String: Exercise] {
        try ExerciseLibrary.seedIfNeeded(ctx)
        return Dictionary(try ctx.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0) }) { a, _ in a }
    }

    /// A finished session with one exercise's sets.
    @discardableResult
    func session(_ ctx: ModelContext, _ exercise: Exercise, day: Int, _ sets: [(Double, Int)]) -> WorkoutSession {
        let start = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        let s = WorkoutSession(startedAt: start)
        s.endedAt = start.addingTimeInterval(3_600)
        ctx.insert(s)
        for (i, (w, r)) in sets.enumerated() {
            let set = WorkoutSet(exercise: exercise, exerciseOrder: 0, setIndex: i, reps: r, weightKg: w, isCompleted: true)
            ctx.insert(set)
            s.sets.append(set)
        }
        return s
    }

    @Test func addRemoveMoveItems() throws {
        let ctx = try freshContext()
        let lib = try library(ctx)
        let routine = WorkoutRepository.createRoutine(name: "Push", sortOrder: 0, in: ctx)
        for key in ["exercise.benchPress", "exercise.overheadPress", "exercise.plank"] {
            WorkoutRepository.addItem(lib[key]!, to: routine, in: ctx)
        }
        #expect(routine.orderedItems.map(\.order) == [0, 1, 2])
        #expect(routine.orderedItems.last?.repMin == 30)  // duration exercise defaults to seconds

        WorkoutRepository.moveItems(in: routine, fromOffsets: [2], toOffset: 0, in: ctx)
        #expect(routine.orderedItems.map { $0.exercise!.name } == ["exercise.plank", "exercise.benchPress", "exercise.overheadPress"])

        WorkoutRepository.removeItems(at: [1], from: routine, in: ctx)
        #expect(routine.orderedItems.map { $0.exercise!.name } == ["exercise.plank", "exercise.overheadPress"])
        #expect(routine.orderedItems.map(\.order) == [0, 1])
    }

    @Test func routineForWeekday() {
        let a = RoutineTemplate(name: "A", weekdays: [2, 5], sortOrder: 1)
        let b = RoutineTemplate(name: "B", weekdays: [7], sortOrder: 0)
        let cal = Calendar(identifier: .gregorian)
        let saturday = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
        let sunday = cal.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
        #expect(WorkoutHistory.routine(for: saturday, in: [a, b], calendar: cal)?.name == "B")
        #expect(WorkoutHistory.routine(for: sunday, in: [a, b], calendar: cal) == nil)
    }

    @Test func suggestionUsesHistory() throws {
        let ctx = try freshContext()
        let lib = try library(ctx)
        let bench = lib["exercise.benchPress"]!
        let routine = WorkoutRepository.createRoutine(name: "Push", sortOrder: 0, in: ctx)
        let item = WorkoutRepository.addItem(bench, to: routine, in: ctx)
        #expect(WorkoutHistory.suggestion(for: item, sessions: [], increment: 2.5)?.reason == .calibration)

        let sessions = [session(ctx, bench, day: 1, [(60, 10), (60, 9)]), session(ctx, bench, day: 3, [(60, 12), (60, 12)])]
        let s = WorkoutHistory.suggestion(for: item, sessions: sessions, increment: 2.5)
        #expect(s == ProgressionSuggestion(weightKg: 62.5, reason: .increase(byKg: 2.5, reps: 12)))
        #expect(WorkoutHistory.setsPerSession(exerciseID: bench.id, in: sessions).first?.first?.reps == 12)  // newest first
    }

    @Test func recordBadge() throws {
        let ctx = try freshContext()
        let bench = try library(ctx)["exercise.benchPress"]!
        let first = session(ctx, bench, day: 1, [(60, 10)])
        let same = session(ctx, bench, day: 2, [(60, 8)])
        let better = session(ctx, bench, day: 3, [(65, 8)])
        let all = [first, same, better]
        #expect(!WorkoutHistory.hasRecord(first, among: all))   // nothing to beat yet
        #expect(!WorkoutHistory.hasRecord(same, among: all))
        #expect(WorkoutHistory.hasRecord(better, among: all))
    }
}
