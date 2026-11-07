import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Habits tab (DESIGN.md §5.4, canvas p.5).
struct HabitsView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder) private var habits: [Habit]
    @Query(filter: #Predicate<Habit> { $0.isArchived }) private var archived: [Habit]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.firstWeekday, store: .orbit) private var firstWeekday = SettingsSnapshot.defaults.firstWeekday

    @State private var today = DayKey.day(.now)
    @State private var showNew = false
    @State private var editing: Habit?
    @State private var skipDenied = false

    private var calc: HabitCalculator { HabitCalculator(firstWeekday: firstWeekday) }

    var body: some View {
        // Group once per render: day-based habits due today, weekly ones, and the rest.
        let due = habits.filter { calc.isScheduled($0.rule(), on: today) }
        let weekly = habits.filter { $0.rule().isWeekly }
        let other = habits.filter { !$0.rule().isWeekly && !calc.isScheduled($0.rule(), on: today) }
        // Logs are read here and passed down as plain values: children re-render whenever this
        // body does (after every save), instead of relying on observing each HabitLog.
        let logs = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0.dayLogs) })
        let inputs = habits.map { ($0.rule(), logs[$0.id] ?? [:]) }
        let progress = calc.dayProgress(inputs, on: today)

        NavigationStack {
            List {
                ScreenHeader(Text("tab.habits")) {
                    RoundAddButton(label: Text("habits.add")) { showNew = true }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                if habits.isEmpty {
                    emptyState
                } else {
                    Section {
                        WeekStrip(inputs: inputs, calc: calc, today: today)
                    }

                    if !due.isEmpty {
                        Section {
                            rows(due, logs)
                        } header: {
                            HStack {
                                Text("habits.section.today")
                                Spacer()
                                Text("habits.today.progress \(progress.done) \(progress.total)").textCase(nil)
                            }
                        }
                    }
                    if !weekly.isEmpty {
                        Section("habits.section.week") { rows(weekly, logs) }
                    }
                    if !other.isEmpty {
                        Section("habits.section.other") { rows(other, logs) }
                    }
                }
                if !archived.isEmpty {
                    Section {
                        NavigationLink {
                            ArchivedHabitsView()
                        } label: {
                            LabeledContent("habits.archived") { Text(verbatim: "\(archived.count)") }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.orbit.bg)
            .navigationTitle(Text("tab.habits"))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNew) { HabitFormView(habit: nil, nextSortOrder: habits.count) }
            .sheet(item: $editing) { HabitFormView(habit: $0, nextSortOrder: habits.count) }
            .alert("habits.skip.denied.title", isPresented: $skipDenied) {
                Button("common.ok", role: .cancel) {}
            } message: {
                Text("habits.skip.denied.message")
            }
            // Keep "today" right after midnight or when coming back to the app.
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = DayKey.day(.now) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = DayKey.day(.now) } }
        }
    }

    private func rows(_ group: [Habit], _ logs: [UUID: [Int: HabitDay]]) -> some View {
        ForEach(group) { habit in
            NavigationLink {
                HabitDetailView(habit: habit)
            } label: {
                HabitRow(habit: habit, logs: logs[habit.id] ?? [:], calc: calc, today: today)
            }
                .swipeActions(edge: .leading) { skipAction(habit) }
                .swipeActions(edge: .trailing) {
                    Button("habits.action.archive", systemImage: "archivebox") {
                        HabitRepository.setArchived(true, habit)
                    }
                    .tint(.gray)
                    // System blue: the accent turns lime in dark mode, and lime can't carry the white swipe icon.
                    Button("habits.action.edit", systemImage: "pencil") { editing = habit }
                        .tint(.blue)
                    if habit.type == .count, (habit.log(on: today)?.value ?? 0) > 0 {
                        Button("habits.action.reset", systemImage: "arrow.counterclockwise") {
                            HabitRepository.setValue(0, for: habit, day: today, in: context)
                        }
                    }
                }
        }
        .onMove { HabitRepository.move(group, fromOffsets: $0, toOffset: $1) }
    }

    @ViewBuilder
    private func skipAction(_ habit: Habit) -> some View {
        if habit.log(on: today)?.isSkipped == true {
            Button("habits.action.unskip", systemImage: "arrow.uturn.backward") {
                HabitRepository.setSkipped(false, for: habit, day: today, calculator: calc, in: context)
            }
        } else if !habit.rule().isWeekly {
            Button("habits.action.skip", systemImage: "forward.end") {
                skipDenied = !HabitRepository.setSkipped(true, for: habit, day: today, calculator: calc, in: context)
            }
            .tint(.indigo)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("habits.empty.title", systemImage: "checkmark.circle")
        } description: {
            Text("habits.empty.description")
        } actions: {
            Button("habits.empty.action") { showNew = true }
                .buttonStyle(.orbitPrimary)
        }
        .listRowBackground(Color.clear)
    }
}

/// HAB-07: Mon–Sun with each day's share of due habits done.
private struct WeekStrip: View {
    let inputs: [(rule: HabitRule, logs: [Int: HabitDay])]
    let calc: HabitCalculator
    let today: Int
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            ForEach(calc.weekDays(containing: today), id: \.self) { day in
                let p = calc.dayProgress(inputs, on: day)
                let isToday = day == today
                VStack(spacing: 8) {
                    Text(shortWeekday(day))
                        .font(.footnote.weight(isToday ? .bold : .semibold))
                        .foregroundStyle(isToday ? Color.orbit.accent : Color.orbit.textSecondary)
                    MiniRing(progress: day > today || p.total == 0 ? 0 : Double(p.done) / Double(p.total), lineWidth: 4) {
                        if isToday {
                            Circle().fill(Color.orbit.accent).padding(5)
                        }
                    }
                    .frame(width: 34, height: 34)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(fullWeekday(day)))
                .accessibilityValue(Text("habits.today.progress \(p.done) \(p.total)"))
            }
        }
        .padding(.vertical, 4)
    }

    private func date(_ day: Int) -> Date { DayKey.date(fromDay: day, calendar: calc.calendar) ?? .now }

    private func shortWeekday(_ day: Int) -> String {
        date(day).formatted(.dateTime.weekday(.abbreviated).locale(locale))
    }

    private func fullWeekday(_ day: Int) -> String {
        date(day).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }
}

#Preview("Habits") {
    HabitsView()
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty, dark, English") {
    HabitsView()
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
}
