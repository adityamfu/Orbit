import Foundation
import SwiftData
import OrbitEngine

/// V3 (Phase 4): adds finance. Habit and workout models are unchanged and reused.
/// Money is `Int64` rupiah everywhere.
public enum OrbitSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        OrbitSchemaV2.models + [Wallet.self, MoneyCategory.self, FinanceTransaction.self, Budget.self, RecurringRule.self]
    }

    @Model
    public final class Wallet {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var name: String
        public var typeRaw: String
        public var iconName: String
        public var initialBalance: Int64
        public var sortOrder: Int
        public var isArchived: Bool
        @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.wallet)
        public var transactions: [FinanceTransaction] = []
        @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.toWallet)
        public var incomingTransfers: [FinanceTransaction] = []

        public init(id: UUID = UUID(), name: String, type: WalletType, iconName: String? = nil, initialBalance: Int64 = 0,
                    sortOrder: Int = 0, isArchived: Bool = false, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.name = name
            self.typeRaw = type.rawValue
            self.iconName = iconName ?? type.defaultIcon
            self.initialBalance = initialBalance
            self.sortOrder = sortOrder
            self.isArchived = isArchived
        }
    }

    @Model
    public final class MoneyCategory {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        /// Built-in: catalog key ("category.food"). Custom: the user's text.
        public var name: String
        public var kindRaw: String
        public var iconName: String
        public var isDefault: Bool
        public var sortOrder: Int
        public var isArchived: Bool
        @Relationship(deleteRule: .nullify, inverse: \FinanceTransaction.category)
        public var transactions: [FinanceTransaction] = []
        @Relationship(deleteRule: .cascade, inverse: \Budget.category)
        public var budgets: [Budget] = []

        public init(id: UUID = UUID(), name: String, kind: MoneyKind, iconName: String, isDefault: Bool = false,
                    sortOrder: Int = 0, isArchived: Bool = false, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.name = name
            self.kindRaw = kind.rawValue
            self.iconName = iconName
            self.isDefault = isDefault
            self.sortOrder = sortOrder
            self.isArchived = isArchived
        }
    }

    @Model
    public final class FinanceTransaction {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var kindRaw: String
        /// Always positive; `kind` says which way it moves.
        public var amount: Int64
        public var date: Date
        public var note: String
        public var wallet: Wallet?
        /// Transfers only.
        public var toWallet: Wallet?
        /// nil for transfers.
        public var category: MoneyCategory?
        public var recurringRuleID: UUID?
        /// FIN-03: the "Biaya Admin" expense created with a transfer.
        public var linkedFeeID: UUID?

        public init(id: UUID = UUID(), kind: MoneyKind, amount: Int64, date: Date = .now, note: String = "",
                    recurringRuleID: UUID? = nil, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.kindRaw = kind.rawValue
            self.amount = amount
            self.date = date
            self.note = note
            self.recurringRuleID = recurringRuleID
        }
    }

    @Model
    public final class Budget {
        // One budget per category per period. Uses categoryID (an attribute) because uniqueness
        // constraints can't include relationships.
        #Unique<Budget>([\.categoryID, \.periodKey])

        public var id: UUID
        public var category: MoneyCategory?
        public var categoryID: UUID
        /// `yyyyMM`, following the cycle day (OrbitEngine `Period`).
        public var periodKey: Int
        public var limit: Int64

        public init(id: UUID = UUID(), category: MoneyCategory, periodKey: Int, limit: Int64) {
            self.id = id
            self.categoryID = category.id
            self.periodKey = periodKey
            self.limit = limit
        }
    }

    /// Template + schedule. Wallets and category are kept as ids: the rule only copies them into
    /// the transactions it posts.
    @Model
    public final class RecurringRule {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        public var kindRaw: String
        public var amount: Int64
        public var walletID: UUID
        public var toWalletID: UUID?
        public var categoryID: UUID?
        public var note: String
        public var frequencyRaw: String
        public var dayOfMonth: Int?
        public var weekday: Int?
        public var month: Int?
        public var startDate: Date
        public var endDate: Date?
        public var nextDueDate: Date
        public var modeRaw: String
        public var isActive: Bool

        public init(id: UUID = UUID(), kind: MoneyKind, amount: Int64, walletID: UUID, toWalletID: UUID? = nil,
                    categoryID: UUID?, note: String = "", frequency: Recurrence.Frequency, startDate: Date,
                    endDate: Date? = nil, mode: RecurringMode = .confirm, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.kindRaw = kind.rawValue
            self.amount = amount
            self.walletID = walletID
            self.toWalletID = toWalletID
            self.categoryID = categoryID
            self.note = note
            self.frequencyRaw = ""
            self.startDate = startDate
            self.endDate = endDate
            self.nextDueDate = startDate
            self.modeRaw = mode.rawValue
            self.isActive = true
            self.frequency = frequency
            self.nextDueDate = Recurrence(frequency).next(onOrAfter: startDate)
        }
    }
}

