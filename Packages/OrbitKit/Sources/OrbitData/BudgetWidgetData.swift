import Foundation
import SwiftData
import OrbitEngine

/// Widget kinds for finance.
public extension WidgetKinds {
    static let budget = "BudgetWidget"
}

/// One category's budget status for the widget list.
public struct BudgetWidgetItem: Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var spent: Int64
    public var limit: Int64
    public var status: BudgetStatus

    public var remaining: Int64 { limit - spent }
    public var isOver: Bool {
        switch status {
        case .over: true
        default: false
        }
    }
}

/// Everything the budget widget shows for the current period.
public struct BudgetWidgetSnapshot: Sendable {
    public var periodKey: Int
    public var totalLimit: Int64
    public var totalSpent: Int64
    public var totalRemaining: Int64 { totalLimit - totalSpent }
    public var items: [BudgetWidgetItem]

    public var overallStatus: BudgetStatus {
        BudgetStatus(spent: totalSpent, limit: totalLimit, elapsed: 1)
    }

    public init(periodKey: Int, totalLimit: Int64, totalSpent: Int64, items: [BudgetWidgetItem]) {
        self.periodKey = periodKey
        self.totalLimit = totalLimit
        self.totalSpent = totalSpent
        self.items = items
    }

    /// Reads the shared store (used by the widget extension).
    public static func load(date: Date = .now, cycleDay: Int = SettingsSnapshot(from: .orbit).cycleStartDay) -> BudgetWidgetSnapshot {
        let periodKey = Period.key(date, cycleDay: cycleDay)
        let interval = Period.interval(periodKey, cycleDay: cycleDay)

        guard let container = try? OrbitData.makeContainer() else {
            return BudgetWidgetSnapshot(periodKey: periodKey, totalLimit: 0, totalSpent: 0, items: [])
        }
        let context = ModelContext(container)

        let transactions = (try? context.fetch(FetchDescriptor<FinanceTransaction>())) ?? []
        let summary = PeriodSummary(transactions, in: interval)

        let budgets = ((try? context.fetch(FetchDescriptor<Budget>())) ?? [])
            .filter { $0.periodKey == periodKey }
        let categories = (try? context.fetch(FetchDescriptor<MoneyCategory>())) ?? []
        let catsByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let today = Period.day(date, in: periodKey, cycleDay: cycleDay)
        let elapsed = Double(today.day) / Double(today.of)

        var items: [BudgetWidgetItem] = []
        for budget in budgets {
            guard let cat = catsByID[budget.categoryID] else { continue }
            let spent = summary.spentByCategory[budget.categoryID] ?? 0
            items.append(BudgetWidgetItem(
                id: cat.id,
                name: cat.displayName(),
                spent: spent,
                limit: budget.limit,
                status: BudgetStatus(spent: spent, limit: budget.limit, elapsed: elapsed)
            ))
        }
        items.sort { $0.spent > $1.spent }

        let totalLimit = items.map(\.limit).reduce(0, +)
        let totalSpent = items.map(\.spent).reduce(0, +)

        return BudgetWidgetSnapshot(periodKey: periodKey, totalLimit: totalLimit, totalSpent: totalSpent, items: items)
    }

    /// Gallery / placeholder content (names from the design canvas).
    public static let sample = BudgetWidgetSnapshot(
        periodKey: 202611,
        totalLimit: 5_000_000,
        totalSpent: 3_200_000,
        items: [
            BudgetWidgetItem(id: UUID(), name: "Makan & Minum", spent: 1_200_000, limit: 1_500_000, status: .safe),
            BudgetWidgetItem(id: UUID(), name: "Transportasi", spent: 380_000, limit: 400_000, status: .warning),
            BudgetWidgetItem(id: UUID(), name: "Tagihan & Utilitas", spent: 700_000, limit: 600_000, status: .over(percent: 17)),
        ]
    )
}
