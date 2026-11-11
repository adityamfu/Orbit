import Foundation
import SwiftData
import OrbitEngine

#if canImport(HealthKit)
import HealthKit
#endif

/// Apple Health bridge (PRD §4.6 HLT-01–05). Offline-first: the app works fully without Health permission.
/// Runs on MainActor like the rest of the app, so no actor hopping / data races.
@MainActor
public final class HealthKitService: Sendable {
    public static let shared = HealthKitService()

#if canImport(HealthKit)
    private let store = HKHealthStore()

    /// Metadata key Orbit stamps on every HKWorkout so we can dedupe imports (PRD HLT-03).
    private static let orbitSourceUUIDKey = "orbit.sourceUUID"

    private init() {}

    /// Whether the device supports HealthKit (always true on iPhone, false on Mac Catalyst tests).
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Current authorization status for writing/reading workout data (HKAuthorizationStatus raw value).
    public var authorizationStatus: Int {
#if canImport(HealthKit)
        store.authorizationStatus(for: HKObjectType.workoutType()).rawValue
#else
        0 // .notDetermined
#endif
    }

    /// Request permission to read/write workouts. Safe to call repeatedly (no-op once decided).
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        ]
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: writeTypes, read: readTypes) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    // MARK: - Write (HLT-02)

    /// Save a finished Orbit session to Apple Health as an HKWorkout (PRD HLT-02).
    /// Fire-and-forget: never blocks the caller. Returns the HealthKit UUID, or nil if not authorized.
    public func save(session: WorkoutSession, context: ModelContext) async -> UUID? {
        guard isAvailable, authorizationStatus == 2 else { return nil } // .sharingAuthorized
        let sourceUUID = UUID()
        let workout = HKWorkout(activityType: activityType(session), start: session.startedAt,
                                end: session.endedAt ?? .now)
        return await withCheckedContinuation { continuation in
            store.save(workout) { _, saveError in
                if saveError != nil {
                    continuation.resume(returning: nil)
                    return
                }
                session.healthKitUUID = sourceUUID
                session.sourceRaw = WorkoutSource.orbit.rawValue
                try? context.save()
                continuation.resume(returning: sourceUUID)
            }
        }
    }

    private func activityType(_ session: WorkoutSession) -> HKWorkoutActivityType {
        // Cardio exercises → match cardio type; everything else → strength training.
        let isCardio = session.sets.contains { set in
            set.exercise?.typeRaw == ExerciseKind.cardio.rawValue
        }
        return isCardio ? .running : .traditionalStrengthTraining
    }

    // MARK: - Read / Import (HLT-01, HLT-03)

    /// Import workouts from Apple Health that Orbit hasn't seen yet (deduped by start date + source).
    /// New workouts are inserted as `source = .health` so they get the "Apple Health" badge in history.
    /// Fire-and-forget: never blocks the caller.
    public func importWorkouts(into context: ModelContext) async -> Int {
        guard isAvailable, authorizationStatus == 2 else { return 0 } // .sharingAuthorized
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date.now,
                                                    options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: 0)
                    return
                }
                let known = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
                var imported = 0
                for workout in workouts {
                    // Dedupe: skip if we already imported this exact workout (same start + source=health).
                    let alreadyImported = known.contains { s in
                        s.sourceRaw == WorkoutSource.health.rawValue
                            && s.startedAt.timeIntervalSince1970 == workout.startDate.timeIntervalSince1970
                    }
                    if alreadyImported { continue }
                    let session = WorkoutSession(startedAt: workout.startDate, source: .health,
                                                 activityType: "strength")
                    session.endedAt = workout.endDate
                    session.healthKitUUID = workout.uuid
                    session.note = "Impor dari Apple Health"
                    context.insert(session)
                    imported += 1
                }
                try? context.save()
                continuation.resume(returning: imported)
            }
            store.execute(query)
        }
    }

    /// Read step count for a date range (HLT-01). Returns total steps, or nil if not authorized.
    public func stepCount(from start: Date, to end: Date) async -> Int? {
        guard isAvailable, authorizationStatus == 2, // .sharingAuthorized
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        return await readQuantity(type: type, unit: .count(), from: start, to: end).map { Int($0) }
    }

    /// Read active energy for a date range (HLT-01). Returns kcal, or nil if not authorized.
    public func activeEnergy(from start: Date, to end: Date) async -> Double? {
        guard isAvailable, authorizationStatus == 2, // .sharingAuthorized
              let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        return await readQuantity(type: type, unit: .kilocalorie(), from: start, to: end)
    }

    private func readQuantity(type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
#else
    // macOS / tests: HealthKit not available, everything is a no-op.
    private init() {}
    public var isAvailable: Bool { false }
    public var authorizationStatus: HKAuthorizationStatus { .notDetermined }
    public func requestAuthorization() async -> Bool { false }
    public func save(session: WorkoutSession, context: ModelContext) -> UUID? { nil }
    public func importWorkouts(into context: ModelContext) -> Int { 0 }
    public func stepCount(from: Date, to: Date) async -> Int? { nil }
    public func activeEnergy(from: Date, to: Date) async -> Double? { nil }
#endif
}
