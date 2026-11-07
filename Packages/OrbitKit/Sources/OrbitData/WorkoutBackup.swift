import Foundation
import SwiftData

/// Everything workout-related in a backup (schema v3+). Links between records use ids.
public struct WorkoutRecords: Codable, Equatable, Sendable {
    public var exercises: [ExerciseRecord] = []
    public var routines: [RoutineRecord] = []
    public var sessions: [SessionRecord] = []

    public init() {}

    public struct ExerciseRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var name: String
        public var typeRaw: String
        public var muscleGroupRaw: String
        public var isLowerBody: Bool
        public var equipmentRaw: String
        public var defaultRestSec: Int
        public var isCustom: Bool
        public var isArchived: Bool
    }

    public struct RoutineRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var name: String
        public var weekdays: [Int]
        public var sortOrder: Int
        public var items: [Item]

        public struct Item: Codable, Equatable, Sendable {
            public var exerciseID: UUID?
            public var order: Int
            public var targetSets: Int
            public var repMin: Int
            public var repMax: Int
            public var restSec: Int
        }
    }

    public struct SessionRecord: Codable, Equatable, Sendable {
        public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var startedAt: Date
        public var endedAt: Date?
        public var routineID: UUID?
        public var note: String
        public var sourceRaw: String
        public var healthKitUUID: UUID?
        public var activityTypeRaw: String
        public var energyKcal: Double?
        public var distanceM: Double?
        public var avgHeartRate: Double?
        public var sets: [SetRecordData]

        public struct SetRecordData: Codable, Equatable, Sendable {
            public var exerciseID: UUID?
            public var exerciseOrder: Int
            public var setIndex: Int
            public var reps: Int?
            public var weightKg: Double?
            public var durationSec: Int?
            public var distanceM: Double?
            public var energyKcal: Double?
            public var isWarmup: Bool
            public var isCompleted: Bool
            public var completedAt: Date?
        }
    }
}

extension WorkoutRecords {
    init(context: ModelContext) throws {
        exercises = try context.fetch(FetchDescriptor<Exercise>()).map {
            ExerciseRecord(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, name: $0.name, typeRaw: $0.typeRaw,
                           muscleGroupRaw: $0.muscleGroupRaw, isLowerBody: $0.isLowerBody, equipmentRaw: $0.equipmentRaw,
                           defaultRestSec: $0.defaultRestSec, isCustom: $0.isCustom, isArchived: $0.isArchived)
        }
        routines = try context.fetch(FetchDescriptor<RoutineTemplate>(sortBy: [SortDescriptor(\.sortOrder)])).map { t in
            RoutineRecord(id: t.id, createdAt: t.createdAt, updatedAt: t.updatedAt, name: t.name, weekdays: t.weekdays,
                          sortOrder: t.sortOrder, items: t.orderedItems.map {
                              .init(exerciseID: $0.exercise?.id, order: $0.order, targetSets: $0.targetSets,
                                    repMin: $0.repMin, repMax: $0.repMax, restSec: $0.restSec)
                          })
        }
        sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)])).map { s in
            SessionRecord(id: s.id, createdAt: s.createdAt, updatedAt: s.updatedAt, startedAt: s.startedAt, endedAt: s.endedAt,
                          routineID: s.template?.id, note: s.note, sourceRaw: s.sourceRaw, healthKitUUID: s.healthKitUUID,
                          activityTypeRaw: s.activityTypeRaw, energyKcal: s.energyKcal, distanceM: s.distanceM,
                          avgHeartRate: s.avgHeartRate,
                          sets: s.sets.sorted { ($0.exerciseOrder, $0.setIndex) < ($1.exerciseOrder, $1.setIndex) }.map {
                              .init(exerciseID: $0.exercise?.id, exerciseOrder: $0.exerciseOrder, setIndex: $0.setIndex,
                                    reps: $0.reps, weightKg: $0.weightKg, durationSec: $0.durationSec, distanceM: $0.distanceM,
                                    energyKcal: $0.energyKcal, isWarmup: $0.isWarmup, isCompleted: $0.isCompleted,
                                    completedAt: $0.completedAt)
                          })
        }
    }

    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: WorkoutSet.self)
        try context.delete(model: WorkoutSession.self)
        try context.delete(model: TemplateItem.self)
        try context.delete(model: RoutineTemplate.self)
        try context.delete(model: Exercise.self)
    }

    func insert(into context: ModelContext) {
        var exercisesByID: [UUID: Exercise] = [:]
        for r in exercises {
            let e = Exercise(id: r.id, name: r.name, type: .weightReps, muscleGroup: .chest, isCustom: r.isCustom,
                             isArchived: r.isArchived, createdAt: r.createdAt)
            e.updatedAt = r.updatedAt
            e.typeRaw = r.typeRaw
            e.muscleGroupRaw = r.muscleGroupRaw
            e.isLowerBody = r.isLowerBody
            e.equipmentRaw = r.equipmentRaw
            e.defaultRestSec = r.defaultRestSec
            context.insert(e)
            exercisesByID[r.id] = e
        }
        var routinesByID: [UUID: RoutineTemplate] = [:]
        for r in routines {
            let t = RoutineTemplate(id: r.id, name: r.name, weekdays: r.weekdays, sortOrder: r.sortOrder, createdAt: r.createdAt)
            t.updatedAt = r.updatedAt
            context.insert(t)
            for i in r.items {
                guard let exercise = i.exerciseID.flatMap({ exercisesByID[$0] }) else { continue }
                let item = TemplateItem(exercise: exercise, order: i.order, targetSets: i.targetSets, repMin: i.repMin,
                                        repMax: i.repMax, restSec: i.restSec)
                context.insert(item)
                t.items.append(item)
            }
            routinesByID[r.id] = t
        }
        for r in sessions {
            let s = WorkoutSession(id: r.id, startedAt: r.startedAt, template: r.routineID.flatMap { routinesByID[$0] },
                                   note: r.note, activityType: r.activityTypeRaw)
            s.createdAt = r.createdAt
            s.updatedAt = r.updatedAt
            s.endedAt = r.endedAt
            s.sourceRaw = r.sourceRaw
            s.healthKitUUID = r.healthKitUUID
            s.energyKcal = r.energyKcal
            s.distanceM = r.distanceM
            s.avgHeartRate = r.avgHeartRate
            context.insert(s)
            for d in r.sets {
                guard let exercise = d.exerciseID.flatMap({ exercisesByID[$0] }) else { continue }
                let set = WorkoutSet(exercise: exercise, exerciseOrder: d.exerciseOrder, setIndex: d.setIndex, reps: d.reps,
                                     weightKg: d.weightKg, durationSec: d.durationSec, distanceM: d.distanceM,
                                     energyKcal: d.energyKcal, isWarmup: d.isWarmup, isCompleted: d.isCompleted,
                                     completedAt: d.completedAt)
                context.insert(set)
                s.sets.append(set)
            }
        }
    }
}
