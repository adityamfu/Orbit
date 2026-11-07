import Foundation
import Testing
@testable import OrbitEngine

struct StrengthTests {
    func set(_ w: Double, _ r: Int, warmup: Bool = false, done: Bool = true) -> SetRecord {
        SetRecord(reps: r, weightKg: w, isWarmup: warmup, isCompleted: done)
    }

    @Test func epley() {
        #expect(Strength.e1RM(weightKg: 100, reps: 1) == 100)
        #expect(abs(Strength.e1RM(weightKg: 60, reps: 12) - 84) < 0.001)
        #expect(Strength.e1RM(weightKg: 60, reps: 0) == 0)
    }

    @Test func volumeIgnoresWarmupsAndUnfinished() {
        let sets = [set(40, 10, warmup: true), set(60, 10), set(60, 8), set(60, 12, done: false)]
        #expect(Strength.volume(sets) == 60 * 10 + 60 * 8)
    }

    @Test func recordsAndNewRecords() {
        let before = Strength.records([set(60, 10), set(60, 8)])
        #expect(before == PersonalRecords(heaviestKg: 60, bestE1RM: 80, bestSetVolume: 600))

        // Same weight, more reps → e1RM and set-volume PR, not heaviest.
        #expect(Strength.newRecords([set(60, 12)], previous: before) == [.e1RM, .setVolume])
        // Heavier, fewer reps.
        #expect(Strength.newRecords([set(70, 3)], previous: before) == [.heaviest])
        // Warm-ups never count.
        #expect(Strength.newRecords([set(100, 5, warmup: true)], previous: before).isEmpty)
        // First session ever: nothing to beat.
        #expect(Strength.newRecords([set(60, 10)], previous: .none).isEmpty)
    }

    @Test func summary() {
        let start = Date(timeIntervalSince1970: 0)
        let s = SessionSummary(start: start, end: start.addingTimeInterval(3_480), sets: [set(50, 10), set(50, 10, warmup: true)])
        #expect(s == SessionSummary(start: start, end: start.addingTimeInterval(3_480), sets: [set(50, 10)]))
        #expect(s.durationSec == 3_480)
        #expect(s.volumeKg == 500)
        #expect(s.completedSets == 1)
    }
}

struct ProgressionTests {
    func session(_ w: Double, _ reps: [Int]) -> [SetRecord] {
        reps.map { SetRecord(reps: $0, weightKg: w) }
    }

    @Test func noHistoryIsCalibration() {
        let s = Progression.suggest(sessions: [], repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        #expect(s == ProgressionSuggestion(weightKg: nil, reason: .calibration))
    }

    @Test func allSetsAtTopIncreaseUpperBody() {
        let s = Progression.suggest(sessions: [session(60, [12, 12, 12])], repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        #expect(s == ProgressionSuggestion(weightKg: 62.5, reason: .increase(byKg: 2.5, reps: 12)))
    }

    @Test func lowerBodyMovesTwoSteps() {
        let s = Progression.suggest(sessions: [session(100, [10, 10, 10])], repMin: 6, repMax: 10, increment: 2.5, isLowerBody: true)
        #expect(s.weightKg == 105)
        #expect(s.reason == .increase(byKg: 5, reps: 10))
    }

    @Test func partialRangeHolds() {
        let s = Progression.suggest(sessions: [session(60, [12, 10, 9])], repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        #expect(s == ProgressionSuggestion(weightKg: 60, reason: .hold))
    }

    @Test func oneBadSessionHolds() {
        let s = Progression.suggest(sessions: [session(60, [8, 7, 6]), session(60, [10, 9, 8])],
                                    repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        #expect(s.reason == .hold)
    }

    @Test func twoBadSessionsDeloadTenPercent() {
        let s = Progression.suggest(sessions: [session(62.5, [7, 6, 6]), session(62.5, [8, 7, 6])],
                                    repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        // 62.5 × 0.9 = 56.25 sits exactly between 55 and 57.5 → ties round down.
        #expect(s == ProgressionSuggestion(weightKg: 55, reason: .decrease(percent: 10)))
        // 80 × 0.9 = 72 → nearest 2.5 is 72.5.
        let s2 = Progression.suggest(sessions: [session(80, [5]), session(80, [5])], repMin: 6, repMax: 8, increment: 2.5, isLowerBody: false)
        #expect(s2.weightKg == 72.5)
    }

    @Test func warmupsAndEmptySessionsAreIgnored() {
        var last = session(60, [12, 12])
        last.insert(SetRecord(reps: 5, weightKg: 40, isWarmup: true), at: 0)
        let s = Progression.suggest(sessions: [[], last], repMin: 8, repMax: 12, increment: 2.5, isLowerBody: false)
        #expect(s.weightKg == 62.5)
    }
}
