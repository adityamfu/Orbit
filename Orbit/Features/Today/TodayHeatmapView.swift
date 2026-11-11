import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// TOD-01: Heatmap konsistensi — 7 hari × 18 minggu terakhir. Tiap kotak = persentase
/// habit terjadwal yang selesai di hari itu (5 level).
struct TodayHeatmapView: View {
    let habits: [Habit]
    let logsByHabit: [UUID: [Int: HabitDay]]
    let calc: HabitCalculator
    let today: Int
    @Environment(\.locale) private var locale

    private let weeks = 18
    private let cellSize: CGFloat = 14

    var body: some View {
        let weekGrid = heatmapWeeks()
        let dayLabels = weekdayLabels()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("tab.today.heatmap").font(Typography.section)
                Spacer()
            }

            // Day-of-week labels (Mon–Sun based on firstWeekday setting).
            HStack(spacing: 0) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(Color.orbit.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grid: 7 rows (days) × 18 columns (weeks).
            VStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<weeks, id: \.self) { col in
                            let dayKey = weekGrid[col][row]
                            let level = heatLevel(for: dayKey)
                            let isFuture = dayKey > today
                            Rectangle()
                                .fill(isFuture ? Color.clear : Color.orbit.heat(level))
                                .frame(width: cellSize, height: cellSize)
                                .cornerRadius(4)
                                .opacity(isFuture ? 0.15 : 1)
                        }
                    }
                }
            }

            // Period navigation + range label.
            HStack {
                Button {
                    // Previous period — cut for v1 (shortcut below).
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(true)

                Text("\(formatDate(weekGrid.last?.first ?? today)) – \(formatDate(weekGrid.first?.last ?? today))")
                    .font(.caption)
                    .foregroundStyle(Color.orbit.textSecondary)

                Spacer()
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.orbit.heroTop, Color.orbit.heroBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 28, style: .continuous)
        )
    }

    // MARK: - Computation

    /// Grid: columns = weeks (newest first), rows = days of week (Mon–Sun).
    private func heatmapWeeks() -> [[Int]] {
        var result: [[Int]] = []
        for w in 0..<weeks {
            let start = weekStartDate(offset: -w)
            var weekDays: [Int] = []
            for d in 0..<7 {
                let date = calc.calendar.date(byAdding: .day, value: d, to: start)!
                weekDays.append(DayKey.day(date, calendar: calc.calendar))
            }
            result.append(weekDays)
        }
        return result
    }

    private func weekStartDate(offset: Int) -> Date {
        let now = Date.now
        guard let interval = calc.calendar.dateInterval(of: .weekOfYear, for: now) else { return now }
        let weekStart = interval.start
        return calc.calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart)!
    }

    private func weekdayLabels() -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = calc.firstWeekday
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].map { symbols[$0 - 1] }
    }

    /// Heat level 0–4 for a day: share of scheduled habits that are done.
    private func heatLevel(for dayKey: Int) -> Int {
        let scheduled = habits.filter { calc.isScheduled($0.rule(), on: dayKey) }
        guard !scheduled.isEmpty else { return 0 }
        let done = scheduled.filter { habit in
            let entry = logsByHabit[habit.id]?[dayKey]
            return calc.isDone(habit.rule(), entry)
        }.count
        let pct = Double(done) / Double(scheduled.count)
        return min(max(Int(pct * 4.0 + 0.5), 0), 4)
    }

    private func formatDate(_ dayKey: Int) -> String {
        guard let date = DayKey.date(fromDay: dayKey, calendar: calc.calendar) else { return "" }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}

#Preview("Heatmap") {
    TodayHeatmapView(
        habits: [],
        logsByHabit: [:],
        calc: HabitCalculator(firstWeekday: 2),
        today: DayKey.day(.now)
    )
}
