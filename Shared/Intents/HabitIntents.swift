// Target membership: Orbit + OrbitWidgetsExtension (via the Shared folder).
// Widget buttons run these in the widget process; they write to the shared store directly.
import AppIntents
import OrbitData

/// Check / uncheck a habit for today (count habits: reach target ↔ reset).
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.habit.toggle"
    static let isDiscoverable = false

    @Parameter(title: "intent.habit.parameter")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: habitID) {
            try HabitRepository.perform(onHabit: id) { habit, day, context in
                HabitRepository.toggle(habit, day: day, in: context)
            }
        }
        return .result()
    }
}

/// +1 on a count habit for today.
struct IncrementHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.habit.increment"
    static let isDiscoverable = false

    @Parameter(title: "intent.habit.parameter")
    var habitID: String

    init() {}

    init(habitID: UUID) {
        self.habitID = habitID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: habitID) {
            try HabitRepository.perform(onHabit: id) { habit, day, context in
                HabitRepository.increment(habit, day: day, in: context)
            }
        }
        return .result()
    }
}
