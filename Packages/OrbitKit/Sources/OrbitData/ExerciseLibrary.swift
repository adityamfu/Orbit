import Foundation
import SwiftData
import OrbitEngine

/// Built-in exercises (WRK-01). Names are catalog keys so they follow the app language.
public enum ExerciseLibrary {
    struct Entry {
        let key: String
        let type: ExerciseKind
        let muscle: MuscleGroup
        let lower: Bool
        let equipment: Equipment
        let rest: Int
    }

    static let entries: [Entry] = [
        // Chest
        .init(key: "exercise.benchPress", type: .weightReps, muscle: .chest, lower: false, equipment: .barbell, rest: 120),
        .init(key: "exercise.inclineBenchPress", type: .weightReps, muscle: .chest, lower: false, equipment: .barbell, rest: 120),
        .init(key: "exercise.dumbbellBenchPress", type: .weightReps, muscle: .chest, lower: false, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.inclineDumbbellPress", type: .weightReps, muscle: .chest, lower: false, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.chestFly", type: .weightReps, muscle: .chest, lower: false, equipment: .machine, rest: 60),
        .init(key: "exercise.cableCrossover", type: .weightReps, muscle: .chest, lower: false, equipment: .cable, rest: 60),
        .init(key: "exercise.pushUp", type: .bodyweight, muscle: .chest, lower: false, equipment: .bodyweight, rest: 60),
        .init(key: "exercise.dips", type: .bodyweight, muscle: .chest, lower: false, equipment: .bodyweight, rest: 90),
        // Back
        .init(key: "exercise.deadlift", type: .weightReps, muscle: .back, lower: true, equipment: .barbell, rest: 180),
        .init(key: "exercise.pullUp", type: .bodyweight, muscle: .back, lower: false, equipment: .bodyweight, rest: 120),
        .init(key: "exercise.chinUp", type: .bodyweight, muscle: .back, lower: false, equipment: .bodyweight, rest: 120),
        .init(key: "exercise.latPulldown", type: .weightReps, muscle: .back, lower: false, equipment: .cable, rest: 90),
        .init(key: "exercise.barbellRow", type: .weightReps, muscle: .back, lower: false, equipment: .barbell, rest: 120),
        .init(key: "exercise.dumbbellRow", type: .weightReps, muscle: .back, lower: false, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.seatedCableRow", type: .weightReps, muscle: .back, lower: false, equipment: .cable, rest: 90),
        .init(key: "exercise.facePull", type: .weightReps, muscle: .back, lower: false, equipment: .cable, rest: 60),
        // Legs
        .init(key: "exercise.backSquat", type: .weightReps, muscle: .legs, lower: true, equipment: .barbell, rest: 180),
        .init(key: "exercise.frontSquat", type: .weightReps, muscle: .legs, lower: true, equipment: .barbell, rest: 180),
        .init(key: "exercise.legPress", type: .weightReps, muscle: .legs, lower: true, equipment: .machine, rest: 120),
        .init(key: "exercise.romanianDeadlift", type: .weightReps, muscle: .legs, lower: true, equipment: .barbell, rest: 120),
        .init(key: "exercise.lunge", type: .weightReps, muscle: .legs, lower: true, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.bulgarianSplitSquat", type: .weightReps, muscle: .legs, lower: true, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.legExtension", type: .weightReps, muscle: .legs, lower: true, equipment: .machine, rest: 60),
        .init(key: "exercise.legCurl", type: .weightReps, muscle: .legs, lower: true, equipment: .machine, rest: 60),
        .init(key: "exercise.calfRaise", type: .weightReps, muscle: .legs, lower: true, equipment: .machine, rest: 60),
        .init(key: "exercise.hipThrust", type: .weightReps, muscle: .legs, lower: true, equipment: .barbell, rest: 90),
        // Shoulders
        .init(key: "exercise.overheadPress", type: .weightReps, muscle: .shoulders, lower: false, equipment: .barbell, rest: 120),
        .init(key: "exercise.dumbbellShoulderPress", type: .weightReps, muscle: .shoulders, lower: false, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.arnoldPress", type: .weightReps, muscle: .shoulders, lower: false, equipment: .dumbbell, rest: 90),
        .init(key: "exercise.lateralRaise", type: .weightReps, muscle: .shoulders, lower: false, equipment: .dumbbell, rest: 60),
        .init(key: "exercise.rearDeltFly", type: .weightReps, muscle: .shoulders, lower: false, equipment: .dumbbell, rest: 60),
        .init(key: "exercise.uprightRow", type: .weightReps, muscle: .shoulders, lower: false, equipment: .barbell, rest: 60),
        // Arms
        .init(key: "exercise.barbellCurl", type: .weightReps, muscle: .arms, lower: false, equipment: .barbell, rest: 60),
        .init(key: "exercise.dumbbellCurl", type: .weightReps, muscle: .arms, lower: false, equipment: .dumbbell, rest: 60),
        .init(key: "exercise.hammerCurl", type: .weightReps, muscle: .arms, lower: false, equipment: .dumbbell, rest: 60),
        .init(key: "exercise.preacherCurl", type: .weightReps, muscle: .arms, lower: false, equipment: .machine, rest: 60),
        .init(key: "exercise.tricepPushdown", type: .weightReps, muscle: .arms, lower: false, equipment: .cable, rest: 60),
        .init(key: "exercise.skullCrusher", type: .weightReps, muscle: .arms, lower: false, equipment: .barbell, rest: 60),
        .init(key: "exercise.overheadTricepExtension", type: .weightReps, muscle: .arms, lower: false, equipment: .dumbbell, rest: 60),
        // Core
        .init(key: "exercise.plank", type: .duration, muscle: .core, lower: false, equipment: .bodyweight, rest: 60),
        .init(key: "exercise.sidePlank", type: .duration, muscle: .core, lower: false, equipment: .bodyweight, rest: 60),
        .init(key: "exercise.hangingLegRaise", type: .bodyweight, muscle: .core, lower: false, equipment: .bodyweight, rest: 60),
        .init(key: "exercise.cableCrunch", type: .weightReps, muscle: .core, lower: false, equipment: .cable, rest: 60),
        .init(key: "exercise.russianTwist", type: .bodyweight, muscle: .core, lower: false, equipment: .bodyweight, rest: 60),
        .init(key: "exercise.abWheel", type: .bodyweight, muscle: .core, lower: false, equipment: .other, rest: 60),
        // Cardio
        .init(key: "exercise.running", type: .cardio, muscle: .cardio, lower: false, equipment: .other, rest: 0),
        .init(key: "exercise.cycling", type: .cardio, muscle: .cardio, lower: false, equipment: .other, rest: 0),
        .init(key: "exercise.walking", type: .cardio, muscle: .cardio, lower: false, equipment: .other, rest: 0),
        .init(key: "exercise.swimming", type: .cardio, muscle: .cardio, lower: false, equipment: .other, rest: 0),
        .init(key: "exercise.rowing", type: .cardio, muscle: .cardio, lower: false, equipment: .machine, rest: 0),
        .init(key: "exercise.elliptical", type: .cardio, muscle: .cardio, lower: false, equipment: .machine, rest: 0),
        .init(key: "exercise.jumpRope", type: .cardio, muscle: .cardio, lower: false, equipment: .other, rest: 0),
    ]

    /// Adds any built-in exercise that isn't in the store yet. Safe to call on every launch.
    @discardableResult
    public static func seedIfNeeded(_ context: ModelContext) throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })).map(\.name))
        let missing = entries.filter { !existing.contains($0.key) }
        for e in missing {
            context.insert(Exercise(name: e.key, type: e.type, muscleGroup: e.muscle, isLowerBody: e.lower,
                                    equipment: e.equipment, defaultRestSec: e.rest, isCustom: false))
        }
        if !missing.isEmpty { try context.save() }
        return missing.count
    }
}