public typealias Wallet = OrbitSchemaV3.Wallet
public typealias FinanceTransaction = OrbitSchemaV3.FinanceTransaction
public typealias MoneyCategory = OrbitSchemaV3.MoneyCategory
public typealias Budget = OrbitSchemaV3.Budget
public typealias RecurringRule = OrbitSchemaV3.RecurringRule

public enum WalletType: String, CaseIterable, Codable, Sendable {
    case cash, bank, eWallet, other

    public var defaultIcon: String {
        switch self {
        case .cash: "banknote"
        case .bank: "building.columns"
        case .eWallet: "iphone"
        case .other: "wallet.bifold"
        }
    }
}

public enum RecurringMode: String, Codable, Sendable {
    /// Posted as soon as it's due.
    case auto
    /// Shown as a card (and a notification) to confirm or skip.
    case confirm
}

public extension Wallet {
    var type: WalletType { WalletType(rawValue: typeRaw) ?? .other }
}

public extension MoneyCategory {
    var kind: MoneyKind { MoneyKind(rawValue: kindRaw) ?? .expense }

    /// Built-ins translate their key; custom categories show what the user typed.
    func displayName(language: AppLanguage? = nil) -> String {
        isDefault ? L10n.string(key: name, language: language) : name
    }
}

public extension FinanceTransaction {
    var kind: MoneyKind { MoneyKind(rawValue: kindRaw) ?? .expense }

    var entry: MoneyEntry? {
        wallet.map { MoneyEntry(kind: kind, amount: amount, walletID: $0.id, toWalletID: toWallet?.id) }
    }
}

public extension RecurringRule {
    var kind: MoneyKind { MoneyKind(rawValue: kindRaw) ?? .expense }
    var mode: RecurringMode { RecurringMode(rawValue: modeRaw) ?? .confirm }

    var frequency: Recurrence.Frequency {
        get {
            switch frequencyRaw {
            case "weekly": .weekly(weekday: weekday ?? 2)
            case "yearly": .yearly(month: month ?? 1, day: dayOfMonth ?? 1)
            default: .monthly(day: dayOfMonth ?? 1)
            }
        }
        set {
            weekday = nil
            month = nil
            dayOfMonth = nil
            switch newValue {
            case .weekly(let w): frequencyRaw = "weekly"; weekday = w
            case .monthly(let d): frequencyRaw = "monthly"; dayOfMonth = d
            case .yearly(let m, let d): frequencyRaw = "yearly"; month = m; dayOfMonth = d
            }
        }
    }
}

/// Built-in categories (FIN-04). Names are catalog keys so they follow the app language.
public enum CategoryLibrary {
    static let expense: [(String, String)] = [
        ("category.food", "fork.knife"), ("category.transport", "car"), ("category.shopping", "bag"),
        ("category.bills", "bolt"), ("category.rent", "house"), ("category.internet", "wifi"),
        ("category.subscriptions", "arrow.triangle.2.circlepath"), ("category.entertainment", "play.rectangle"),
        ("category.health", "cross.case"), ("category.education", "book"), ("category.charity", "heart"),
        (adminFee, "building.columns"), ("category.otherExpense", "ellipsis"),
    ]
    static let income: [(String, String)] = [
        ("category.salary", "banknote"), ("category.freelance", "laptopcomputer"), ("category.bonus", "star"),
        ("category.gift", "gift"), ("category.otherIncome", "ellipsis"),
    ]
    /// FIN-03: transfer fees are booked here.
    public static let adminFee = "category.adminFee"

    /// Adds any built-in category not in the store yet. Safe to call on every launch.
    @discardableResult
    public static func seedIfNeeded(_ context: ModelContext) throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.isDefault })).map(\.name))
        var added = 0
        for (kind, list) in [(MoneyKind.expense, expense), (.income, income)] {
            for (order, (key, icon)) in list.enumerated() where !existing.contains(key) {
                context.insert(MoneyCategory(name: key, kind: kind, iconName: icon, isDefault: true, sortOrder: order))
                added += 1
            }
        }
        if added > 0 { try context.save() }
        return added
    }
}
