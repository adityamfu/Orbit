import Foundation
import SwiftData
import OrbitEngine

/// Routine and exercise writes. Each one saves right away (widgets read the store from another process).
public enum WorkoutRepository {
    @discardableResult
    public static func createRoutine(name: String, sortOrder: Int, in context: ModelContext) -> RoutineTemplate {
        let routine = RoutineTemplate(name: name, sortOrder: sortOrder)
        context.insert(routine)
        save(context)
        return routine
    }

    public static func deleteRoutine(_ routine: RoutineTemplate, in context: ModelContext) {
        context.delete(routine)  // items cascade; past sessions keep their sets, the link is nullified
        save(context)
    }

    @discardableResult
    public static func addItem(_ exercise: Exercise, to routine: RoutineTemplate, in context: ModelContext) -> TemplateItem {
        let defaults = exercise.type == .duration ? (30, 60) : (8, 12)
        let item = TemplateItem(exercise: exercise, order: (routine.items.map(\.order).max() ?? -1) + 1,
                                targetSets: exercise.type == .cardio ? 1 : 3, repMin: defaults.0, repMax: defaults.1)
        context.insert(item)
        routine.items.append(item)
        routine.updatedAt = .now
        save(context)
        return item
    }

    public static func removeItems(at offsets: IndexSet, from routine: RoutineTemplate, in context: ModelContext) {
        let ordered = routine.orderedItems
        for index in offsets {
            let item = ordered[index]
            routine.items.removeAll { $0.persistentModelID == item.persistentModelID }
            context.delete(item)
        }
        renumber(routine.orderedItems)
        routine.updatedAt = .now
        save(context)
    }

    public static func moveItems(in routine: RoutineTemplate, fromOffsets source: IndexSet, toOffset destination: Int,
                                 in context: ModelContext) {
        let items = routine.orderedItems
        let moving = source.map { items[$0] }
        var ordered = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        ordered.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        renumber(ordered)
        routine.updatedAt = .now
        save(context)
    }

    @discardableResult
    public static func createExercise(name: String, type: ExerciseKind, muscleGroup: MuscleGroup, isLowerBody: Bool,
                                      restSec: Int, in context: ModelContext) -> Exercise {
        let exercise = Exercise(name: name, type: type, muscleGroup: muscleGroup, isLowerBody: isLowerBody,
                                equipment: .other, defaultRestSec: restSec, isCustom: true)
        context.insert(exercise)
        save(context)
        return exercise
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Saving workouts failed: \(error)")
        }
        WidgetKinds.reload(WidgetKinds.workout)
    }

    private static func renumber(_ items: [TemplateItem]) {
        for (index, item) in items.enumerated() where item.order != index {
            item.order = index
        }
    }
}

/// Read-side helpers over finished sessions (most recent first).
public enum WorkoutHistory {
    /// The routine planned for `date`'s weekday, if any (first by sort order).
    public static func routine(for date: Date, in routines: [RoutineTemplate], calendar: Calendar = .current) -> RoutineTemplate? {
        let weekday = calendar.component(.weekday, from: date)
        return routines.sorted { $0.sortOrder < $1.sortOrder }.first { $0.weekdays.contains(weekday) }
    }

    /// This exercise's working history: one array of sets per past session, newest first.
    public static func setsPerSession(exerciseID: UUID, in sessions: [WorkoutSession], limit: Int = 3) -> [[SetRecord]] {
        Array(finished(sessions).lazy
            .map { $0.sets.filter { $0.exercise?.id == exerciseID }.sorted { $0.setIndex < $1.setIndex }.map(\.record) }
            .filter { !$0.isEmpty }
            .prefix(limit))
    }

    /// Engine suggestion for one routine item, from history.
    public static func suggestion(for item: TemplateItem, sessions: [WorkoutSession], increment: Double) -> ProgressionSuggestion? {
        guard let exercise = item.exercise, exercise.type == .weightReps else { return nil }
        return Progression.suggest(sessions: setsPerSession(exerciseID: exercise.id, in: sessions),
                                   repMin: item.repMin, repMax: item.repMax, increment: increment,
                                   isLowerBody: exercise.isLowerBody)
    }

