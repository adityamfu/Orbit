import Foundation
import Testing
@testable import OrbitEngine

struct KPITests {
    /// Monday 2026-11-09. With firstWeekday = 2 (Mon):
    /// this week = Mon Nov 9 – Sun Nov 15 (daysAgo 0-6)
    /// last week = Mon Nov 2 – Sun Nov 8 (daysAgo 7-13)
    /// week 2   = Mon Oct 26 – Sun Nov 1  (daysAgo 14-20)
    /// week 3   = Mon Oct 19 – Sun Oct 25 (daysAgo 21-27)
    /// week 4   = Mon Oct 12 – Sun Oct 18 (daysAgo 28-34)
    let now = Date(timeIntervalSince1970: 1_731_139_200) // 2026-11-09 00:00:00 UTC (Monday)

    private func session(daysAgo: Int, volumeKg: Double, cardioMinutes: Double = 0) -> KPISession {
        let started = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return KPISession(startedAt: started, volumeKg: volumeKg, durationSec: 3600, cardioMinutes: cardioMinutes)
    }

    @Test func coldStartNoHistory() {
        let kpi = KPIEngine.nextWeek(sessions: [], firstWeekday: 2, scheduledDays: 3, now: now)
        #expect(kpi.sessions.target == 0)
        #expect(kpi.sessions.reason.contains("kalibrasi"))
        #expect(kpi.volume.target == 0)
        #expect(kpi.cardioMinutes.target == KPIEngine.weeklyCardioReference)
        #expect(kpi.steps.target == 0)
        #expect(kpi.score == 0)
    }

