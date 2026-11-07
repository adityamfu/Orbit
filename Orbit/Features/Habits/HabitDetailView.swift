import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// HAB-08/09: stats, calendar heatmap, and editing past days.
struct HabitDetailView: View {
    let habit: Habit
    /// Queried (not read through `habit.logs`) so the screen redraws after every save.
    @Query private var logRecords: [HabitLog]
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.firstWeekday, store: .orbit) private var firstWeekday = SettingsSnapshot.defaults.firstWeekday

    @State private var month: Date = .now
    @State private var editingDay: EditDay?
    @State private var showEdit = false

    struct EditDay: Identifiable { let id: Int }

    init(habit: Habit) {
        self.habit = habit
        let id = habit.id
        _logRecords = Query(filter: #Predicate<HabitLog> { $0.habitID == id })
    }

    private var calc: HabitCalculator { HabitCalculator(firstWeekday: firstWeekday) }

    var body: some View {
        let today = DayKey.day(.now)
        let rule = habit.rule(calendar: calc.calendar)
        let logs = Dictionary(logRecords.map { ($0.dayKey, HabitDay(value: $0.value, isSkipped: $0.isSkipped)) }) { a, _ in a }
        let streak = calc.streak(rule, logs: logs, today: today)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(Text(habit.name), caption: Text(HabitSubtitle.schedule(habit.schedule, locale: locale)))
                    .padding(.horizontal, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatCard(title: "habit.detail.current", icon: "flame",
                             value: streakText(streak.current, weeks: streak.inWeeks))
                    StatCard(title: "habit.detail.best", icon: "trophy",
                             value: streakText(streak.best, weeks: streak.inWeeks))
                    StatCard(title: "habit.detail.rate30", icon: "calendar",
                             value: percent(calc.completionRate(rule, logs: logs, today: today, days: 30)))
                    StatCard(title: "habit.detail.rate90", icon: "calendar.badge.clock",
                             value: percent(calc.completionRate(rule, logs: logs, today: today, days: 90)))
                }

                HabitCalendar(rule: rule, logs: logs, calc: calc, today: today, month: $month) { day in
                    editingDay = EditDay(id: day)
                }
            }
            .padding(16)
        }
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("habits.action.edit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) { HabitFormView(habit: habit, nextSortOrder: habit.sortOrder) }
        .sheet(item: $editingDay) { day in
            DayEditSheet(habit: habit, day: day.id, entry: logs[day.id], calc: calc)
                .presentationDetents([.height(300)])
        }
        // Archiving from the edit form leaves nothing to show here.
        .onChange(of: habit.isArchived) { _, archived in if archived { dismiss() } }
    }

    private func streakText(_ n: Int, weeks: Bool) -> String {
        locale.localized(weeks ? "habit.streak.weeks.short \(n)" : "habit.streak.days.short \(n)")
    }

    private func percent(_ rate: Double?) -> String {
        rate.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(locale)) } ?? "—"
    }
}

private struct StatCard: View {
    let title: LocalizedStringKey
    let icon: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orbit.textSecondary)
            Text(value)
                .font(Typography.stat)
                .foregroundStyle(Color.orbit.accent)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Month grid coloured by day status. Tap a day (up to today) to edit it.
private struct HabitCalendar: View {
    let rule: HabitRule
    let logs: [Int: HabitDay]
    let calc: HabitCalculator
    let today: Int
    @Binding var month: Date
    let onSelect: (Int) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let cal = calc.calendar
        let interval = cal.dateInterval(of: .month, for: month)!
        let first = interval.start
        let dayCount = cal.range(of: .day, in: .month, for: first)!.count
        let leading = (cal.component(.weekday, from: first) - calc.firstWeekday + 7) % 7
        let days: [Int?] = Array(repeating: nil, count: leading)
            + (0..<dayCount).map { DayKey.day(cal.date(byAdding: .day, value: $0, to: first)!, calendar: cal) }
        let canGoForward = DayKey.day(interval.end, calendar: cal) <= today

        VStack(spacing: 12) {
            HStack {
                Text(first.formatted(.dateTime.month(.wide).year().locale(locale)))
                    .font(Typography.section)
                Spacer()
                monthButton("chevron.left", label: "habit.calendar.previous", by: -1)
                monthButton("chevron.right", label: "habit.calendar.next", by: 1).disabled(!canGoForward)
            }

            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdaySymbols[i])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.orbit.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        cell(day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }

            HStack(spacing: 16) {
                legend(Color.orbit.accent, "habit.calendar.done")
                legend(Color.orbit.accentSoft, "habit.calendar.skipped")
                legend(Color.orbit.iconTile, "habit.calendar.missed")
            }
            .font(.caption)
            .foregroundStyle(Color.orbit.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var weekdaySymbols: [String] {
        var cal = calc.calendar
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calc.firstWeekday - 1 + $0) % 7] }
    }

    @ViewBuilder
    private func cell(_ day: Int) -> some View {
        let status = calc.status(rule, logs[day], on: day, today: today)
        let editable = day <= today && day >= rule.startDay
        let (fill, text): (Color, Color) = switch status {
        case .done: (Color.orbit.accent, Color.orbit.onAccent)
        case .partial(let f): (Color.orbit.accent.opacity(0.2 + 0.5 * f), Color.primary)
        case .skipped: (Color.orbit.accentSoft, Color.orbit.accent)
        case .missed: (Color.orbit.iconTile, Color.primary)
        case .pending, .none: (Color.clear, editable ? Color.primary : Color.secondary.opacity(0.5))
        }
        Button {
            onSelect(day)
        } label: {
            Text(verbatim: "\(day % 100)")
                .font(.footnote.weight(day == today ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(text)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(fill, in: .rect(cornerRadius: 9, style: .continuous))
                .overlay {
                    if day == today {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.orbit.accent, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!editable)
        .accessibilityLabel(Text(dateText(day)))
        .accessibilityValue(Text(statusKey(status)))
    }

    private func statusKey(_ status: HabitCalculator.DayStatus) -> LocalizedStringKey {
        switch status {
        case .done: "habit.calendar.done"
        case .partial: "habit.calendar.partial"
        case .skipped: "habit.calendar.skipped"
        case .missed: "habit.calendar.missed"
        case .pending, .none: ""
        }
    }

    private func dateText(_ day: Int) -> String {
        (DayKey.date(fromDay: day, calendar: calc.calendar) ?? .now)
            .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    private func monthButton(_ icon: String, label: LocalizedStringKey, by months: Int) -> some View {
        Button {
            month = calc.calendar.date(byAdding: .month, value: months, to: month) ?? month
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 36)
                .background(Color.orbit.iconTile, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(title)
        }
    }
}

/// HAB-09: fix a past day (forgot to check yesterday, or log a rest day).
private struct DayEditSheet: View {
    let habit: Habit
    let day: Int
    let calc: HabitCalculator
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var value: Int
    @State private var skipped: Bool
    @State private var skipDenied = false

    init(habit: Habit, day: Int, entry: HabitDay?, calc: HabitCalculator) {
        self.habit = habit
        self.day = day
        self.calc = calc
        _value = State(initialValue: entry?.value ?? 0)
        _skipped = State(initialValue: entry?.isSkipped ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if habit.type == .count {
                    Stepper(value: $value, in: 0...999) {
                        Text("habit.count.progress \(value) \(habit.targetCount) \(habit.unit)")
                    }
                } else {
                    Toggle("habit.day.done", isOn: Binding(get: { value >= 1 }, set: { value = $0 ? 1 : 0 }))
                }
                if !habit.rule().isWeekly {
                    Section {
                        Toggle("habits.action.skip", isOn: $skipped)
                    } footer: {
                        if skipDenied { Text("habits.skip.denied.message") }
                    }
                }
            }
            .navigationTitle(Text(dateTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onChange(of: value) { _, new in
                HabitRepository.setValue(new, for: habit, day: day, in: context)
                if skipped { HabitRepository.setSkipped(true, for: habit, day: day, calculator: calc, in: context) }
            }
            .onChange(of: skipped) { _, new in
                let ok = HabitRepository.setSkipped(new, for: habit, day: day, calculator: calc, in: context)
                if !ok {
                    skipDenied = true
                    skipped = false
                }
            }
        }
    }

    private var dateTitle: String {
        (DayKey.date(fromDay: day, calendar: calc.calendar) ?? .now)
            .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }
}

#Preview("Detail") {
    let container = OrbitData.makePreviewContainer()
    let habit = try! container.mainContext.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))[2]
    return NavigationStack { HabitDetailView(habit: habit) }
        .modelContainer(container)
}
