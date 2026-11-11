import Foundation
import SwiftData
import OrbitEngine

/// Finance writes. Each one saves right away (widgets read the store from another process).
public enum FinanceRepository {
    /// FIN-02 / FIN-03: a transfer with `fee > 0` also books a "Biaya Admin" expense on the source wallet.
    @discardableResult
    public static func add(kind: MoneyKind, amount: Int64, wallet: Wallet, toWallet: Wallet? = nil,
                           category: MoneyCategory?, date: Date = .now, note: String = "", fee: Int64 = 0,
                           in context: ModelContext) -> FinanceTransaction {
        let t = FinanceTransaction(kind: kind, amount: amount, date: date, note: note)
        context.insert(t)
        t.wallet = wallet
        t.toWallet = kind == .transfer ? toWallet : nil
        t.category = kind == .transfer ? nil : category
        if kind == .transfer, fee > 0 {
            let feeCategory = try? context.fetch(FetchDescriptor<MoneyCategory>(
                predicate: #Predicate { $0.name == "category.adminFee" && $0.isDefault })).first
            let f = FinanceTransaction(kind: .expense, amount: fee, date: date)
            context.insert(f)
            f.wallet = wallet
            f.category = feeCategory
            t.linkedFeeID = f.id
        }
        save(context)
        return t
    }

    /// Removes a transaction and its admin fee, if any.
    public static func delete(_ t: FinanceTransaction, in context: ModelContext) {
        if let feeID = t.linkedFeeID,
           let fee = try? context.fetch(FetchDescriptor<FinanceTransaction>(predicate: #Predicate { $0.id == feeID })).first {
            context.delete(fee)
        }
        context.delete(t)
        save(context)
    }

    @discardableResult
    public static func createWallet(name: String, type: WalletType, initialBalance: Int64, sortOrder: Int,
                                    in context: ModelContext) -> Wallet {
        let w = Wallet(name: name, type: type, initialBalance: initialBalance, sortOrder: sortOrder)
        context.insert(w)
        save(context)
        return w
    }

    /// Used wallets are archived, never deleted (CLAUDE.md data rule).
    public static func setArchived(_ archived: Bool, _ wallet: Wallet) {
        wallet.isArchived = archived
        wallet.updatedAt = .now
        wallet.modelContext.map(save)
    }

    /// Used categories are archived, never deleted (CLAUDE.md data rule).
    public static func setArchived(_ archived: Bool, _ category: MoneyCategory) {
        category.isArchived = archived
        category.updatedAt = .now
        category.modelContext.map(save)
    }

    /// FIN-04: create a custom category.
    @discardableResult
    public static func createCategory(name: String, kind: MoneyKind, iconName: String, sortOrder: Int,
                                      in context: ModelContext) -> MoneyCategory {
        let c = MoneyCategory(name: name, kind: kind, iconName: iconName, isDefault: false, sortOrder: sortOrder)
        context.insert(c)
        save(context)
        return c
    }

    public static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Saving finance failed: \(error)")
        }
    }
}

/// Totals for one budget period (summary card, budgets).
public struct PeriodSummary: Equatable, Sendable {
    public var income: Int64 = 0
    public var expense: Int64 = 0
    /// Expense per category id.
    public var spentByCategory: [UUID: Int64] = [:]

    public var net: Int64 { income - expense }

    /// Transfers move money between wallets and don't count as income or expense.
    public init(_ transactions: [FinanceTransaction], in interval: DateInterval) {
        for t in transactions where interval.contains(t.date) && t.date < interval.end {
            switch t.kind {
            case .income: income += t.amount
            case .expense:
                expense += t.amount
                if let id = t.category?.id { spentByCategory[id, default: 0] += t.amount }
            case .transfer: break
            }
        }
    }
}

public extension Wallet {
    /// Balance from every transaction touching this wallet (FIN-01).
    var balance: Int64 {
        Ledger.balance(of: id, initial: initialBalance, entries: (transactions + incomingTransfers).compactMap(\.entry))
    }
}
