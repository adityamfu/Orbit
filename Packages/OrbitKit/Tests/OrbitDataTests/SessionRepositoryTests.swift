import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

@MainActor
struct SessionRepositoryTests {
    func setup() throws -> (ModelContext, RoutineTemplate) {
        let ctx = try freshContext()
        let routine = try ProgramPreset.pushPullLegs.install(in: ctx, language: .id)[0]  // Push: bench 4×8–12 first
        return (ctx, routine)
    }

    func all(_ ctx: ModelContext) throws -> [WorkoutSession] { try ctx.fetch(FetchDescriptor<WorkoutSession>()) }

    /// Runs a full Push session ticking every set with the given bench reps.
    @MainActor
    func runSession(_ ctx: ModelContext, _ routine: RoutineTemplate, benchReps: Int, at day: Int) async throws -> [SessionRecord] {
        let start = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        let s = SessionRepository.start(template: routine, history: try all(ctx), increment: 2.5, in: ctx, now: start)
        for entry in SessionRepository.exercises(in: s) {
            for set in entry.sets {
                if entry.order == 0 { set.reps = benchReps; set.weightKg = set.weightKg ?? 60 }
                SessionRepository.setCompleted(set, true, in: ctx, now: start)
            }
        }
        return await SessionRepository.finish(s, history: try all(ctx), in: ctx, now: start.addingTimeInterval(3_600))
    }

    @Test func startPrefillsFromRoutine() throws {
        let (ctx, routine) = try setup()
        let s = SessionRepository.start(template: routine, history: [], increment: 2.5, in: ctx)
        let entries = SessionRepository.exercises(in: s)
        #expect(entries.count == 5)
        #expect(entries[0].sets.count == 4)
        #expect(entries[0].sets.allSatisfy { $0.reps == 12 && $0.weightKg == nil && !$0.isCompleted })  // calibration
        #expect(entries[0].restSec == 120)
        #expect(entries[0].repRange == 8...12)
        #expect(SessionRepository.activeSession(in: ctx)?.id == s.id)
    }

    @Test @MainActor
    func nextSessionUsesSuggestionAndPrevious() async throws {
        let (ctx, routine) = try setup()
        _ = try await runSession(ctx, routine, benchReps: 12, at: 1)  // all sets hit 12 at 60 kg
        let next = SessionRepository.start(template: routine, history: try all(ctx), increment: 2.5, in: ctx,
                                           now: Date(timeIntervalSince1970: 3 * 86_400))
        let bench = SessionRepository.exercises(in: next)[0]
        #expect(bench.sets.allSatisfy { $0.weightKg == 62.5 })
        let previous = SessionRepository.previousSets(for: bench.exercise, before: next, history: try all(ctx))
        #expect(previous.count == 4)
        #expect(previous.first?.weightKg == 60)
    }

    @Test @MainActor
    func finishDropsUntickedSetsAndReportsRecords() async throws {
        let (ctx, routine) = try setup()
        #expect((try await runSession(ctx, routine, benchReps: 10, at: 1)).isEmpty)  // first session: nothing to beat

        let start = Date(timeIntervalSince1970: 5 * 86_400)
        let s = SessionRepository.start(template: routine, history: try all(ctx), increment: 2.5, in: ctx, now: start)
        let bench = SessionRepository.exercises(in: s)[0]
        bench.sets[0].reps = 12
        SessionRepository.setCompleted(bench.sets[0], true, in: ctx)  // only one set ticked
        let records = await SessionRepository.finish(s, history: try all(ctx), in: ctx, now: start.addingTimeInterval(1_800))
        #expect(s.sets.count == 1)
        #expect(s.endedAt != nil)
        #expect(records.first?.kinds.contains(.e1RM) == true)  // 60 × 12 beats 60 × 10
    }

    @Test @MainActor
    func emptyFinishDiscards() async throws {
        let (ctx, routine) = try setup()
        let s = SessionRepository.start(template: routine, history: [], increment: 2.5, in: ctx)
        await SessionRepository.finish(s, history: [], in: ctx)
        #expect(try all(ctx).isEmpty)
    }

    @Test func addSetsAndWarmupsAndReorder() throws {
        let (ctx, routine) = try setup()
        let s = SessionRepository.start(template: routine, history: [], increment: 2.5, in: ctx)
        let first = SessionRepository.exercises(in: s)[0]
        first.sets.forEach { $0.weightKg = 60 }
        SessionRepository.addSet(to: s, exerciseOrder: 0, in: ctx)
        SessionRepository.addSet(to: s, exerciseOrder: 0, warmup: true, in: ctx)
        let sets = SessionRepository.exercises(in: s)[0].sets
        #expect(sets.count == 6)
        #expect(sets.first?.isWarmup == true)
        #expect(sets.first?.weightKg == 30)
        #expect(sets.map(\.setIndex) == [0, 1, 2, 3, 4, 5])

        SessionRepository.deleteSet(sets[2], from: s, in: ctx)
        #expect(SessionRepository.exercises(in: s)[0].sets.map(\.setIndex) == [0, 1, 2, 3, 4])

        let secondName = SessionRepository.exercises(in: s)[1].exercise.name
        SessionRepository.moveExercise(order: 1, by: -1, in: s, in: ctx)
        #expect(SessionRepository.exercises(in: s)[0].exercise.name == secondName)

        SessionRepository.removeExercise(order: 0, from: s, in: ctx)
        #expect(SessionRepository.exercises(in: s).map(\.order) == [0, 1, 2, 3])
    }

    @Test func emptySessionAddExercise() throws {
        let ctx = try freshContext()
        try ExerciseLibrary.seedIfNeeded(ctx)
        let run = try #require(try ctx.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == "exercise.running" })).first)
        let s = SessionRepository.start(template: nil, history: [], increment: 2.5, in: ctx)
        SessionRepository.addExercise(run, to: s, history: [], increment: 2.5, in: ctx)
        #expect(SessionRepository.exercises(in: s).first?.sets.count == 1)  // cardio: one entry
    }
}

struct NextOpenSetTests {
    @Test func walksExercisesInOrder() throws {
        let ctx = try freshContext()
        let routine = try ProgramPreset.fullBody.install(in: ctx, language: .id)[0]
        let s = SessionRepository.start(template: routine, history: [], increment: 2.5, in: ctx)
        let first = SessionRepository.exercises(in: s)[0]
        #expect(SessionRepository.nextOpenSet(in: s)?.set.id == first.sets[0].id)
        first.sets.forEach { SessionRepository.setCompleted($0, true, in: ctx) }
        let next = try #require(SessionRepository.nextOpenSet(in: s))
        #expect(next.exercise.order == 1)
        #expect(next.index == 0)
        SessionRepository.exercises(in: s).flatMap(\.sets).forEach { SessionRepository.setCompleted($0, true, in: ctx) }
        #expect(SessionRepository.nextOpenSet(in: s) == nil)
    }
}
