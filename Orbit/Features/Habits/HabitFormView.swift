import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Add / edit a habit (native Form, DESIGN.md §5.4).
struct HabitFormView: View {
    let habit: Habit?
    let nextSortOrder: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var name: String
    @State private var icon: String
    @State private var type: HabitType
    @State private var target: Int
    @State private var unit: String
    @State private var kind: Kind
    @State private var weekdays: Set<Int>
    @State private var perWeek: Int
    @State private var everyN: Int
    @State private var reminders: [Int]

    enum Kind: CaseIterable { case daily, weekdays, timesPerWeek, everyNDays }

    static let icons = [
        "drop", "figure.walk", "figure.run", "figure.flexibility", "dumbbell", "bicycle",
        "waveform.path.ecg", "heart", "pills", "bed.double", "moon", "sun.max",
        "book", "pencil", "chevron.left.forwardslash.chevron.right", "brain.head.profile", "music.note", "leaf",
        "frying.pan", "fork.knife", "cup.and.saucer", "house", "phone.down", "sparkles",
    ]

    init(habit: Habit?, nextSortOrder: Int) {
        self.habit = habit
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.iconName ?? Self.icons[0])
        _type = State(initialValue: habit?.type ?? .check)
        _target = State(initialValue: habit.map { max($0.targetCount, 2) } ?? 8)
        _unit = State(initialValue: habit?.unit ?? "")
        _reminders = State(initialValue: habit?.reminderMinutes.sorted() ?? [])
        var kind = Kind.daily, days: Set<Int> = [2, 3, 4, 5, 6], perWeek = 3, everyN = 2
        switch habit?.schedule ?? .daily {
        case .daily: break
        case .weekdays(let d): kind = .weekdays; days = d
        case .timesPerWeek(let n): kind = .timesPerWeek; perWeek = n
        case .everyNDays(let n): kind = .everyNDays; everyN = n
        }
        _kind = State(initialValue: kind)
        _weekdays = State(initialValue: days)
        _perWeek = State(initialValue: perWeek)
        _everyN = State(initialValue: everyN)
    }

    private var schedule: HabitRule.Schedule {
        switch kind {
        case .daily: .daily
        case .weekdays: .weekdays(weekdays)
        case .timesPerWeek: .timesPerWeek(perWeek)
        case .everyNDays: .everyNDays(everyN)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kind != .weekdays || !weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("habit.form.name", text: $name)
                        .font(.body.weight(.medium))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Self.icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                Image(systemName: symbol)
                                    .frame(width: 40, height: 40)
                                    .foregroundStyle(icon == symbol ? Color.orbit.accent : Color.orbit.iconTint)
                                    .background(icon == symbol ? Color.orbit.accentSoft : Color.orbit.iconTile,
                                                in: .rect(cornerRadius: 11, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(icon == symbol ? Color.orbit.accent : .clear, lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: symbol))
                            .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("habit.form.section.type") {
                    Picker("habit.form.section.type", selection: $type) {
                        Text("habit.type.check").tag(HabitType.check)
                        Text("habit.type.count").tag(HabitType.count)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if type == .count {
                        Stepper(value: $target, in: 2...100) {
                            Text("habit.form.target \(target)")
                        }
                        TextField("habit.form.unit", text: $unit)
                    }
                }

                Section("habit.form.section.schedule") {
                    Picker("habit.form.section.schedule", selection: $kind) {
                        Text("habit.schedule.kind.daily").tag(Kind.daily)
                        Text("habit.schedule.kind.weekdays").tag(Kind.weekdays)
                        Text("habit.schedule.kind.timesPerWeek").tag(Kind.timesPerWeek)
                        Text("habit.schedule.kind.everyNDays").tag(Kind.everyNDays)
                    }
                    switch kind {
                    case .daily: EmptyView()
                    case .weekdays: weekdayPicker
                    case .timesPerWeek:
                        Stepper(value: $perWeek, in: 1...7) { Text("habit.schedule.timesPerWeek \(perWeek)") }
                    case .everyNDays:
                        Stepper(value: $everyN, in: 2...30) { Text("habit.schedule.everyNDays \(everyN)") }
                    }
                }

                Section {
                    ForEach(reminders.indices, id: \.self) { i in
                        DatePicker("habit.form.reminder", selection: reminderBinding(i), displayedComponents: .hourAndMinute)
                    }
                    .onDelete { reminders.remove(atOffsets: $0) }
                    Button("habit.form.addReminder", systemImage: "bell") {
                        reminders.append(reminders.last.map { min($0 + 60, 23 * 60 + 59) } ?? 20 * 60)
                    }
                } header: {
                    Text("habit.form.section.reminders")
                } footer: {
                    Text("habit.form.reminders.footer")
                }

                if let habit {
                    Section {
                        Button("habits.action.archive", role: .destructive) {
                            HabitRepository.setArchived(true, habit)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text(habit == nil ? "habit.form.newTitle" : "habit.form.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return HStack {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let on = weekdays.contains(day)
                Button {
                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? Color.orbit.onAccent : Color.primary)
                        .background(on ? Color.orbit.accent : Color.orbit.iconTile, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(cal.standaloneWeekdaySymbols[day - 1]))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func reminderBinding(_ i: Int) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: reminders[i] / 60, minute: reminders[i] % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            reminders[i] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target = type == .check ? 1 : target
        let reminders = Array(Set(reminders)).sorted()
        if let habit {
            habit.name = trimmed
            habit.iconName = icon
            habit.type = type
            habit.targetCount = target
            habit.unit = type == .count ? unit : ""
            habit.schedule = schedule
            habit.reminderMinutes = reminders
            habit.updatedAt = .now
        } else {
            context.insert(Habit(name: trimmed, iconName: icon, type: type, targetCount: target,
                                 unit: type == .count ? unit : "", schedule: schedule,
                                 reminderMinutes: reminders, sortOrder: nextSortOrder))
        }
        HabitRepository.save(context)
        dismiss()
    }
}

#Preview("New") {
    HabitFormView(habit: nil, nextSortOrder: 0)
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
}
