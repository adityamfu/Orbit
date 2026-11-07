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

struct WorkoutProgressTests {
    @Test func progressAndWeeklyVolume() throws {
        let ctx = try freshContext()
        try ExerciseLibrary.seedIfNeeded(ctx)
        let lib = Dictionary(try ctx.fetch(FetchDescriptor<Exercise>()).map { ($0.name, $0) }) { a, _ in a }
        let bench = lib["exercise.benchPress"]!, squat = lib["exercise.backSquat"]!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 18))! }
        func session(_ date: Date, _ sets: [(Exercise, Double, Int, Bool)]) {
            let s = WorkoutSession(startedAt: date)
            s.endedAt = date.addingTimeInterval(3_600)
            ctx.insert(s)
            for (i, (e, w, r, warm)) in sets.enumerated() {
                let set = WorkoutSet(exercise: e, exerciseOrder: 0, setIndex: i, reps: r, weightKg: w, isWarmup: warm, isCompleted: true)
                ctx.insert(set)
                s.sets.append(set)
            }
        }
        session(day(2), [(bench, 40, 10, true), (bench, 60, 10, false), (bench, 60, 12, false)])   // Mon wk 45
        session(day(5), [(squat, 100, 5, false)])                                                    // Thu wk 45
        session(day(9), [(bench, 62.5, 8, false), (bench, 60, 12, false)])                           // Mon wk 46
        let all = try ctx.fetch(FetchDescriptor<WorkoutSession>())

        let points = WorkoutHistory.progress(exerciseID: bench.id, in: all)
        let tops: [Double] = points.map(\.topWeightKg)
        #expect(tops == [60, 62.5])
        #expect(points[0].topReps == 12)                       // tie on weight → more reps; warm-up ignored
        #expect(abs(points[0].e1RM - 84) < 0.01)
        let expectedVolume: Double = 62.5 * 8 + 60 * 12
        #expect(points[1].volumeKg == expectedVolume)

        let volume = WorkoutHistory.weeklyVolume(all, weeks: 3, firstWeekday: 2, now: day(10), calendar: cal)
        #expect(volume.count == 3 * MuscleGroup.allCases.count)
        let chest = volume.filter { $0.muscle == .chest }.map(\.kg)
        let expectedChest: [Double] = [0, 1_320, 1_220]
        #expect(chest == expectedChest)                        // empty week stays as 0
        let legs: [Double] = volume.filter { $0.muscle == .legs }.map(\.kg)
        #expect(legs == [0, 500, 0])
    }
}
