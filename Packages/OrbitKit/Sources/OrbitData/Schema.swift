import Foundation
import SwiftData
import OrbitEngine

// Every @Model change needs a new VersionedSchema + a stage in OrbitMigrationPlan (CLAUDE.md rule 5).

public enum OrbitSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { [Habit.self, HabitLog.self] }

    @Model
    public final class Habit {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var name: String
        /// SF Symbol name.
        public var iconName: String
        public var typeRaw: String
        /// Value per day to count as done (1 for check habits).
        public var targetCount: Int
        /// Count habits only, e.g. "gelas".
        public var unit: String
        public var scheduleRaw: String
        public var scheduleWeekdays: [Int]
        public var timesPerWeek: Int?
        public var everyNDays: Int?
        /// Minutes after midnight, e.g. 21:00 = 1260.
        public var reminderMinutes: [Int]
        public var startDate: Date
        public var sortOrder: Int
        public var isArchived: Bool
        @Relationship(deleteRule: .cascade, inverse: \HabitLog.habit)
        public var logs: [HabitLog] = []

        public init(
            id: UUID = UUID(),
            name: String,
            iconName: String,
            type: HabitType = .check,
            targetCount: Int = 1,
            unit: String = "",
            schedule: HabitRule.Schedule = .daily,
            reminderMinutes: [Int] = [],
            startDate: Date = .now,
            sortOrder: Int = 0,
            isArchived: Bool = false,
            createdAt: Date = .now
        ) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.name = name
            self.iconName = iconName
            self.typeRaw = type.rawValue
            self.targetCount = type == .check ? 1 : max(targetCount, 1)
            self.unit = unit
            self.scheduleRaw = ScheduleKind.daily.rawValue
            self.scheduleWeekdays = []
            self.reminderMinutes = reminderMinutes
            self.startDate = startDate
            self.sortOrder = sortOrder
            self.isArchived = isArchived
            self.schedule = schedule
        }
    }

    @Model
    public final class HabitLog {
        // One log per habit per day. Uses habitID (an attribute) because uniqueness
        // constraints can't include relationships.
        #Unique<HabitLog>([\.habitID, \.dayKey])

        public var id: UUID
        public var habitID: UUID
        public var habit: Habit?
        /// `yyyyMMdd`.
        public var dayKey: Int
        public var value: Int
        public var isSkipped: Bool
        public var loggedAt: Date

        public init(habit: Habit, dayKey: Int, value: Int, isSkipped: Bool = false, loggedAt: Date = .now) {
            self.id = UUID()
            self.habitID = habit.id
            self.dayKey = dayKey
            self.value = value
            self.isSkipped = isSkipped
            self.loggedAt = loggedAt
        }
    }
}

public enum OrbitMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [OrbitSchemaV1.self, OrbitSchemaV2.self] }
    /// V1 → V2 only adds workout models, so SwiftData can migrate on its own.
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: OrbitSchemaV1.self, toVersion: OrbitSchemaV2.self)]
    }
}

/// The schema the app runs on today.
public typealias OrbitSchemaCurrent = OrbitSchemaV2

public typealias Habit = OrbitSchemaV1.Habit
public typealias HabitLog = OrbitSchemaV1.HabitLog

public enum HabitType: String, CaseIterable, Codable, Sendable {
    case check, count
}

enum ScheduleKind: String {
    case daily, weekdays, timesPerWeek, everyNDays
}

public extension Habit {
    var type: HabitType {
        get { HabitType(rawValue: typeRaw) ?? .check }
        set { typeRaw = newValue.rawValue }
    }

    var schedule: HabitRule.Schedule {
        get {
            switch ScheduleKind(rawValue: scheduleRaw) ?? .daily {
            case .daily: .daily
            case .weekdays: .weekdays(Set(scheduleWeekdays))
            case .timesPerWeek: .timesPerWeek(timesPerWeek ?? 1)
            case .everyNDays: .everyNDays(everyNDays ?? 1)
            }
        }
        set {
            scheduleWeekdays = []
            timesPerWeek = nil
            everyNDays = nil
            switch newValue {
            case .daily:
                scheduleRaw = ScheduleKind.daily.rawValue
            case .weekdays(let days):
                scheduleRaw = ScheduleKind.weekdays.rawValue
                scheduleWeekdays = days.sorted()
            case .timesPerWeek(let n):
                scheduleRaw = ScheduleKind.timesPerWeek.rawValue
                timesPerWeek = n
            case .everyNDays(let n):
                scheduleRaw = ScheduleKind.everyNDays.rawValue
                everyNDays = n
            }
        }
    }

    /// Engine view of this habit.
    func rule(calendar: Calendar = .current) -> HabitRule {
        HabitRule(schedule: schedule, target: targetCount, startDay: DayKey.day(startDate, calendar: calendar))
    }

    /// Logs keyed by day for the engine.
    var dayLogs: [Int: HabitDay] {
        Dictionary(logs.map { ($0.dayKey, HabitDay(value: $0.value, isSkipped: $0.isSkipped)) }) { first, _ in first }
    }

    func log(on day: Int) -> HabitLog? {
        logs.first { $0.dayKey == day }
    }
}

public extension HabitCalculator {
    /// Calculator using the user's "first day of week" setting.
    static func fromSettings(_ defaults: UserDefaults = .orbit, calendar: Calendar = .current) -> HabitCalculator {
        HabitCalculator(calendar: calendar, firstWeekday: SettingsSnapshot(from: defaults).firstWeekday)
    }
}
