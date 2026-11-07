import Foundation

public enum ExerciseKind: String, CaseIterable, Codable, Sendable {
    /// Weight × reps (bench press).
    case weightReps
    /// Reps only (push-up).
    case bodyweight
    /// Time only (plank).
    case duration
    /// Time + distance + optional kcal (run).
    case cardio
}

public enum MuscleGroup: String, CaseIterable, Codable, Sendable {
    case chest, back, legs, shoulders, arms, core, cardio
}

/// One logged set, engine-side.
public struct SetRecord: Sendable, Equatable {
    public var reps: Int?
    public var weightKg: Double?
    public var durationSec: Int?
    public var distanceM: Double?
    public var isWarmup: Bool
    public var isCompleted: Bool

    public init(reps: Int? = nil, weightKg: Double? = nil, durationSec: Int? = nil, distanceM: Double? = nil,
                isWarmup: Bool = false, isCompleted: Bool = true) {
        self.reps = reps
        self.weightKg = weightKg
        self.durationSec = durationSec
        self.distanceM = distanceM
        self.isWarmup = isWarmup
        self.isCompleted = isCompleted
    }

    /// Completed, non-warm-up sets are the ones that count for volume, PRs and progression.
    public var isWorking: Bool { isCompleted && !isWarmup }
}

// MARK: - Strength maths (WRK-09, WRK-10)

public struct PersonalRecords: Sendable, Equatable {
    public var heaviestKg: Double
    public var bestE1RM: Double
    /// Best single set weight × reps.
    public var bestSetVolume: Double

    public static let none = PersonalRecords(heaviestKg: 0, bestE1RM: 0, bestSetVolume: 0)

    public init(heaviestKg: Double, bestE1RM: Double, bestSetVolume: Double) {
        self.heaviestKg = heaviestKg
        self.bestE1RM = bestE1RM
        self.bestSetVolume = bestSetVolume
    }
}

public enum RecordKind: String, CaseIterable, Sendable {
    case heaviest, e1RM, setVolume
}

public enum Strength {
    /// Epley: w × (1 + reps / 30); a single rep is the weight itself.
    public static func e1RM(weightKg: Double, reps: Int) -> Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// Σ weight × reps over working sets.
    public static func volume(_ sets: [SetRecord]) -> Double {
        sets.filter(\.isWorking).reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
    }

    public static func records(_ sets: [SetRecord]) -> PersonalRecords {
        sets.filter(\.isWorking).reduce(.none) { best, set in
            let w = set.weightKg ?? 0, r = set.reps ?? 0
            return PersonalRecords(
                heaviestKg: max(best.heaviestKg, r > 0 ? w : 0),
                bestE1RM: max(best.bestE1RM, e1RM(weightKg: w, reps: r)),
                bestSetVolume: max(best.bestSetVolume, w * Double(r))
            )
        }
    }

    /// Which records this exercise's sets beat. A first-ever session sets no "new" records
    /// (there was nothing to beat), so PR badges only appear from the second session on.
    public static func newRecords(_ sets: [SetRecord], previous: PersonalRecords) -> [RecordKind] {
        guard previous != .none else { return [] }
        let now = records(sets)
        var result: [RecordKind] = []
        if now.heaviestKg > previous.heaviestKg { result.append(.heaviest) }
        if now.bestE1RM > previous.bestE1RM + 0.01 { result.append(.e1RM) }
        if now.bestSetVolume > previous.bestSetVolume { result.append(.setVolume) }
        return result
    }
}

public struct SessionSummary: Sendable, Equatable {
    public var durationSec: Int
    public var volumeKg: Double
    public var completedSets: Int

    public init(start: Date, end: Date, sets: [SetRecord]) {
        durationSec = max(0, Int(end.timeIntervalSince(start)))
        volumeKg = Strength.volume(sets)
        completedSets = sets.count { $0.isWorking }
    }
}

// MARK: - Double progression (KPI-04, PRD §4.5)

public struct ProgressionSuggestion: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// No history yet: use the template (PRD "Kalibrasi").
        case calibration
        /// Every working set reached the top of the rep range last time.
        case increase(byKg: Double, reps: Int)
        /// Not all sets reached the top yet: same weight, aim for more reps.
        case hold
        /// Below the bottom of the range two sessions in a row.
        case decrease(percent: Int)
    }

    public var weightKg: Double?
    public var reason: Reason

    public init(weightKg: Double?, reason: Reason) {
        self.weightKg = weightKg
        self.reason = reason
    }
}

public enum Progression {
    /// - Parameters:
    ///   - sessions: this exercise's sets per past session, most recent first.
    ///   - increment: minimum weight step (setting, default 2.5 kg). Lower body moves by 2×.
    public static func suggest(sessions: [[SetRecord]], repMin: Int, repMax: Int, increment: Double,
                               isLowerBody: Bool) -> ProgressionSuggestion {
        let history = sessions.map { $0.filter { $0.isWorking && ($0.weightKg ?? 0) > 0 && $0.reps != nil } }
            .filter { !$0.isEmpty }
        guard let last = history.first, let lastWeight = last.compactMap(\.weightKg).max() else {
            return ProgressionSuggestion(weightKg: nil, reason: .calibration)
        }
        let belowMin: ([SetRecord]) -> Bool = { sets in sets.contains { ($0.reps ?? 0) < repMin } }

        if history.count >= 2, belowMin(last), belowMin(history[1]) {
            let lowered = round(lastWeight * 0.9, to: increment)
            return ProgressionSuggestion(weightKg: lowered, reason: .decrease(percent: 10))
        }
        if last.allSatisfy({ ($0.reps ?? 0) >= repMax }) {
            let step = increment * (isLowerBody ? 2 : 1)
            return ProgressionSuggestion(weightKg: lastWeight + step, reason: .increase(byKg: step, reps: repMax))
        }
        return ProgressionSuggestion(weightKg: lastWeight, reason: .hold)
    }

    /// Nearest multiple of `step`; an exact tie rounds down, so a deload never ends up lighter than intended.
    static func round(_ value: Double, to step: Double) -> Double {
        guard step > 0 else { return value }
        return ((value / step) - 0.5).rounded(.up) * step
    }
}
