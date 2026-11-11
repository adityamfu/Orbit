import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Insight tab: weekly KPI score, targets vs actuals, and highlights (PRD §4.5, KPI-06).
struct InsightView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.firstWeekday, store: .orbit) private var firstWeekday = SettingsSnapshot.defaults.firstWeekday

    var body: some View {
        let sessions = kpiSessions(in: context)
        let kpi = KPIEngine.nextWeek(sessions: sessions, firstWeekday: firstWeekday, scheduledDays: 3, now: .now)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(Text("insight.title"))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                // Weekly score card.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("insight.score").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.orbit.textSecondary)
                            Text(verbatim: "\(kpi.score)").font(Typography.statHero)
                                .foregroundStyle(Color.orbit.accent)
                                .tracking(-1.5)
                        }
                        Spacer()
                        MiniRing(progress: Double(kpi.score) / 100, lineWidth: 10) {
                            Text(verbatim: "\(kpi.score)%").font(Typography.metric)
                        }
                        .frame(width: 80, height: 80)
                    }
                    Text(kpiScoreText(kpi.score)).font(.body)
                        .foregroundStyle(Color.orbit.textSecondary)
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 28, style: .continuous))

                // KPI table: target vs actual.
                VStack(alignment: .leading, spacing: 8) {
                    Text("insight.kpi.title").font(Typography.section)
                    ForEach(kpiRows(kpi), id: \.metric) { row in
                        KPIRow(metric: LocalizedStringKey(row.metric), target: row.target, actual: row.actual,
                               percent: row.percent, reason: row.reason)
                    }
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))

                // This week's target with engine reason.
                VStack(alignment: .leading, spacing: 8) {
                    Text("insight.target.title").font(Typography.section)
                    ForEach(kpiTargetRows(kpi), id: \.metric) { row in
                        HStack(spacing: 10) {
                            Text(LocalizedStringKey(row.metric)).font(.subheadline.weight(.medium))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: row.value).font(Typography.metric)
                                Text(verbatim: row.reason).font(.caption2)
                                    .foregroundStyle(Color.orbit.textSecondary)
                            }
                        }
                        .padding(.vertical, 6)
                        if row.metric != kpiTargetRows(kpi).last?.metric { Divider().padding(.leading, 120) }
                    }
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))

                // Highlights.
                VStack(alignment: .leading, spacing: 8) {
                    Text("insight.highlights.title").font(Typography.section)
                    HStack(spacing: 10) {
                        HighlightTile(title: "insight.highlight.pr", value: "—", icon: "trophy")
                        HighlightTile(title: "insight.highlight.streak", value: "—", icon: "flame")
                        HighlightTile(title: "insight.highlight.spending", value: "—", icon: "wallet.bifold")
                    }
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .padding(16)
        }
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func kpiRows(_ kpi: WeeklyKPI) -> [(metric: String, target: Double, actual: Double, percent: Int, reason: String)] {
        [
            ("insight.kpi.sessions", kpi.sessions.target, kpi.sessions.actual, kpi.sessions.achievementPercent, kpi.sessions.reason),
            ("insight.kpi.volume", kpi.volume.target, kpi.volume.actual, kpi.volume.achievementPercent, kpi.volume.reason),
            ("insight.kpi.cardio", kpi.cardioMinutes.target, kpi.cardioMinutes.actual, kpi.cardioMinutes.achievementPercent, kpi.cardioMinutes.reason),
            ("insight.kpi.steps", kpi.steps.target, kpi.steps.actual, kpi.steps.achievementPercent, kpi.steps.reason),
        ]
    }

    private func kpiTargetRows(_ kpi: WeeklyKPI) -> [(metric: String, value: String, reason: String)] {
        [
            ("insight.kpi.sessions", "\(Int(kpi.sessions.target))", kpi.sessions.reason),
            ("insight.kpi.volume", "\(Int(kpi.volume.target)) kg", kpi.volume.reason),
            ("insight.kpi.cardio", "\(Int(kpi.cardioMinutes.target)) min", kpi.cardioMinutes.reason),
            ("insight.kpi.steps", "\(Int(kpi.steps.target))", kpi.steps.reason),
        ]
    }

    private func kpiScoreText(_ score: Int) -> String {
        switch score {
        case 80...: return "insight.score.great"
        case 50..<80: return "insight.score.good"
        case 1..<50: return "insight.score.fair"
        default: return "insight.score.start"
        }
    }
}

/// One KPI row: target vs actual with status chip.
private struct KPIRow: View {
    let metric: LocalizedStringKey
    let target: Double
    let actual: Double
    let percent: Int
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Text(metric).font(.subheadline.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: format(actual)).font(.subheadline.monospacedDigit())
                    Text(verbatim: "/\(format(target))").font(.caption2)
                        .foregroundStyle(Color.orbit.textSecondary)
                }
                Text("\(percent)%").font(.caption.weight(.semibold))
                    .foregroundStyle(percent >= 100 ? Color.orbit.accent : Color.orbit.textSecondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func format(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

}

/// Highlight tile (placeholder until HealthKit/habit data is wired).
private struct HighlightTile: View {
    let title: LocalizedStringKey
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.orbit.accent)
            Text(value).font(Typography.metric)
            Text(title).font(.caption2).foregroundStyle(Color.orbit.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color.orbit.card, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

/// Finished sessions as engine-side KPI snapshots.
private func kpiSessions(in context: ModelContext) -> [KPISession] {
    let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    return sessions.filter { $0.endedAt != nil }.map { session in
        let sets = session.sets.filter { $0.isCompleted && !$0.isWarmup }
        let volume = Strength.volume(sets.map(\.record))
        let cardio = sets.reduce(0.0) { total, set in
            total + (Double(set.durationSec ?? 0) / 60.0)
        }
        let durationSec = session.endedAt.map { Int($0.timeIntervalSince(session.startedAt)) } ?? 0
        return KPISession(startedAt: session.startedAt, volumeKg: volume,
                          durationSec: durationSec, cardioMinutes: cardio)
    }
}

#Preview("Insight") {
    NavigationStack { InsightView() }
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty, English") {
    NavigationStack { InsightView() }
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
        .environment(\.locale, Locale(identifier: "en_US"))
}
