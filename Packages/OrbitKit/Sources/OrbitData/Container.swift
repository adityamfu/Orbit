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
        PreviewData.insertFinance(into: container.mainContext)
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

        // Workouts: the PPL program and a few finished sessions with progress on bench press.
        guard let routines = try? ProgramPreset.pushPullLegs.install(in: context, language: .id),
              let push = routines.first, let legs = routines.last else { return }
        func session(_ routine: RoutineTemplate, daysAgo: Int, minutes: Int, weight: Double, reps: Int) {
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let s = WorkoutSession(startedAt: start, template: routine)
            s.endedAt = start.addingTimeInterval(TimeInterval(minutes * 60))
            context.insert(s)
            for (order, item) in routine.orderedItems.enumerated() {
                guard let exercise = item.exercise else { continue }
                for index in 0..<item.targetSets {
                    let set = WorkoutSet(exercise: exercise, exerciseOrder: order, setIndex: index, reps: reps,
                                         weightKg: order == 0 ? weight : 20, isCompleted: true, completedAt: start)
                    context.insert(set)
                    s.sets.append(set)
                }
            }
        }
        session(push, daysAgo: 9, minutes: 62, weight: 57.5, reps: 12)
        session(legs, daysAgo: 5, minutes: 58, weight: 90, reps: 10)
        session(push, daysAgo: 2, minutes: 60, weight: 60, reps: 12)
    }

    /// Wallets, a budget and a few transactions like canvas p.4.
    static func insertFinance(into context: ModelContext, today: Date = .now) {
        try? CategoryLibrary.seedIfNeeded(context)
        let cats = Dictionary(((try? context.fetch(FetchDescriptor<MoneyCategory>())) ?? []).map { ($0.name, $0) }) { a, _ in a }
        let bca = FinanceRepository.createWallet(name: "BCA", type: .bank, initialBalance: 0, sortOrder: 0, in: context)
        let gopay = FinanceRepository.createWallet(name: "GoPay", type: .eWallet, initialBalance: 200_000, sortOrder: 1, in: context)
        let cash = FinanceRepository.createWallet(name: "Tunai", type: .cash, initialBalance: 850_000, sortOrder: 2, in: context)
        let ago = { (days: Double) in today.addingTimeInterval(-86_400 * days) }
        FinanceRepository.add(kind: .income, amount: 5_000_000, wallet: bca, category: cats["category.freelance"], date: ago(2),
                              note: "Proyek landing page", in: context)
        FinanceRepository.add(kind: .transfer, amount: 300_000, wallet: bca, toWallet: gopay, category: nil, date: ago(2),
                              note: "Isi saldo GoPay", fee: 1_000, in: context)
        FinanceRepository.add(kind: .expense, amount: 50_000, wallet: cash, category: cats["category.transport"], note: "Bensin", in: context)
        FinanceRepository.add(kind: .expense, amount: 18_000, wallet: gopay, category: cats["category.food"], note: "Sarapan", in: context)
        let period = Period.key(today, cycleDay: 1)
        for (key, limit) in [("category.food", 1_500_000), ("category.transport", 400_000)] as [(String, Int64)] {
            guard let cat = cats[key] else { continue }
            let b = Budget(category: cat, periodKey: period, limit: limit)
            context.insert(b)
            b.category = cat
        }
    }
}