    @Test func sessionTargetGoesUpAfterTwoFullWeeks() {
        let sessions: [KPISession] = [
            // Week 4: 3 sessions
            session(daysAgo: 28, volumeKg: 100), session(daysAgo: 29, volumeKg: 100), session(daysAgo: 30, volumeKg: 100),
            // Week 3: 3 sessions
            session(daysAgo: 21, volumeKg: 100), session(daysAgo: 22, volumeKg: 100), session(daysAgo: 23, volumeKg: 100),
            // Week 2: 3 sessions
            session(daysAgo: 14, volumeKg: 100), session(daysAgo: 15, volumeKg: 100), session(daysAgo: 16, volumeKg: 100),
            // Last week: 3 sessions
            session(daysAgo: 7, volumeKg: 100), session(daysAgo: 8, volumeKg: 100), session(daysAgo: 9, volumeKg: 100),
            // This week: 3 sessions (already done)
            session(daysAgo: 0, volumeKg: 100), session(daysAgo: 1, volumeKg: 100), session(daysAgo: 2, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 3, now: now)
        #expect(kpi.sessions.target == 3) // baseline 3 + 1, capped at scheduledDays 3
        #expect(kpi.sessions.reason.contains("100% 2 minggu"))
    }

    @Test func sessionTargetGoesDownAfterBelow50Percent() {
        let sessions: [KPISession] = [
            // Week 4: 3 sessions
            session(daysAgo: 28, volumeKg: 100), session(daysAgo: 29, volumeKg: 100), session(daysAgo: 30, volumeKg: 100),
            // Week 3: 3 sessions
            session(daysAgo: 21, volumeKg: 100), session(daysAgo: 22, volumeKg: 100), session(daysAgo: 23, volumeKg: 100),
            // Week 2: 3 sessions
            session(daysAgo: 14, volumeKg: 100), session(daysAgo: 15, volumeKg: 100), session(daysAgo: 16, volumeKg: 100),
            // Last week: 1 session (< 50% of baseline 3)
            session(daysAgo: 7, volumeKg: 100),
            // This week: 3 sessions
            session(daysAgo: 0, volumeKg: 100), session(daysAgo: 1, volumeKg: 100), session(daysAgo: 2, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 5, now: now)
        #expect(kpi.sessions.target == 2) // baseline 3 - 1
        #expect(kpi.sessions.reason.contains("di bawah 50%"))
    }

    @Test func volumeGoesUpAfter95Percent() {
        let sessions: [KPISession] = [
            // Week 4: 100 kg
            session(daysAgo: 28, volumeKg: 100),
            // Week 3: 100 kg
            session(daysAgo: 21, volumeKg: 100),
            // Week 2: 100 kg
            session(daysAgo: 14, volumeKg: 100),
            // Last week: 100 kg (≥ 95% of baseline 100)
            session(daysAgo: 7, volumeKg: 100),
            // This week: 100 kg
            session(daysAgo: 2, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 5, now: now)
        #expect(kpi.volume.target == 105) // 100 * 1.05
        #expect(kpi.volume.reason.contains("≥ 95%"))
    }

    @Test func volumeGoesDownBelow70Percent() {
        let sessions: [KPISession] = [
            // Week 4: 100 kg
            session(daysAgo: 28, volumeKg: 100),
            // Week 3: 100 kg
            session(daysAgo: 21, volumeKg: 100),
            // Week 2: 100 kg
            session(daysAgo: 14, volumeKg: 100),
            // Last week: 50 kg (< 70% of baseline ~83)
            session(daysAgo: 7, volumeKg: 50),
            // This week: 100 kg
            session(daysAgo: 2, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 5, now: now)
        #expect(abs(kpi.volume.target - 75) < 0.001) // ~83.33 * 0.9 = 75
        #expect(kpi.volume.reason.contains("di bawah 70%"))
    }

    @Test func volumeStaysBetween70And95Percent() {
        let sessions: [KPISession] = [
            // Week 4: 100 kg
            session(daysAgo: 28, volumeKg: 100),
            // Week 3: 100 kg
            session(daysAgo: 21, volumeKg: 100),
            // Week 2: 100 kg
            session(daysAgo: 14, volumeKg: 100),
            // Last week: 85 kg (70-95% of baseline 95)
            session(daysAgo: 7, volumeKg: 85),
            // This week: 100 kg
            session(daysAgo: 2, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 5, now: now)
        #expect(kpi.volume.target == 95) // baseline
        #expect(kpi.volume.reason.contains("tetap"))
    }

    @Test func cardioTargetUsesHealthData() {
        let sessions: [KPISession] = [session(daysAgo: 1, volumeKg: 50, cardioMinutes: 30)]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 5,
                                     cardioMinutesLastWeek: 180, avgDailyStepsLastWeek: 0, now: now)
        #expect(kpi.cardioMinutes.target == 180)
        #expect(kpi.cardioMinutes.reason.contains("WHO"))
    }

    @Test func cardioTargetFallsBackToWHOReference() {
        let kpi = KPIEngine.nextWeek(sessions: [], firstWeekday: 2, scheduledDays: 5,
                                     cardioMinutesLastWeek: 0, avgDailyStepsLastWeek: 0, now: now)
        #expect(kpi.cardioMinutes.target == KPIEngine.weeklyCardioReference)
    }

    @Test func stepsTargetRoundsTo500() {
        let kpi = KPIEngine.nextWeek(sessions: [], firstWeekday: 2, scheduledDays: 5,
                                     cardioMinutesLastWeek: 0, avgDailyStepsLastWeek: 8000, now: now)
        // 8000 * 1.05 = 8400 → /500 = 16.8 → round 17 → 8500
        #expect(kpi.steps.target == 8500)
    }

    @Test func weeklyScoreIsAverageOfAchievements() {
        let sessions: [KPISession] = [
            // This week: 3 sessions, 100 kg volume
            session(daysAgo: 0, volumeKg: 0), session(daysAgo: 1, volumeKg: 0), session(daysAgo: 2, volumeKg: 100),
            // Last week: 85 kg volume
            session(daysAgo: 7, volumeKg: 85),
            // Week 2: 100 kg
            session(daysAgo: 14, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 3,
                                     cardioMinutesLastWeek: 0, avgDailyStepsLastWeek: 0, now: now)
        #expect(kpi.sessions.achievementPercent == 100)
        #expect(kpi.volume.achievementPercent == 100) // 100 actual vs ~62 target, capped at 100
        #expect(kpi.cardioMinutes.achievementPercent == 0)
        #expect(kpi.steps.achievementPercent == 0) // no steps data yet (target 0)
        #expect(kpi.score == 50) // (100+100+0+0)/4
    }

    @Test func scheduledDaysCapApplies() {
        let sessions: [KPISession] = [
            // Week 4: 3 sessions
            session(daysAgo: 28, volumeKg: 100), session(daysAgo: 29, volumeKg: 100), session(daysAgo: 30, volumeKg: 100),
            // Week 3: 3 sessions
            session(daysAgo: 21, volumeKg: 100), session(daysAgo: 22, volumeKg: 100), session(daysAgo: 23, volumeKg: 100),
            // Week 2: 3 sessions
            session(daysAgo: 14, volumeKg: 100), session(daysAgo: 15, volumeKg: 100), session(daysAgo: 16, volumeKg: 100),
            // Last week: 3 sessions
            session(daysAgo: 7, volumeKg: 100), session(daysAgo: 8, volumeKg: 100), session(daysAgo: 9, volumeKg: 100),
        ]
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: 2, scheduledDays: 3, now: now)
        #expect(kpi.sessions.target == 3) // baseline 3 + 1 = 4, capped at scheduledDays 3
    }
}