    /// Whether `session` beat an earlier best on any exercise (badge "PR" in history).
    public static func hasRecord(_ session: WorkoutSession, among sessions: [WorkoutSession]) -> Bool {
        let earlier = finished(sessions).filter { $0.startedAt < session.startedAt }
        let byExercise = Dictionary(grouping: session.sets.filter { $0.exercise != nil }) { $0.exercise!.id }
        return byExercise.contains { id, sets in
            let previous = Strength.records(earlier.flatMap { $0.sets.filter { $0.exercise?.id == id }.map(\.record) })
            return !Strength.newRecords(sets.map(\.record), previous: previous).isEmpty
        }
    }

    public static func finished(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    /// WRK-11: one point per session that has this exercise, oldest first.
    public static func progress(exerciseID: UUID, in sessions: [WorkoutSession]) -> [ExercisePoint] {
        finished(sessions).reversed().compactMap { session in
            let sets = session.sets.filter { $0.exercise?.id == exerciseID }.map(\.record).filter(\.isWorking)
            let weighted = sets.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
            guard let top = weighted.max(by: { ($0.weightKg!, $0.reps!) < ($1.weightKg!, $1.reps!) }) else { return nil }
            return ExercisePoint(date: session.startedAt, topWeightKg: top.weightKg!, topReps: top.reps!,
                                 e1RM: Strength.records(weighted).bestE1RM, volumeKg: Strength.volume(weighted))
        }
    }

    /// WRK-11: working-set volume per muscle group per week, for the last `weeks` weeks (oldest first).
    /// Weeks with no volume still appear (as 0) so the chart keeps its timeline.
    public static func weeklyVolume(_ sessions: [WorkoutSession], weeks: Int, firstWeekday: Int, now: Date = .now,
                                    calendar: Calendar = .current) -> [MuscleVolume] {
        var cal = calendar
        cal.firstWeekday = firstWeekday
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<weeks).reversed().compactMap { cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        var totals: [Date: [MuscleGroup: Double]] = [:]
        for session in finished(sessions) {
            guard let week = cal.dateInterval(of: .weekOfYear, for: session.startedAt)?.start, starts.contains(week) else { continue }
            for set in session.sets where set.isCompleted && !set.isWarmup {
                guard let muscle = set.exercise?.muscleGroup else { continue }
                totals[week, default: [:]][muscle, default: 0] += (set.weightKg ?? 0) * Double(set.reps ?? 0)
            }
        }
        return starts.flatMap { week in
            MuscleGroup.allCases.map { MuscleVolume(weekStart: week, muscle: $0, kg: totals[week]?[$0] ?? 0) }
        }
    }
}

public struct ExercisePoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let topWeightKg: Double
    public let topReps: Int
    public let e1RM: Double
    public let volumeKg: Double
}

public struct MuscleVolume: Identifiable, Equatable, Sendable {
    public var id: String { "\(weekStart.timeIntervalSince1970)-\(muscle.rawValue)" }
    public let weekStart: Date
    public let muscle: MuscleGroup
    public let kg: Double
}

/// WID-03 / WID-04: today's routine, or the running session.
public struct WorkoutWidgetSnapshot: Sendable {
    public var routineName: String?
    public var exercises: [String]
    /// Set while a session runs.
    public var activeName: String?
    public var activeSince: Date?

    public static func load(date: Date = .now) -> WorkoutWidgetSnapshot {
        guard let container = try? OrbitData.makeContainer() else { return .init(exercises: []) }
        let context = ModelContext(container)
        let routines = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        let routine = WorkoutHistory.routine(for: date, in: routines)
        let active = SessionRepository.activeSession(in: context)
        return .init(routineName: routine?.name,
                     exercises: routine?.orderedItems.compactMap { $0.exercise?.displayName() } ?? [],
                     activeName: active.map { $0.template?.name ?? L10n.string("workout.emptySession") },
                     activeSince: active?.startedAt)
    }

    public static let sample = WorkoutWidgetSnapshot(
        routineName: "Push Day",
        exercises: ["Bench Press", "Overhead Press", "Incline DB Press", "Lateral Raise", "Tricep Pushdown"])
}
