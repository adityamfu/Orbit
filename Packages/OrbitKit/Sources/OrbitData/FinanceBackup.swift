import Foundation
import SwiftData

/// Everything finance-related in a backup (schema v4+). Links between records use ids.
public struct FinanceRecords: Codable, Equatable, Sendable {
    public var wallets: [WalletRecord] = []
    public var categories: [CategoryRecord] = []
    public var transactions: [TransactionRecord] = []
    public var budgets: [BudgetRecord] = []
    public var recurring: [RecurringRecord] = []

    public init() {}

    public struct WalletRecord: Codable, Equatable, Sendable {
        var id: UUID, createdAt: Date, updatedAt: Date, name: String, typeRaw: String, iconName: String
        var initialBalance: Int64, sortOrder: Int, isArchived: Bool
    }

    public struct CategoryRecord: Codable, Equatable, Sendable {
        var id: UUID, createdAt: Date, updatedAt: Date, name: String, kindRaw: String, iconName: String
        var isDefault: Bool, sortOrder: Int, isArchived: Bool
    }

    public struct TransactionRecord: Codable, Equatable, Sendable {
        var id: UUID, createdAt: Date, updatedAt: Date, kindRaw: String, amount: Int64, date: Date, note: String
        var walletID: UUID?, toWalletID: UUID?, categoryID: UUID?, recurringRuleID: UUID?, linkedFeeID: UUID?
    }

    public struct BudgetRecord: Codable, Equatable, Sendable {
        var categoryID: UUID, periodKey: Int, limit: Int64
    }

    public struct RecurringRecord: Codable, Equatable, Sendable {
        var id: UUID, createdAt: Date, updatedAt: Date, kindRaw: String, amount: Int64, walletID: UUID
        var toWalletID: UUID?, categoryID: UUID?, note: String, frequencyRaw: String, dayOfMonth: Int?
        var weekday: Int?, month: Int?, startDate: Date, endDate: Date?, nextDueDate: Date, modeRaw: String, isActive: Bool
    }
}

extension FinanceRecords {
    init(context: ModelContext) throws {
        wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: [SortDescriptor(\.sortOrder)])).map {
            WalletRecord(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, name: $0.name, typeRaw: $0.typeRaw,
                         iconName: $0.iconName, initialBalance: $0.initialBalance, sortOrder: $0.sortOrder, isArchived: $0.isArchived)
        }
        categories = try context.fetch(FetchDescriptor<MoneyCategory>(sortBy: [SortDescriptor(\.kindRaw), SortDescriptor(\.sortOrder), SortDescriptor(\.name)])).map {
            CategoryRecord(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, name: $0.name, kindRaw: $0.kindRaw,
                           iconName: $0.iconName, isDefault: $0.isDefault, sortOrder: $0.sortOrder, isArchived: $0.isArchived)
        }
        transactions = try context.fetch(FetchDescriptor<FinanceTransaction>()).sorted { $0.date < $1.date }.map {
            TransactionRecord(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, kindRaw: $0.kindRaw, amount: $0.amount,
                              date: $0.date, note: $0.note, walletID: $0.wallet?.id, toWalletID: $0.toWallet?.id,
                              categoryID: $0.category?.id, recurringRuleID: $0.recurringRuleID, linkedFeeID: $0.linkedFeeID)
        }
        budgets = try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.periodKey)])).map {
            BudgetRecord(categoryID: $0.categoryID, periodKey: $0.periodKey, limit: $0.limit)
        }
        recurring = try context.fetch(FetchDescriptor<RecurringRule>()).map {
            RecurringRecord(id: $0.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt, kindRaw: $0.kindRaw, amount: $0.amount,
                            walletID: $0.walletID, toWalletID: $0.toWalletID, categoryID: $0.categoryID, note: $0.note,
                            frequencyRaw: $0.frequencyRaw, dayOfMonth: $0.dayOfMonth, weekday: $0.weekday, month: $0.month,
                            startDate: $0.startDate, endDate: $0.endDate, nextDueDate: $0.nextDueDate, modeRaw: $0.modeRaw,
                            isActive: $0.isActive)
        }
    }

    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: Budget.self)
        try context.delete(model: FinanceTransaction.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: MoneyCategory.self)
        try context.delete(model: Wallet.self)
    }

    func insert(into context: ModelContext) {
        var walletsByID: [UUID: Wallet] = [:]
        for r in wallets {
            let w = Wallet(id: r.id, name: r.name, type: WalletType(rawValue: r.typeRaw) ?? .other, iconName: r.iconName,
                           initialBalance: r.initialBalance, sortOrder: r.sortOrder, isArchived: r.isArchived, createdAt: r.createdAt)
            w.updatedAt = r.updatedAt
            context.insert(w)
            walletsByID[r.id] = w
        }
        var categoriesByID: [UUID: MoneyCategory] = [:]
        for r in categories {
            let c = MoneyCategory(id: r.id, name: r.name, kind: .expense, iconName: r.iconName, isDefault: r.isDefault,
                             sortOrder: r.sortOrder, isArchived: r.isArchived, createdAt: r.createdAt)
            c.kindRaw = r.kindRaw
            c.updatedAt = r.updatedAt
            context.insert(c)
            categoriesByID[r.id] = c
        }
        for r in transactions {
            let t = FinanceTransaction(id: r.id, kind: .expense, amount: r.amount, date: r.date, note: r.note,
                                       recurringRuleID: r.recurringRuleID, createdAt: r.createdAt)
            t.kindRaw = r.kindRaw
            t.updatedAt = r.updatedAt
            t.linkedFeeID = r.linkedFeeID
            context.insert(t)
            t.wallet = r.walletID.flatMap { walletsByID[$0] }
            t.toWallet = r.toWalletID.flatMap { walletsByID[$0] }
            t.category = r.categoryID.flatMap { categoriesByID[$0] }
        }
        for r in budgets {
            guard let category = categoriesByID[r.categoryID] else { continue }
            let b = Budget(category: category, periodKey: r.periodKey, limit: r.limit)
            context.insert(b)
            b.category = category
        }
        for r in recurring {
            let rule = RecurringRule(id: r.id, kind: .expense, amount: r.amount, walletID: r.walletID, toWalletID: r.toWalletID,
                                     categoryID: r.categoryID, note: r.note, frequency: .monthly(day: 1), startDate: r.startDate,
                                     endDate: r.endDate, createdAt: r.createdAt)
            rule.kindRaw = r.kindRaw
            rule.updatedAt = r.updatedAt
            rule.frequencyRaw = r.frequencyRaw
            rule.dayOfMonth = r.dayOfMonth
            rule.weekday = r.weekday
            rule.month = r.month
            rule.nextDueDate = r.nextDueDate
            rule.modeRaw = r.modeRaw
            rule.isActive = r.isActive
            context.insert(rule)
        }
    }
}
