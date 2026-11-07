import Foundation
import SwiftData
import WidgetKit
import OrbitEngine

/// Widget kinds, so every write can reload exactly the widgets that show it (CLAUDE.md rule 6).
public enum WidgetKinds {
    public static let habits = "HabitsWidget"
    public static let workout = "WorkoutWidget"

    public static func reload(_ kind: String) {
        if OrbitData.isAppOrExtension { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }

    public static func reloadAll() {
        if OrbitData.isAppOrExtension { WidgetCenter.shared.reloadAllTimelines() }
    }
}

/// One habit as a widget row.
public struct HabitWidgetItem: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var iconName: String
    public var isCount: Bool
    public var value: Int
    public var target: Int
    public var isDone: Bool
    public var isSkipped: Bool

    public init(id: UUID, name: String, iconName: String, isCount: Bool, value: Int, target: Int, isDone: Bool, isSkipped: Bool) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isCount = isCount
        self.value = value
        self.target = target
        self.isDone = isDone
        self.isSkipped = isSkipped
    }
}

/// Everything a habit widget shows for one day: habits due that day, not-done ones first.
public struct HabitWidgetSnapshot: Sendable {
    public var date: Date
    public var items: [HabitWidgetItem]

    public var done: Int { items.count { $0.isDone } }
    public var total: Int { items.count }
    public var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    public init(date: Date, items: [HabitWidgetItem]) {
        self.date = date
        self.items = items
    }

    public static func make(habits: [Habit], calculator: HabitCalculator, date: Date) -> HabitWidgetSnapshot {
        let day = DayKey.day(date, calendar: calculator.calendar)
        let items = habits
            .filter { !$0.isArchived }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { habit -> HabitWidgetItem? in
                let rule = habit.rule(calendar: calculator.calendar)
                guard calculator.isScheduled(rule, on: day) else { return nil }
                let entry = habit.dayLogs[day]
                return HabitWidgetItem(
                    id: habit.id, name: habit.name, iconName: habit.iconName, isCount: habit.type == .count,
                    value: entry?.value ?? 0, target: habit.targetCount,
                    isDone: calculator.isDone(rule, entry), isSkipped: entry?.isSkipped ?? false
                )
            }
        // Stable partition: what's left to do comes first, in the user's order.
        return HabitWidgetSnapshot(date: date, items: items.filter { !$0.isDone } + items.filter(\.isDone))
    }

    /// Reads the shared store (used by the widget extension).
    public static func load(date: Date = .now) -> HabitWidgetSnapshot {
        guard let container = try? OrbitData.makeContainer() else { return HabitWidgetSnapshot(date: date, items: []) }
        let habits = (try? ModelContext(container).fetch(FetchDescriptor<Habit>())) ?? []
        return make(habits: habits, calculator: .fromSettings(), date: date)
    }

    /// Gallery / placeholder content (names from the design canvas).
    public static let sample = HabitWidgetSnapshot(date: .now, items: [
        .init(id: UUID(), name: "Minum air", iconName: "drop", isCount: true, value: 3, target: 8, isDone: false, isSkipped: false),
        .init(id: UUID(), name: "Baca buku", iconName: "book", isCount: false, value: 0, target: 1, isDone: false, isSkipped: false),
        .init(id: UUID(), name: "Belajar Swift", iconName: "chevron.left.forwardslash.chevron.right", isCount: false, value: 0, target: 1, isDone: false, isSkipped: false),
        .init(id: UUID(), name: "Tidur sebelum 23.00", iconName: "moon", isCount: false, value: 0, target: 1, isDone: false, isSkipped: false),
        .init(id: UUID(), name: "Stretching", iconName: "waveform.path.ecg", isCount: false, value: 1, target: 1, isDone: true, isSkipped: false),
        .init(id: UUID(), name: "Rapikan kasur", iconName: "bed.double", isCount: false, value: 1, target: 1, isDone: true, isSkipped: false),
    ])
}

public extension HabitRepository {
    /// Runs a write on one habit for today from outside the app (widget buttons, Siri): opens the
    /// shared store, applies `change`, saves, and reloads the widgets.
    static func perform(onHabit id: UUID, date: Date = .now, _ change: (Habit, Int, ModelContext) -> Void) throws {
        let context = ModelContext(try OrbitData.makeContainer())
        guard let habit = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first else { return }
        change(habit, DayKey.day(date), context)
    }
}
