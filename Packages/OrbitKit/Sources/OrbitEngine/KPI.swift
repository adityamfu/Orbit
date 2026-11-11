import Foundation

/// One metric's target vs actual for a week, with the engine's plain-language reason.
public struct KPIMetric: Sendable, Equatable {
    public var target: Double
    public var actual: Double
    public var reason: String

    public var achievementPercent: Int {
        guard target > 0 else { return 0 } // no target set yet
        return Int(min(Double(actual) / Double(target) * 100, 100).rounded())
    }

    public init(target: Double, actual: Double, reason: String) {
        self.target = target
        self.actual = actual
        self.reason = reason
    }
}

/// The week's KPIs: targets, actuals, reasons, and the weekly score (0–100).
public struct WeeklyKPI: Sendable, Equatable {
    public var weekKey: Int // yyyyWW, first weekday per user setting
    public var sessions: KPIMetric
    public var volume: KPIMetric
    public var cardioMinutes: KPIMetric
    public var steps: KPIMetric

    public var score: Int {
        let values = [sessions, volume, cardioMinutes, steps].map { $0.achievementPercent }
        return values.reduce(0, +) / values.count
    }

    public init(weekKey: Int, sessions: KPIMetric, volume: KPIMetric,
                cardioMinutes: KPIMetric, steps: KPIMetric) {
        self.weekKey = weekKey
        self.sessions = sessions
        self.volume = volume
        self.cardioMinutes = cardioMinutes
        self.steps = steps
    }
}

/// One finished session, engine-side view (no SwiftData).
public struct KPISession: Sendable, Equatable {
    public var startedAt: Date
    public var volumeKg: Double
    public var durationSec: Int
    public var cardioMinutes: Double

    public init(startedAt: Date, volumeKg: Double, durationSec: Int, cardioMinutes: Double = 0) {
        self.startedAt = startedAt
        self.volumeKg = volumeKg
        self.durationSec = durationSec
        self.cardioMinutes = cardioMinutes
    }
}

/// Smart weekly KPI engine (PRD §4.5). Deterministic, no external AI.
/// Reason strings are in Indonesian (app default language); views localize at display time.
public enum KPIEngine {
    /// WHO cardio reference, shown as info not a forced target.
    public static let weeklyCardioReference: Double = 150 // minutes per week

    /// Compute next week's targets from finished sessions (PRD §4.5).
    /// - scheduledDays: number of scheduled workout days per week (caps the session target).
    /// - cardioMinutesLastWeek: total cardio minutes last week (from Health, 0 if none).
    /// - avgDailyStepsLastWeek: average daily steps last week (from Health, 0 if none).
    /// - now: "today"; week boundaries are derived from this.
    public static func nextWeek(sessions: [KPISession], firstWeekday: Int = 2,
                                scheduledDays: Int = 3, cardioMinutesLastWeek: Double = 0,
                                avgDailyStepsLastWeek: Int = 0, now: Date = .now) -> WeeklyKPI {
        let cal = weeklyCalendar(firstWeekday: firstWeekday)
        let thisWeek = weekKey(for: now, calendar: cal)
        let lastWeek = weekKey(for: cal.date(byAdding: .day, value: -7, to: now)!, calendar: cal)

        let finished = sessions.filter { $0.startedAt < now }
        // Baseline is computed from finished weeks before this week (this week isn't done yet).
        let beforeThisWeek = finished.filter {
            weekStart(for: $0.startedAt, calendar: cal) != thisWeek
        }

        // --- Sessions ---
        let sessionWeekly = sessionsPerWeek(finished: beforeThisWeek, weeks: 4, calendar: cal)
            .filter { $0.key != thisWeek } // only completed weeks
        let sessionTargets = sessionTarget(weekly: sessionWeekly, scheduledDays: scheduledDays)
        let sessionsActual = sessionCount(finished: finished, weekKey: thisWeek, calendar: cal)
        let sessionsMetric = KPIMetric(target: sessionTargets.target, actual: Double(sessionsActual),
                                       reason: sessionTargets.reason)

        // --- Volume ---
        let volumeWeekly = volumePerWeek(finished: beforeThisWeek, weeks: 3, calendar: cal)
            .filter { $0.key != thisWeek } // only completed weeks
        let volumeTargets = volumeTarget(weekly: volumeWeekly)
        let volumeActual = volumeSum(finished: finished, weekKey: thisWeek, calendar: cal)
        let volumeMetric = KPIMetric(target: volumeTargets.target, actual: volumeActual,
                                     reason: volumeTargets.reason)

        // --- Cardio minutes ---
        let cardioActual = cardioSum(finished: finished, weekKey: thisWeek, calendar: cal)
        let cardioTarget = cardioMinutesLastWeek > 0 ? cardioMinutesLastWeek : weeklyCardioReference
        let cardioMetric = KPIMetric(target: cardioTarget, actual: cardioActual,
                                     reason: cardioReason(actual: cardioActual))

        // --- Steps ---
        let stepsTargetVal = stepsTarget(avgDailySteps: avgDailyStepsLastWeek)
        let stepsActual = Double(stepsCount(lastWeek: lastWeek, avgDailySteps: avgDailyStepsLastWeek))
        let stepsMetric = KPIMetric(target: stepsTargetVal, actual: stepsActual,
                                    reason: stepsReason(actual: stepsActual, target: stepsTargetVal))

        return WeeklyKPI(weekKey: thisWeek, sessions: sessionsMetric, volume: volumeMetric,
                         cardioMinutes: cardioMetric, steps: stepsMetric)
    }

    // MARK: - Sessions

