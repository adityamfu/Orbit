import Foundation
import SwiftData
import OrbitEngine

/// One exercise inside a session, with its sets in order.
public struct SessionExercise: Identifiable {
    public var id: Int { order }
    public let order: Int
    public let exercise: Exercise
    public let sets: [WorkoutSet]
    /// The routine item it came from (rep range, rest), if any.
    public let item: TemplateItem?

    public var restSec: Int { item?.restSec ?? exercise.defaultRestSec }
    public var repRange: ClosedRange<Int> {
        let lo = item?.repMin ?? 8, hi = max(item?.repMax ?? 12, lo)
        return lo...hi
    }
}

/// Personal records beaten in a finished session, per exercise.
public struct SessionRecord: Identifiable {
    public var id: UUID { exercise.id }
    public let exercise: Exercise
    public let kinds: [RecordKind]
    public let best: PersonalRecords
}

/// WRK-05 / 08 / 09: running a session. Sets are created up front with the suggested weight and
/// target reps as placeholders; the user ticks them off. Unticked sets are dropped on finish.
public enum SessionRepository {
    public static func activeSession(in context: ModelContext) -> WorkoutSession? {
        try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt == nil },
                                                           sortBy: [SortDescriptor(\.startedAt, order: .reverse)])).first
    }

    @discardableResult
    public static func start(template: RoutineTemplate?, history: [WorkoutSession], increment: Double,
                             in context: ModelContext, now: Date = .now) -> WorkoutSession {
        let session = WorkoutSession(startedAt: now, template: template)
        context.insert(session)
        for (order, item) in (template?.orderedItems ?? []).enumerated() {
            guard let exercise = item.exercise else { continue }
            prefill(exercise, order: order, sets: item.targetSets, item: item, session: session, history: history,
                    increment: increment, in: context)
        }
        save(context)
        return session
    }

    public static func addExercise(_ exercise: Exercise, to session: WorkoutSession, history: [WorkoutSession],
                                   increment: Double, in context: ModelContext) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        prefill(exercise, order: order, sets: exercise.type == .cardio ? 1 : 3, item: nil, session: session,
                history: history, increment: increment, in: context)
        save(context)
    }

    /// Copies the last set's values; a warm-up goes first and starts lighter.
    public static func addSet(to session: WorkoutSession, exerciseOrder: Int, warmup: Bool = false, in context: ModelContext) {
        let current = sets(of: session, order: exerciseOrder)
        guard let template = warmup ? current.first(where: { !$0.isWarmup }) ?? current.first : current.last,
              let exercise = template.exercise else { return }
        let set = WorkoutSet(exercise: exercise, exerciseOrder: exerciseOrder, setIndex: 0, reps: template.reps,
                             weightKg: warmup ? template.weightKg.map { ($0 * 0.5 / 2.5).rounded() * 2.5 } : template.weightKg,
                             durationSec: template.durationSec, distanceM: template.distanceM, isWarmup: warmup)
        context.insert(set)
        session.sets.append(set)
        var ordered = current
        if warmup { ordered.insert(set, at: 0) } else { ordered.append(set) }
        renumber(ordered)
        save(context)
    }

    public static func deleteSet(_ set: WorkoutSet, from session: WorkoutSession, in context: ModelContext) {
        let order = set.exerciseOrder
        session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        context.delete(set)
        renumber(sets(of: session, order: order))
        save(context)
    }

    public static func setCompleted(_ set: WorkoutSet, _ done: Bool, in context: ModelContext, now: Date = .now) {
        set.isCompleted = done
        set.completedAt = done ? now : nil
        save(context)
    }

    public static func removeExercise(order: Int, from session: WorkoutSession, in context: ModelContext) {
        for set in sets(of: session, order: order) {
            session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
            context.delete(set)
        }
        compactOrders(session)
        save(context)
    }

    /// Moves an exercise one place up (-1) or down (+1).
    public static func moveExercise(order: Int, by delta: Int, in session: WorkoutSession, in context: ModelContext) {
        let orders = Set(session.sets.map(\.exerciseOrder)).sorted()
        guard let index = orders.firstIndex(of: order), orders.indices.contains(index + delta) else { return }
        let other = orders[index + delta]
        for set in session.sets {
            if set.exerciseOrder == order { set.exerciseOrder = other } else if set.exerciseOrder == other { set.exerciseOrder = order }
        }
        save(context)
    }

    /// Ends the session: drops unticked sets, stamps the end, and reports new records.
    /// A session with nothing ticked is discarded instead.
    @discardableResult
    public static func finish(_ session: WorkoutSession, history: [WorkoutSession], in context: ModelContext,
                              now: Date = .now) -> [SessionRecord] {
        for set in session.sets where !set.isCompleted {
            session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
            context.delete(set)
        }
        guard !session.sets.isEmpty else {
            discard(session, in: context)
            return []
        }
        compactOrders(session)
        session.endedAt = now
        session.updatedAt = now
        save(context)
        return records(for: session, history: history)
    }

    public static func discard(_ session: WorkoutSession, in context: ModelContext) {
        context.delete(session)
        save(context)
    }

    // MARK: Reading

    public static func exercises(in session: WorkoutSession) -> [SessionExercise] {
        let items = session.template?.orderedItems ?? []
        return Dictionary(grouping: session.sets.filter { $0.exercise != nil }, by: \.exerciseOrder)
            .sorted { $0.key < $1.key }
            .map { order, sets in
                let exercise = sets[0].exercise!
                return SessionExercise(order: order, exercise: exercise, sets: sets.sorted { $0.setIndex < $1.setIndex },
                                       item: items.first { $0.exercise?.id == exercise.id })
            }
    }

    /// The same exercise's sets from the most recent earlier finished session ("Sebelumnya").
    public static func previousSets(for exercise: Exercise, before session: WorkoutSession,
                                    history: [WorkoutSession]) -> [SetRecord] {
        let earlier = history.filter { $0.id != session.id && $0.startedAt < session.startedAt }
        return WorkoutHistory.setsPerSession(exerciseID: exercise.id, in: earlier, limit: 1).first ?? []
    }

    public static func records(for session: WorkoutSession, history: [WorkoutSession]) -> [SessionRecord] {
        let earlier = WorkoutHistory.finished(history).filter { $0.id != session.id && $0.startedAt < session.startedAt }
        return exercises(in: session).compactMap { entry in
            let previous = Strength.records(earlier.flatMap { $0.sets.filter { $0.exercise?.id == entry.exercise.id }.map(\.record) })
            let now = entry.sets.map(\.record)
            let kinds = Strength.newRecords(now, previous: previous)
            return kinds.isEmpty ? nil : SessionRecord(exercise: entry.exercise, kinds: kinds, best: Strength.records(now))
        }
    }

    // MARK: Private

    private static func prefill(_ exercise: Exercise, order: Int, sets count: Int, item: TemplateItem?,
                                session: WorkoutSession, history: [WorkoutSession], increment: Double,
                                in context: ModelContext) {
        let previous = WorkoutHistory.setsPerSession(exerciseID: exercise.id, in: history, limit: 1).first?
            .filter { !$0.isWarmup } ?? []
        let repMax = item?.repMax ?? 12
        let suggestion = exercise.type == .weightReps
            ? Progression.suggest(sessions: WorkoutHistory.setsPerSession(exerciseID: exercise.id, in: history),
                                  repMin: item?.repMin ?? 8, repMax: repMax, increment: increment,
                                  isLowerBody: exercise.isLowerBody)
            : nil
        for index in 0..<max(count, 1) {
            let last = previous.indices.contains(index) ? previous[index] : previous.last
            let set = WorkoutSet(exercise: exercise, exerciseOrder: order, setIndex: index)
            switch exercise.type {
            case .weightReps:
                set.weightKg = suggestion?.weightKg ?? last?.weightKg
                set.reps = repMax
            case .bodyweight:
                set.reps = last?.reps ?? repMax
            case .duration:
                set.durationSec = last?.durationSec ?? repMax
            case .cardio:
                set.durationSec = last?.durationSec
                set.distanceM = last?.distanceM
            }
            context.insert(set)
            session.sets.append(set)
        }
    }

    private static func sets(of session: WorkoutSession, order: Int) -> [WorkoutSet] {
        session.sets.filter { $0.exerciseOrder == order }.sorted { $0.setIndex < $1.setIndex }
    }

    private static func renumber(_ sets: [WorkoutSet]) {
        for (index, set) in sets.enumerated() where set.setIndex != index { set.setIndex = index }
    }

    /// Exercise orders back to 0, 1, 2… after removals.
    private static func compactOrders(_ session: WorkoutSession) {
        let orders = Set(session.sets.map(\.exerciseOrder)).sorted()
        for set in session.sets { set.exerciseOrder = orders.firstIndex(of: set.exerciseOrder) ?? set.exerciseOrder }
    }

    private static func save(_ context: ModelContext) {
        WorkoutRepository.save(context)
    }
}
