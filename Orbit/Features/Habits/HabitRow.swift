import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// One habit: grey icon tile, name, subtitle (progress / reminder / schedule / streak), control.
struct HabitRow: View {
    let habit: Habit
    let logs: [Int: HabitDay]
    let calc: HabitCalculator
    let today: Int
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    var body: some View {
        let rule = habit.rule(calendar: calc.calendar)
        let streak = calc.streak(rule, logs: logs, today: today)
        let subtitle = HabitSubtitle(habit: habit, rule: rule, logs: logs, streak: streak, today: today, locale: locale)

        HStack(spacing: 12) {
            Image(systemName: habit.iconName)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.orbit.iconTint)
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                if !subtitle.text.isEmpty {
                    Text(subtitle.text)
                        .font(.subheadline.weight(subtitle.isBest ? .semibold : .regular))
                        .foregroundStyle(subtitle.isBest ? Color.orbit.accent : Color.orbit.textSecondary)
                }
            }
            Spacer(minLength: 8)
            control(rule: rule, logs: logs)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(rule: HabitRule, logs: [Int: HabitDay]) -> some View {
        if let perWeek = rule.timesPerWeek {
            // Weekly habits: "2/3", tapping logs (or un-logs) today.
            let doneToday = calc.isDone(rule, logs[today])
            Button {
                HabitRepository.toggle(habit, day: today, in: context)
            } label: {
                Text(verbatim: "\(calc.doneInWeek(rule, logs: logs, containing: today))/\(perWeek)")
                    .font(Typography.metric)
                    .foregroundStyle(doneToday ? Color.orbit.accent : Color.primary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(doneToday ? "habits.a11y.unlogToday" : "habits.a11y.logToday"))
        } else if logs[today]?.isSkipped == true {
            HabitCheckButton(.skipped, label: Text("habits.action.unskip")) {
                HabitRepository.setSkipped(false, for: habit, day: today, calculator: calc, in: context)
            }
        } else if habit.type == .count {
            HabitCheckButton(.count(value: logs[today]?.value ?? 0, target: habit.targetCount), label: Text("habits.a11y.addOne")) {
                HabitRepository.increment(habit, day: today, in: context)
            }
        } else {
            let done = calc.isDone(rule, logs[today])
            HabitCheckButton(.check(done: done), label: Text(done ? "habits.a11y.undo" : "habits.a11y.markDone")) {
                HabitRepository.toggle(habit, day: today, in: context)
            }
        }
    }
}

/// Builds the row subtitle like the canvas: "3 dari 8 gelas · setiap hari", "Pengingat 21.00 · 8 hari",
/// "Sen–Sab · 5 hari", "31 hari beruntun · terbaik", "3x seminggu · 4 minggu".
struct HabitSubtitle {
    var text = ""
    var isBest = false

    init(habit: Habit, rule: HabitRule, logs: [Int: HabitDay], streak: HabitStreak, today: Int, locale: Locale) {
        var parts: [String] = []
        if let perWeek = rule.timesPerWeek {
            parts.append(locale.localized("habit.schedule.timesPerWeek \(perWeek)"))
        } else {
            if habit.type == .count {
                let value = logs[today]?.value ?? 0
                parts.append(locale.localized("habit.count.progress \(value) \(habit.targetCount) \(habit.unit)").trimmingCharacters(in: .whitespaces))
            }
            if let minutes = habit.reminderMinutes.min() {
                parts.append(locale.localized("habit.reminder \(Self.time(minutes, locale))"))
            } else if habit.type == .count || rule.schedule != .daily {
                parts.append(Self.schedule(rule.schedule, locale: locale))
            }
        }
        if streak.current > 0, parts.count < 2 {
            let short = !parts.isEmpty
            let n = streak.current
            let text = switch (streak.inWeeks, short) {
            case (false, false): locale.localized("habit.streak.days.long \(n)")
            case (false, true): locale.localized("habit.streak.days.short \(n)")
            case (true, false): locale.localized("habit.streak.weeks.long \(n)")
            case (true, true): locale.localized("habit.streak.weeks.short \(n)")
            }
            parts.append(text)
            if streak.current >= 7, streak.current == streak.best {
                parts.append(locale.localized("habit.streak.best"))
                isBest = true
            }
        }
        text = parts.joined(separator: " · ")
    }

    static func time(_ minutes: Int, _ locale: Locale) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour().minute().locale(locale))
    }

    /// "setiap hari", "Sen–Sab", "Sen, Rab, Jum", "3x seminggu", "tiap 2 hari".
    static func schedule(_ schedule: HabitRule.Schedule, locale: Locale) -> String {
        switch schedule {
        case .daily:
            return locale.localized("habit.schedule.daily")
        case .timesPerWeek(let n):
            return locale.localized("habit.schedule.timesPerWeek \(n)")
        case .everyNDays(let n):
            return locale.localized("habit.schedule.everyNDays \(n)")
        case .weekdays(let days):
            var cal = Calendar(identifier: .gregorian)
            cal.locale = locale
            let symbols = cal.shortStandaloneWeekdaySymbols
            let order = [2, 3, 4, 5, 6, 7, 1]
            let picked = order.filter(days.contains)
            // Contiguous Mon-first run of 3+ days → "Sen–Sab".
            if picked.count >= 3, let first = order.firstIndex(of: picked[0]),
               Array(order[first..<min(first + picked.count, order.count)]) == picked {
                return "\(symbols[picked[0] - 1])–\(symbols[picked[picked.count - 1] - 1])"
            }
            return picked.map { symbols[$0 - 1] }.formatted(.list(type: .and).locale(locale))
        }
    }
}

extension Locale {
    /// A catalog string in this locale's language — for text built outside `Text`.
    func localized(_ value: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(value, locale: self))
    }
}
