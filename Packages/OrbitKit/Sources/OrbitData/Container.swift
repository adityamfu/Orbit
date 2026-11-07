import Foundation
import SwiftData
import OrbitEngine

public extension OrbitData {
    /// The single store shared by app and widgets (App Group). Named "Orbit" so it never opens
    /// the Phase 0 spike store (default.store) still sitting on the device.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: OrbitSchemaCurrent.self)
        let config = inMemory
            ? ModelConfiguration("Orbit", schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration("Orbit", schema: schema, groupContainer: .identifier(appGroup))
        return try ModelContainer(for: schema, migrationPlan: OrbitMigrationPlan.self, configurations: config)
    }

    /// A container at a given file and schema version; tests use it to check migrations.
    static func makeContainer(at url: URL, version: any VersionedSchema.Type) throws -> ModelContainer {
        let schema = Schema(versionedSchema: version)
        return try ModelContainer(for: schema, migrationPlan: OrbitMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, url: url))
    }

    /// In-memory container with the habits from the design canvas, for `#Preview`.
    @MainActor
    static func makePreviewContainer() -> ModelContainer {
        let container = try! makeContainer(inMemory: true)
        PreviewData.insert(into: container.mainContext)
        return container
    }
}

@MainActor
enum PreviewData {
    static func insert(into context: ModelContext, today: Date = .now, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: .day, value: -60, to: today)!
        func habit(_ name: String, _ icon: String, _ order: Int, type: HabitType = .check, target: Int = 1,
                   unit: String = "", schedule: HabitRule.Schedule = .daily, reminders: [Int] = []) -> Habit {
            let h = Habit(name: name, iconName: icon, type: type, targetCount: target, unit: unit,
                          schedule: schedule, reminderMinutes: reminders, startDate: start, sortOrder: order)
            context.insert(h)
            return h
        }
        let water = habit("Minum air", "drop", 0, type: .count, target: 8, unit: "gelas")
        let stretch = habit("Stretching pagi", "waveform.path.ecg", 1)
        let bed = habit("Rapikan kasur", "bed.double", 2)
        let read = habit("Baca buku 20 mnt", "book", 3, reminders: [21 * 60])
        let swift = habit("Belajar Swift 30 mnt", "chevron.left.forwardslash.chevron.right", 4,
                          schedule: .weekdays([2, 3, 4, 5, 6, 7]))
        let sleep = habit("Tidur sebelum 23.00", "moon", 5, reminders: [22 * 60 + 15])
        let cook = habit("Masak sendiri", "frying.pan", 6, schedule: .timesPerWeek(3))

        // (habit, value, days ago) — a believable history: some streaks, some gaps.
        func log(_ h: Habit, _ value: Int, _ daysAgo: ClosedRange<Int>, every step: Int = 1) {
            for ago in stride(from: daysAgo.lowerBound, through: daysAgo.upperBound, by: step) {
                let day = DayKey.day(calendar.date(byAdding: .day, value: -ago, to: today)!, calendar: calendar)
                let entry = HabitLog(habit: h, dayKey: day, value: value)
                context.insert(entry)
                entry.habit = h
            }
        }
        log(water, 3, 0...0)
        log(water, 8, 1...20)
        log(stretch, 1, 0...11)
        log(bed, 1, 0...30)
        log(read, 1, 1...8)
        log(swift, 1, 1...6)
        log(sleep, 1, 3...20, every: 2)
        log(cook, 1, 1...28, every: 3)
    }
}
