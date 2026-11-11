import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Today tab (PRD §4.1, DESIGN.md §5.1).
struct TodayView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder) private var habits: [Habit]
    @Query private var habitLogs: [HabitLog]
    @Query private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.firstWeekday, store: .orbit) private var firstWeekday = SettingsSnapshot.defaults.firstWeekday

    @State private var showingWorkout = false

    private var calc: HabitCalculator { HabitCalculator(firstWeekday: firstWeekday) }
    private var today: Int { DayKey.day(.now) }

    /// Habit logs keyed by habit id, then by day key.
    private var logsByHabit: [UUID: [Int: HabitDay]] {
        Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.dayLogs) })
    }

    /// Habits scheduled for today.
    private var todaysHabits: [Habit] {
        habits.filter { calc.isScheduled($0.rule(), on: today) }
    }

    /// Routine planned for today's weekday.
    private var todaysRoutine: RoutineTemplate? {
        let routines = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        return WorkoutHistory.routine(for: .now, in: routines, calendar: calc.calendar)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(Text("tab.today"), caption: Text(dateCaption)) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(Color.primary)
                                .frame(width: 44, height: 44)
                                .background(Color.orbit.card, in: .circle)
                        }
                        .accessibilityLabel(Text("settings.title"))
                    }

                    if let expiry = BuildInfo.expirationDate {
                        let days = BuildInfo.daysRemaining(until: expiry)
                        if days <= 2 { ExpiryBanner(days: days) }
                    }

                    // TOD-01 Heatmap
                    TodayHeatmapView(
                        habits: habits,
                        logsByHabit: logsByHabit,
                        calc: calc,
                        today: today
                    )

                    // TOD-02 Four stat cards (2×2 grid).
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                        spacing: 12
                    ) {
                        TodayStatCard(
                            title: "tab.today.stats.streak",
                            icon: "flame",
                            value: "\(overallStreak.current)",
                            subtitle: "\(overallStreak.best) hari terpanjang",
                            color: Color.orbit.accent
                        )
                        TodayStatCard(
                            title: "tab.today.stats.checkins",
                            icon: "checkmark.circle",
                            value: "\(totalCheckins)",
                            subtitle: startDateText,
                            color: Color.orbit.accent
                        )
                        TodayStatCard(
                            title: "tab.today.stats.workouts",
                            icon: "dumbbell",
                            value: "\(sessionsThisWeek) / \(sessionsTarget)",
                            subtitle: "tab.today.stats.workouts.sub",
                            color: Color.orbit.accent
                        )
                        TodayStatCard(
                            title: "tab.today.stats.target",
                            icon: "target",
                            value: "\(kpiScore)%",
                            subtitle: "tab.today.stats.target.sub",
                            color: Color.orbit.accent,
                            progress: Double(kpiScore) / 100
                        )
                    }

                    // TOD-03 Kebiasaan hari ini.
                    if !todaysHabits.isEmpty {
                        TodayHabitsCard(
                            habits: todaysHabits,
                            logsByHabit: logsByHabit,
                            calc: calc,
                            today: today,
                            context: context
                        )
                    }

                    // TOD-04 Latihan hari ini.
                    TodayWorkoutCard(
                        routine: todaysRoutine,
                        sessions: sessions,
                        onStart: { showingWorkout = true }
                    )
                }
                .padding(16)
            }
            .background(Color.orbit.bg)
            .navigationTitle(Text("tab.today"))
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showingWorkout) {
                ActiveSessionView()
            }
        }
    }

    // MARK: - Computed

    private var dateCaption: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    private var totalCheckins: Int {
        habitLogs.count
    }

    private var startDateText: String {
        habits.map(\.startDate).min()?.formatted(.dateTime.day().month(.abbreviated).locale(locale)) ?? ""
    }

    private var sessionsThisWeek: Int {
        let cal = calc.calendar
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return sessions.filter { $0.endedAt != nil && $0.startedAt >= weekStart }.count
    }

    private var sessionsTarget: Int {
        3 // default scheduled days; from settings in a later phase
    }

    private var kpiScore: Int {
        let finished = sessions.filter { $0.endedAt != nil }
        let kpiSessions = finished.map { session -> KPISession in
            let sets = session.sets.filter { $0.isCompleted && !$0.isWarmup }
            let volume = Strength.volume(sets.map(\.record))
            let duration = session.endedAt.map { Int($0.timeIntervalSince(session.startedAt)) } ?? 0
            return KPISession(startedAt: session.startedAt, volumeKg: volume, durationSec: duration)
        }
        let kpi = KPIEngine.nextWeek(
            sessions: kpiSessions, firstWeekday: firstWeekday, scheduledDays: sessionsTarget, now: .now
        )
        return kpi.score
    }

    /// Streak harian keseluruhan: hari berturut-turut di mana semua habit terjadwal selesai.
    private var overallStreak: (current: Int, best: Int) {
        var current = 0, best = 0
        var day = today

        // Today counts if complete.
        let todaysAllDone = !todaysHabits.isEmpty && todaysHabits.allSatisfy { habit in
            let entry = logsByHabit[habit.id]?[today]
            return calc.isDone(habit.rule(), entry)
        }
        if todaysAllDone {
            current = 1
            best = 1
        }

        // Walk backwards from yesterday.
        day = DayKey.adding(-1, to: day)
        while true {
            let scheduled = habits.filter { calc.isScheduled($0.rule(), on: day) }
            guard !scheduled.isEmpty else {
                day = DayKey.adding(-1, to: day)
                continue
            }
            let allDone = scheduled.allSatisfy { habit in
                let entry = logsByHabit[habit.id]?[day]
                return calc.isDone(habit.rule(), entry)
            }
            if allDone {
                current += 1
                best = max(best, current)
                day = DayKey.adding(-1, to: day)
            } else {
                break
            }
        }
        return (current, best)
    }
}

/// TOD-06: free-account builds stop opening after 7 days.
struct ExpiryBanner: View {
    let days: Int

    var body: some View {
        Label {
            if days <= 0 {
                Text("build.expiry.today")
            } else {
                Text("build.expiry.days \(days)")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orbit.accent)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orbit.accentSoft, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

#Preview("Today") {
    TodayView()
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty, English") {
    TodayView()
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
        .environment(\.locale, Locale(identifier: "en_US"))
}
