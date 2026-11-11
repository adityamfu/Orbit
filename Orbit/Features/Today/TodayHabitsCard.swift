import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// TOD-03: Kartu kebiasaan hari ini — daftar habit terjadwal dengan toggle / +1.
struct TodayHabitsCard: View {
    let habits: [Habit]
    let logsByHabit: [UUID: [Int: HabitDay]]
    let calc: HabitCalculator
    let today: Int
    let context: ModelContext
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("tab.today.habits").font(Typography.section)
                Spacer()
                Text("\(doneCount) / \(habits.count)").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orbit.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(habits) { habit in
                    TodayHabitRow(habit: habit, logs: logsByHabit[habit.id] ?? [:], calc: calc, today: today, context: context)
                    if habit.id != habits.last?.id { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 16)
            .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private var doneCount: Int {
        habits.filter { habit in
            let entry = logsByHabit[habit.id]?[today]
            return calc.isDone(habit.rule(), entry)
        }.count
    }
}

/// One habit row in today's card.
private struct TodayHabitRow: View {
    let habit: Habit
    let logs: [Int: HabitDay]
    let calc: HabitCalculator
    let today: Int
    let context: ModelContext

    var body: some View {
        let entry = logs[today]
        let isDone = calc.isDone(habit.rule(), entry)
        HStack(spacing: 12) {
            Image(systemName: habit.iconName)
                .foregroundStyle(Color.orbit.iconTint)
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: habit.name).font(.body.weight(.medium))
                if habit.type == .count, let entry {
                    Text("\(entry.value) / \(habit.targetCount) \(habit.unit)")
                        .font(.caption)
                        .foregroundStyle(Color.orbit.textSecondary)
                } else {
                    let streak = calc.streak(habit.rule(), logs: logs, today: today)
                    Text("streak \(streak.current)").font(.caption)
                        .foregroundStyle(Color.orbit.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if habit.type == .count {
                Button {
                    HabitRepository.increment(habit, day: today, in: context)
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(Color.orbit.onPrimary)
                        .background(isDone ? Color.orbit.accent : Color.orbit.primary, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("habits.action.increment"))
            } else {
                Button {
                    HabitRepository.toggle(habit, day: today, in: context)
                } label: {
                    HabitCheckMark(isDone ? .check(done: true) : .check(done: false), size: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isDone ? "habits.a11y.undo" : "habits.a11y.markDone"))
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .opacity(isDone ? 0.6 : 1)
    }
}

#Preview("Habits card") {
    TodayHabitsCard(
        habits: [],
        logsByHabit: [:],
        calc: HabitCalculator(firstWeekday: 2),
        today: DayKey.day(.now),
        context: try! OrbitData.makeContainer(inMemory: true).mainContext
    )
}
