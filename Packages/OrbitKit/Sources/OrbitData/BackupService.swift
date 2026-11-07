import Foundation
import SwiftData

/// The whole backup file. Each phase adds its data here and bumps `currentSchemaVersion`.
/// Older files stay importable: missing arrays decode as empty.
public struct Backup: Codable, Equatable, Sendable {
    /// 1 = settings only (Phase 1). 2 = + habits and logs (Phase 2).
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var exportedAt: Date
    public var settings: SettingsSnapshot
    public var habits: [HabitRecord]

    public init(schemaVersion: Int = Backup.currentSchemaVersion, exportedAt: Date, settings: SettingsSnapshot,
                habits: [HabitRecord] = []) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.habits = habits
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        settings = try c.decode(SettingsSnapshot.self, forKey: .settings)
        habits = try c.decodeIfPresent([HabitRecord].self, forKey: .habits) ?? []
    }
}

/// A habit with its logs, exactly as stored.
public struct HabitRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var name: String
    public var iconName: String
    public var typeRaw: String
    public var targetCount: Int
    public var unit: String
    public var scheduleRaw: String
    public var scheduleWeekdays: [Int]
    public var timesPerWeek: Int?
    public var everyNDays: Int?
    public var reminderMinutes: [Int]
    public var startDate: Date
    public var sortOrder: Int
    public var isArchived: Bool
    public var logs: [LogRecord]

    public struct LogRecord: Codable, Equatable, Sendable {
        public var dayKey: Int
        public var value: Int
        public var isSkipped: Bool
        public var loggedAt: Date
    }
}

public enum BackupError: Error, Equatable {
    /// The file was made by a newer Orbit build than this one.
    case newerSchema(Int)
}

public enum BackupService {
    public static func export(from defaults: UserDefaults, context: ModelContext, now: Date = .now) throws -> Data {
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)]))
        let backup = Backup(exportedAt: now, settings: SettingsSnapshot(from: defaults), habits: habits.map(record))
        return try encoder.encode(backup)
    }

    /// Parses and validates without touching anything, so the UI can confirm before replacing.
    public static func read(_ data: Data) throws -> Backup {
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.schemaVersion <= Backup.currentSchemaVersion else {
            throw BackupError.newerSchema(backup.schemaVersion)
        }
        return backup
    }

    /// "Replace all" import (SET-06): wipes every habit, then recreates everything from the file.
    /// On failure nothing is kept: the context is rolled back and settings are untouched.
    public static func restore(_ backup: Backup, into defaults: UserDefaults, context: ModelContext) throws {
        do {
            try replaceAll(with: backup, in: context)
        } catch {
            context.rollback()
            throw error
        }
        backup.settings.write(to: defaults)
    }

    private static func replaceAll(with backup: Backup, in context: ModelContext) throws {
        try context.delete(model: HabitLog.self)
        try context.delete(model: Habit.self)
        for r in backup.habits {
            let habit = Habit(id: r.id, name: r.name, iconName: r.iconName, startDate: r.startDate,
                              sortOrder: r.sortOrder, isArchived: r.isArchived, createdAt: r.createdAt)
            habit.updatedAt = r.updatedAt
            habit.typeRaw = r.typeRaw
            habit.targetCount = r.targetCount
            habit.unit = r.unit
            habit.scheduleRaw = r.scheduleRaw
            habit.scheduleWeekdays = r.scheduleWeekdays
            habit.timesPerWeek = r.timesPerWeek
            habit.everyNDays = r.everyNDays
            habit.reminderMinutes = r.reminderMinutes
            context.insert(habit)
            for l in r.logs {
                let log = HabitLog(habit: habit, dayKey: l.dayKey, value: l.value, isSkipped: l.isSkipped, loggedAt: l.loggedAt)
                context.insert(log)
                log.habit = habit
            }
        }
        try context.save()
    }

    public static func fileName(for date: Date = .now) -> String {
        "Orbit-backup-\(date.formatted(.iso8601.year().month().day()))"
    }

    private static func record(_ h: Habit) -> HabitRecord {
        HabitRecord(
            id: h.id, createdAt: h.createdAt, updatedAt: h.updatedAt, name: h.name, iconName: h.iconName,
            typeRaw: h.typeRaw, targetCount: h.targetCount, unit: h.unit, scheduleRaw: h.scheduleRaw,
            scheduleWeekdays: h.scheduleWeekdays, timesPerWeek: h.timesPerWeek, everyNDays: h.everyNDays,
            reminderMinutes: h.reminderMinutes, startDate: h.startDate, sortOrder: h.sortOrder, isArchived: h.isArchived,
            logs: h.logs.sorted { $0.dayKey < $1.dayKey }.map {
                .init(dayKey: $0.dayKey, value: $0.value, isSkipped: $0.isSkipped, loggedAt: $0.loggedAt)
            }
        )
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
