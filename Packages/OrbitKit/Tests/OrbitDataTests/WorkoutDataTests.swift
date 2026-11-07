import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

struct WorkoutDataTests {
    @Test func seedingIsIdempotent() throws {
        let ctx = try freshContext()
        let first = try ExerciseLibrary.seedIfNeeded(ctx)
        #expect(first == ExerciseLibrary.entries.count)
        #expect(first >= 50)
        #expect(try ExerciseLibrary.seedIfNeeded(ctx) == 0)
        #expect(Set(ExerciseLibrary.entries.map(\.key)).count == ExerciseLibrary.entries.count)  // no duplicate keys
    }

    @Test func installPushPullLegs() throws {
        let ctx = try freshContext()
        let routines = try ProgramPreset.pushPullLegs.install(in: ctx, language: .id)
        #expect(routines.count == 3)
        #expect(routines.map { $0.items.count } == [5, 5, 6])
        let push = routines[0]
        #expect(push.orderedItems.first?.exercise?.name == "exercise.benchPress")
        #expect(push.orderedItems.first?.targetSets == 4)
        #expect(push.orderedItems.first?.restSec == 120)  // from the exercise default
        #expect(push.weekdays == [2, 5])
    }

    @Test func builtInNamesFallBackToKeyWithoutBundle() {
        let e = Exercise(name: "exercise.benchPress", type: .weightReps, muscleGroup: .chest, isCustom: false)
        // swift test has no Localizable bundle, so the key comes back unchanged instead of crashing.
        #expect(e.displayName(language: .id) == "exercise.benchPress")
        let custom = Exercise(name: "Sled push", type: .weightReps, muscleGroup: .legs)
        #expect(custom.displayName(language: .en) == "Sled push")
    }

    @Test func backupRoundTripKeepsWorkouts() throws {
        let ctx = try freshContext()
        let routines = try ProgramPreset.fullBody.install(in: ctx, language: .en)
        let squat = try #require(routines[0].orderedItems.first?.exercise)
        let custom = Exercise(name: "Sled push", type: .weightReps, muscleGroup: .legs, isLowerBody: true)
        ctx.insert(custom)
        let session = WorkoutSession(startedAt: Date(timeIntervalSince1970: 1_000), template: routines[0])
        session.endedAt = Date(timeIntervalSince1970: 4_000)
        ctx.insert(session)
        for (i, (w, r)) in [(100.0, 8), (100.0, 7)].enumerated() {
            let set = WorkoutSet(exercise: squat, exerciseOrder: 0, setIndex: i, reps: r, weightKg: w, isCompleted: true)
            ctx.insert(set)
            session.sets.append(set)
        }
        let customSet = WorkoutSet(exercise: custom, exerciseOrder: 1, setIndex: 0, reps: 10, weightKg: 80, isCompleted: true)
        ctx.insert(customSet)
        session.sets.append(customSet)
        try ctx.save()

        let data = try BackupService.export(from: freshDefaults(), context: ctx)
        let target = try freshContext()
        try BackupService.restore(BackupService.read(data), into: freshDefaults(), context: target)

        let first = try BackupService.read(data).workouts
        let again = try BackupService.read(BackupService.export(from: freshDefaults(), context: target)).workouts
        #expect(again.sessions == first.sessions)
        #expect(again.routines == first.routines)
        #expect(Set(again.exercises.map(\.id)) == Set(first.exercises.map(\.id)))
        let restored = try target.fetch(FetchDescriptor<WorkoutSession>()).first
        #expect(restored?.sets.count == 3)
        #expect(restored?.template?.name == routines[0].name)
    }

    @Test func oldBackupRestoresBuiltInLibrary() throws {
        let ctx = try freshContext()
        try BackupService.restore(Backup(schemaVersion: 2, exportedAt: .now, settings: .defaults), into: freshDefaults(), context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Exercise>()) == ExerciseLibrary.entries.count)
    }

    /// The real upgrade path: a V1 store on disk with habits opens fine under V2.
    @Test func migratesV1StoreToV2() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-mig-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let v1 = try OrbitData.makeContainer(at: url, version: OrbitSchemaV1.self)
            let ctx = ModelContext(v1)
            let habit = Habit(name: "Baca", iconName: "book")
            ctx.insert(habit)
            HabitRepository.toggle(habit, day: 20261107, in: ctx)
        }
        let v2 = try OrbitData.makeContainer(at: url, version: OrbitSchemaV2.self)
        let ctx = ModelContext(v2)
        let habits = try ctx.fetch(FetchDescriptor<Habit>())
        #expect(habits.map(\.name) == ["Baca"])
        #expect(habits.first?.logs.count == 1)
        try ExerciseLibrary.seedIfNeeded(ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Exercise>()) > 0)
    }
}