/// Ready-made routines (WRK-04). Installing one creates editable `RoutineTemplate`s.
public enum ProgramPreset: String, CaseIterable, Sendable {
    case pushPullLegs, upperLower, fullBody

    struct Routine {
        let nameKey: String
        let weekdays: [Int]
        /// (exercise key, sets, rep min, rep max)
        let items: [(String, Int, Int, Int)]
    }

    var routines: [Routine] {
        switch self {
        case .pushPullLegs: [
            Routine(nameKey: "routine.push", weekdays: [2, 5], items: [
                ("exercise.benchPress", 4, 8, 12), ("exercise.overheadPress", 3, 8, 10),
                ("exercise.inclineDumbbellPress", 3, 10, 12), ("exercise.lateralRaise", 3, 12, 15),
                ("exercise.tricepPushdown", 3, 10, 12),
            ]),
            Routine(nameKey: "routine.pull", weekdays: [3, 6], items: [
                ("exercise.pullUp", 3, 6, 10), ("exercise.barbellRow", 4, 8, 12), ("exercise.latPulldown", 3, 10, 12),
                ("exercise.facePull", 3, 12, 15), ("exercise.barbellCurl", 3, 8, 12),
            ]),
            Routine(nameKey: "routine.legs", weekdays: [4, 7], items: [
                ("exercise.backSquat", 4, 6, 10), ("exercise.romanianDeadlift", 3, 8, 10), ("exercise.legPress", 3, 10, 12),
                ("exercise.legCurl", 3, 10, 12), ("exercise.calfRaise", 4, 12, 15), ("exercise.hangingLegRaise", 3, 10, 15),
            ]),
        ]
        case .upperLower: [
            Routine(nameKey: "routine.upper", weekdays: [2, 5], items: [
                ("exercise.benchPress", 4, 6, 10), ("exercise.barbellRow", 4, 6, 10), ("exercise.overheadPress", 3, 8, 10),
                ("exercise.latPulldown", 3, 10, 12), ("exercise.dumbbellCurl", 3, 10, 12), ("exercise.tricepPushdown", 3, 10, 12),
            ]),
            Routine(nameKey: "routine.lower", weekdays: [3, 6], items: [
                ("exercise.backSquat", 4, 6, 10), ("exercise.romanianDeadlift", 3, 8, 10), ("exercise.legPress", 3, 10, 12),
                ("exercise.legCurl", 3, 10, 12), ("exercise.calfRaise", 4, 12, 15), ("exercise.plank", 3, 30, 60),
            ]),
        ]
        case .fullBody: [
            Routine(nameKey: "routine.fullBody", weekdays: [2, 4, 6], items: [
                ("exercise.backSquat", 3, 6, 10), ("exercise.benchPress", 3, 8, 12), ("exercise.barbellRow", 3, 8, 12),
                ("exercise.overheadPress", 3, 8, 10), ("exercise.plank", 3, 30, 60),
            ]),
        ]
        }
    }

    /// Creates this program's routines, named in the given language, after `startOrder`.
    @discardableResult
    public func install(in context: ModelContext, language: AppLanguage, startOrder: Int = 0) throws -> [RoutineTemplate] {
        try ExerciseLibrary.seedIfNeeded(context)
        let library = Dictionary(
            try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom })).map { ($0.name, $0) }
        ) { a, _ in a }
        var created: [RoutineTemplate] = []
        for (index, routine) in routines.enumerated() {
            let template = RoutineTemplate(name: L10n.string(key: routine.nameKey, language: language),
                                           weekdays: routine.weekdays, sortOrder: startOrder + index)
            context.insert(template)
            for (order, (key, sets, repMin, repMax)) in routine.items.enumerated() {
                guard let exercise = library[key] else { continue }
                let item = TemplateItem(exercise: exercise, order: order, targetSets: sets, repMin: repMin, repMax: repMax)
                context.insert(item)
                template.items.append(item)
            }
            created.append(template)
        }
        try context.save()
        return created
    }
}

public extension Exercise {
    /// Built-ins translate their key; custom exercises show what the user typed.
    func displayName(language: AppLanguage? = nil) -> String {
        isCustom ? name : L10n.string(key: name, language: language)
    }
}