    private static func sessionTarget(weekly: [(key: Int, count: Int)], scheduledDays: Int)
        -> (target: Double, reason: String) {
        guard !weekly.isEmpty, weekly.contains(where: { $0.count > 0 }) else {
            return (0, "Belum cukup data — gunakan target dari template (kalibrasi).")
        }
        let baseline = median(weekly.map { Double($0.count) })

        // weekly is newest-first, containing only completed weeks.
        let lastCount = weekly.first?.count ?? 0
        let prevCount = weekly.dropFirst().first?.count ?? 0

        var target = baseline
        let reason: String
        if baseline > 0, Double(lastCount) >= baseline, Double(prevCount) >= baseline {
            target = min(baseline + 1, Double(scheduledDays))
            reason = "Target naik karena capaian 100% 2 minggu berturut-turut."
        } else if baseline > 0, Double(lastCount) < baseline * 0.5 {
            target = max(baseline - 1, 1)
            reason = "Target turun karena capaian di bawah 50% minggu lalu."
        } else {
            reason = "Target sama dengan minggu lalu."
        }
        return (target, reason)
    }

    private static func sessionsPerWeek(finished: [KPISession], weeks: Int, calendar: Calendar)
        -> [(key: Int, count: Int)] {
        let now = finished.map(\.startedAt).max() ?? Date.now
        // newest first: index 0 = most recent completed week
        let starts = (0..<weeks).compactMap {
            weekStart(for: calendar.date(byAdding: .day, value: -7 * $0, to: now)!, calendar: calendar)
        }
        var counts: [Int: Int] = [:]
        for session in finished {
            guard let key = weekStart(for: session.startedAt, calendar: calendar) else { continue }
            counts[key, default: 0] += 1
        }
        return starts.map { ($0, counts[$0] ?? 0) }
    }

    // MARK: - Volume

    private static func volumeTarget(weekly: [(key: Int, volume: Double)])
        -> (target: Double, reason: String) {
        guard !weekly.isEmpty else {
            return (0, "Belum cukup data — gunakan target dari template (kalibrasi).")
        }
        let baseline = weekly.map { $0.volume }.reduce(0, +) / Double(weekly.count)

        // weekly is newest-first, containing only completed weeks.
        let lastVol = weekly.first?.volume ?? 0
        let ratio = baseline > 0 ? lastVol / baseline : 0

        var target = baseline
        let reason: String
        if ratio >= 0.95 {
            target = min(baseline * 1.05, baseline * 1.1) // cap at +10%
            reason = "Naik 5% karena capaian volume ≥ 95% minggu lalu."
        } else if ratio < 0.7 {
            target = baseline * 0.9
            reason = "Turun 10% karena capaian volume di bawah 70% minggu lalu."
        } else {
            target = baseline
            reason = "Volume tetap pada baseline minggu lalu."
        }
        return (target, reason)
    }

    private static func volumePerWeek(finished: [KPISession], weeks: Int, calendar: Calendar)
        -> [(key: Int, volume: Double)] {
        let now = finished.map(\.startedAt).max() ?? Date.now
        // newest first: index 0 = most recent completed week
        let starts = (0..<weeks).compactMap {
            weekStart(for: calendar.date(byAdding: .day, value: -7 * $0, to: now)!, calendar: calendar)
        }
        var totals: [Int: Double] = [:]
        for session in finished {
            guard let key = weekStart(for: session.startedAt, calendar: calendar) else { continue }
            totals[key, default: 0] += session.volumeKg
        }
        return starts.map { ($0, totals[$0] ?? 0) }
    }

    // MARK: - Steps

    private static func stepsTarget(avgDailySteps: Int) -> Double {
        guard avgDailySteps > 0 else { return 0 }
        return Double(Int((Double(avgDailySteps) * 1.05 / 500).rounded() * 500))
    }

    private static func stepsCount(lastWeek: Int, avgDailySteps: Int) -> Int {
        // Without HealthKit step data we can't know actuals; report 0 until synced.
        return 0
    }

    private static func stepsReason(actual: Double, target: Double) -> String {
        if target == 0 {
            return "Target langkah akan ditetapkan setelah data langkah tersedia (Apple Health)."
        }
        return "Target langkah harian naik 5% dari rata-rata 2 minggu terakhir."
    }

    // MARK: - Cardio

    private static func cardioSum(finished: [KPISession], weekKey: Int, calendar: Calendar) -> Double {
        var total: Double = 0
        for session in finished {
            guard weekStart(for: session.startedAt, calendar: calendar) == weekKey else { continue }
            total += session.cardioMinutes
        }
        return total
    }

    private static func cardioReason(actual: Double) -> String {
        if actual >= weeklyCardioReference {
            return "Terkunci referensi WHO 150 menit cardio per minggu."
        }
        return "Referensi WHO: 150 menit cardio per minggu (info saja, bukan target paksa)."
    }

    // MARK: - Helpers

    private static func sessionCount(finished: [KPISession], weekKey: Int, calendar: Calendar) -> Int {
        finished.filter { weekStart(for: $0.startedAt, calendar: calendar) == weekKey }.count
    }

    private static func volumeSum(finished: [KPISession], weekKey: Int, calendar: Calendar) -> Double {
        finished.filter { weekStart(for: $0.startedAt, calendar: calendar) == weekKey }
            .map(\.volumeKg).reduce(0, +)
    }

    private static func weeklyCalendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = firstWeekday
        return cal
    }

    /// Start of the week containing `date`, as an Int week key (`yyyyWW`-ish, first weekday per setting).
    private static func weekStart(for date: Date, calendar: Calendar) -> Int? {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: interval.start)
        guard let year = c.yearForWeekOfYear, let week = c.weekOfYear else { return nil }
        return year * 100 + week
    }

    private static func weekKey(for date: Date, calendar: Calendar) -> Int {
        weekStart(for: date, calendar: calendar) ?? 0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}
