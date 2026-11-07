import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

struct FinanceDataTests {
    @Test func seedAndBackupRoundTrip() throws {
        let ctx = try freshContext()
        #expect(try CategoryLibrary.seedIfNeeded(ctx) == 18)
        #expect(try CategoryLibrary.seedIfNeeded(ctx) == 0)
        let food = try #require(try ctx.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.name == "category.food" })).first)
        let bca = Wallet(name: "BCA", type: .bank, initialBalance: 1_000_000)
        let gopay = Wallet(name: "GoPay", type: .eWallet, sortOrder: 1)
        [bca, gopay].forEach(ctx.insert)
        let lunch = FinanceTransaction(kind: .expense, amount: 45_000, note: "Makan siang")
        let topUp = FinanceTransaction(kind: .transfer, amount: 300_000)
        [lunch, topUp].forEach(ctx.insert)
        lunch.wallet = gopay; lunch.category = food
        topUp.wallet = bca; topUp.toWallet = gopay
        let budget = Budget(category: food, periodKey: 202611, limit: 1_500_000)
        ctx.insert(budget); budget.category = food
        ctx.insert(RecurringRule(kind: .expense, amount: 150_000, walletID: bca.id, categoryID: food.id,
                                 frequency: .monthly(day: 31), startDate: .now, mode: .auto))
        try ctx.save()

        let data = try BackupService.export(from: freshDefaults(), context: ctx)
        let target = try freshContext()
        try BackupService.restore(BackupService.read(data), into: freshDefaults(), context: target)
        let first = try BackupService.read(data).finance
        let again = try BackupService.read(BackupService.export(from: freshDefaults(), context: target)).finance
        #expect(again.wallets == first.wallets)
        #expect(again.categories == first.categories)
        let byID: (FinanceRecords.TransactionRecord, FinanceRecords.TransactionRecord) -> Bool = { $0.id.uuidString < $1.id.uuidString }
        #expect(again.transactions.sorted(by: byID) == first.transactions.sorted(by: byID))  // dates are whole seconds after a round trip, so ties may reorder
        #expect(again.budgets == first.budgets)
        #expect(again.recurring == first.recurring)
        #expect(first.transactions.count == 2)

        let wallets = try target.fetch(FetchDescriptor<Wallet>())
        let entries = try target.fetch(FetchDescriptor<FinanceTransaction>()).compactMap(\.entry)
        let g = try #require(wallets.first { $0.name == "GoPay" })
        #expect(Ledger.balance(of: g.id, initial: g.initialBalance, entries: entries) == 255_000)
    }

    @Test func oneBudgetPerCategoryAndPeriod() throws {
        let ctx = try freshContext()
        let c = MoneyCategory(name: "X", kind: .expense, iconName: "star")
        ctx.insert(c)
        for limit in [100, 200] as [Int64] {
            let b = Budget(category: c, periodKey: 202611, limit: limit)
            ctx.insert(b); b.category = c
        }
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Budget>()) == 1)
    }

    @Test func migratesV2StoreToV3() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-v3-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let ctx = ModelContext(try OrbitData.makeContainer(at: url, version: OrbitSchemaV2.self))
            ctx.insert(Habit(name: "Baca", iconName: "book"))
            try ProgramPreset.fullBody.install(in: ctx, language: .id)
        }
        let ctx = ModelContext(try OrbitData.makeContainer(at: url, version: OrbitSchemaV3.self))
        #expect(try ctx.fetchCount(FetchDescriptor<Habit>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<RoutineTemplate>()) == 1)
        #expect(try CategoryLibrary.seedIfNeeded(ctx) == 18)
    }
}

struct FinanceRepositoryTests {
    @Test func transferWithFeeAndSummary() throws {
        let ctx = try freshContext()
        try CategoryLibrary.seedIfNeeded(ctx)
        let food = try #require(try ctx.fetch(FetchDescriptor<MoneyCategory>(predicate: #Predicate { $0.name == "category.food" })).first)
        let bca = FinanceRepository.createWallet(name: "BCA", type: .bank, initialBalance: 0, sortOrder: 0, in: ctx)
        let gopay = FinanceRepository.createWallet(name: "GoPay", type: .eWallet, initialBalance: 0, sortOrder: 1, in: ctx)
        let start = Date(timeIntervalSince1970: 0)
        FinanceRepository.add(kind: .income, amount: 5_000_000, wallet: bca, category: nil, date: start, in: ctx)
        let topUp = FinanceRepository.add(kind: .transfer, amount: 300_000, wallet: bca, toWallet: gopay, category: food,
                                          date: start, fee: 1_000, in: ctx)
        FinanceRepository.add(kind: .expense, amount: 18_000, wallet: gopay, category: food, date: start, in: ctx)

        #expect(topUp.category == nil)
        #expect(bca.balance == 4_699_000)
        #expect(gopay.balance == 282_000)

        let all = try ctx.fetch(FetchDescriptor<FinanceTransaction>())
        let summary = PeriodSummary(all, in: DateInterval(start: start, duration: 86_400))
        #expect(summary.income == 5_000_000)
        #expect(summary.expense == 19_000)                  // lunch + admin fee; the transfer itself isn't spending
        #expect(summary.spentByCategory[food.id] == 18_000)

        FinanceRepository.delete(topUp, in: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<FinanceTransaction>()) == 2)  // fee went with it
        #expect(bca.balance == 5_000_000)
    }
}
