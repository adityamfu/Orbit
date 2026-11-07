import Foundation
import SwiftData
import OrbitEngine

/// V2 (Phase 3): adds workouts. Habit models are unchanged and reused from V1.
public enum OrbitSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [OrbitSchemaV1.Habit.self, OrbitSchemaV1.HabitLog.self,
         Exercise.self, RoutineTemplate.self, TemplateItem.self, WorkoutSession.self, WorkoutSet.self]
    }

    @Model
    public final class Exercise {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        /// Built-in: catalog key ("exercise.benchPress"). Custom: the user's text.
        public var name: String
        public var typeRaw: String
        public var muscleGroupRaw: String
        /// Lower-body lifts progress by 2× the weight step.
        public var isLowerBody: Bool
        public var equipmentRaw: String
        public var defaultRestSec: Int
        public var isCustom: Bool
        public var isArchived: Bool

        public init(id: UUID = UUID(), name: String, type: ExerciseKind, muscleGroup: MuscleGroup, isLowerBody: Bool = false,
                    equipment: Equipment = .barbell, defaultRestSec: Int = 90, isCustom: Bool = true, isArchived: Bool = false,
                    createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.name = name
            self.typeRaw = type.rawValue
            self.muscleGroupRaw = muscleGroup.rawValue
            self.isLowerBody = isLowerBody
            self.equipmentRaw = equipment.rawValue
            self.defaultRestSec = defaultRestSec
            self.isCustom = isCustom
            self.isArchived = isArchived
        }
    }

    @Model
    public final class RoutineTemplate {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var name: String
        /// `Calendar` weekdays this routine is planned for.
        public var weekdays: [Int]
        public var sortOrder: Int
        @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template)
        public var items: [TemplateItem] = []

        public init(id: UUID = UUID(), name: String, weekdays: [Int] = [], sortOrder: Int = 0, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.name = name
            self.weekdays = weekdays
            self.sortOrder = sortOrder
        }
    }

    @Model
    public final class TemplateItem {
        public var id: UUID
        public var template: RoutineTemplate?
        public var exercise: Exercise?
        public var order: Int
        public var targetSets: Int
        public var repMin: Int
        public var repMax: Int
        public var restSec: Int

        public init(id: UUID = UUID(), exercise: Exercise, order: Int, targetSets: Int = 3, repMin: Int = 8, repMax: Int = 12,
                    restSec: Int? = nil) {
            self.id = id
            self.exercise = exercise
            self.order = order
            self.targetSets = targetSets
            self.repMin = repMin
            self.repMax = repMax
            self.restSec = restSec ?? exercise.defaultRestSec
        }
    }

    @Model
    public final class WorkoutSession {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var startedAt: Date
        /// nil while the session is running.
        public var endedAt: Date?
        @Relationship(deleteRule: .nullify)
        public var template: RoutineTemplate?
        public var note: String
        public var sourceRaw: String
        public var healthKitUUID: UUID?
        public var activityTypeRaw: String
        public var energyKcal: Double?
        public var distanceM: Double?
        public var avgHeartRate: Double?
        @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
        public var sets: [WorkoutSet] = []

        public init(id: UUID = UUID(), startedAt: Date = .now, template: RoutineTemplate? = nil, note: String = "",
                    source: WorkoutSource = .orbit, activityType: String = "strength") {
            self.id = id
            self.createdAt = startedAt
            self.updatedAt = startedAt
            self.startedAt = startedAt
            self.template = template
            self.note = note
            self.sourceRaw = source.rawValue
            self.activityTypeRaw = activityType
        }
    }

    @Model
    public final class WorkoutSet {
        public var id: UUID
        public var session: WorkoutSession?
        public var exercise: Exercise?
        /// Position of the exercise within the session.
        public var exerciseOrder: Int
        /// Position of the set within its exercise.
        public var setIndex: Int
        public var reps: Int?
        public var weightKg: Double?
        public var durationSec: Int?
        public var distanceM: Double?
        public var energyKcal: Double?
        public var isWarmup: Bool
        public var isCompleted: Bool
        public var completedAt: Date?

        public init(id: UUID = UUID(), exercise: Exercise, exerciseOrder: Int, setIndex: Int, reps: Int? = nil,
                    weightKg: Double? = nil, durationSec: Int? = nil, distanceM: Double? = nil, energyKcal: Double? = nil,
                    isWarmup: Bool = false, isCompleted: Bool = false, completedAt: Date? = nil) {
            self.id = id
            self.exercise = exercise
            self.exerciseOrder = exerciseOrder
            self.setIndex = setIndex
            self.reps = reps
            self.weightKg = weightKg
            self.durationSec = durationSec
            self.distanceM = distanceM
            self.energyKcal = energyKcal
            self.isWarmup = isWarmup
            self.isCompleted = isCompleted
            self.completedAt = completedAt
        }
    }
}

public typealias Exercise = OrbitSchemaV2.Exercise
public typealias RoutineTemplate = OrbitSchemaV2.RoutineTemplate
public typealias TemplateItem = OrbitSchemaV2.TemplateItem
public typealias WorkoutSession = OrbitSchemaV2.WorkoutSession
public typealias WorkoutSet = OrbitSchemaV2.WorkoutSet

public enum Equipment: String, CaseIterable, Codable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, other
}

public enum WorkoutSource: String, Codable, Sendable {
    case orbit, health
}

public extension Exercise {
    var type: ExerciseKind { ExerciseKind(rawValue: typeRaw) ?? .weightReps }
    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .other }
}

public extension RoutineTemplate {
    var orderedItems: [TemplateItem] { items.sorted { $0.order < $1.order } }
}

public extension WorkoutSession {
    var source: WorkoutSource { WorkoutSource(rawValue: sourceRaw) ?? .orbit }
    var isActive: Bool { endedAt == nil }
}

public extension WorkoutSet {
    var record: SetRecord {
        SetRecord(reps: reps, weightKg: weightKg, durationSec: durationSec, distanceM: distanceM,
                  isWarmup: isWarmup, isCompleted: isCompleted)
    }
}
