import Foundation
import Testing
@testable import OrbitEngine

struct FinanceTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    @Test func periodKeysFollowCycleDay() {
        #expect(Period.key(d(2026, 11, 7), cycleDay: 1, calendar: cal) == 202611)
        #expect(Period.key(d(2026, 11, 24), cycleDay: 25, calendar: cal) == 202610)
        #expect(Period.key(d(2026, 11, 25), cycleDay: 25, calendar: cal) == 202611)
        #expect(Period.key(d(2026, 1, 3), cycleDay: 25, calendar: cal) == 202512)   // crosses the year
        #expect(Period.adding(1, to: 202612) == 202701)
        #expect(Period.adding(-1, to: 202601) == 202512)
        let i = Period.interval(202611, cycleDay: 25, calendar: cal)
        #expect(i.start == d(2026, 11, 25, 0))
        #expect(i.end == d(2026, 12, 25, 0))
        #expect(Period.day(d(2026, 11, 7), in: 202611, cycleDay: 1, calendar: cal) == (7, 30))
    }

    @Test func budgetPacing() {
        // Day 7 of 30 ≈ 23% gone (canvas p.4).
        let elapsed = 7.0 / 30
        #expect(BudgetStatus(spent: 420_000, limit: 1_500_000, elapsed: elapsed) == .safe)     // 28%
        #expect(BudgetStatus(spent: 180_000, limit: 400_000, elapsed: elapsed) == .warning)   // 45%
        #expect(BudgetStatus(spent: 260_000, limit: 250_000, elapsed: elapsed) == .over(percent: 4))
        #expect(BudgetStatus(spent: 0, limit: 0, elapsed: elapsed) == .safe)
    }

    @Test func walletBalance() {
        let bca = UUID(), gopay = UUID()
        let entries = [
            MoneyEntry(kind: .income, amount: 5_000_000, walletID: bca),
            MoneyEntry(kind: .expense, amount: 18_000, walletID: gopay),
            MoneyEntry(kind: .transfer, amount: 300_000, walletID: bca, toWalletID: gopay),
            MoneyEntry(kind: .expense, amount: 1_000, walletID: bca),  // transfer fee
        ]
        #expect(Ledger.balance(of: bca, initial: 0, entries: entries) == 4_699_000)
        #expect(Ledger.balance(of: gopay, initial: 200_000, entries: entries) == 482_000)
        #expect(Ledger.balance(of: gopay, initial: 0, entries: [MoneyEntry(kind: .expense, amount: 5, walletID: gopay)]) == -5)
    }

    @Test func monthlyClampsAndKeepsAnchor() {
        let r = Recurrence(.monthly(day: 31))
        let due = r.due(from: d(2026, 1, 31), through: d(2026, 4, 1), calendar: cal)
        #expect(due.dates.map { cal.component(.day, from: $0) } == [31, 28, 31])  // Jan, Feb, Mar
        #expect(due.next == d(2026, 4, 30, 0))
        // Catching up again from `next` adds nothing new.
        #expect(r.due(from: due.next, through: d(2026, 4, 1), calendar: cal).dates.isEmpty)
        #expect(r.next(onOrAfter: d(2026, 11, 7), calendar: cal) == d(2026, 11, 30, 0))
    }

    @Test func weeklyAndYearly() {
        // Saturday 7 Nov 2026; weekly on Monday (2).
        #expect(Recurrence(.weekly(weekday: 2)).next(onOrAfter: d(2026, 11, 7), calendar: cal) == d(2026, 11, 9, 0))
        #expect(Recurrence(.weekly(weekday: 7)).next(onOrAfter: d(2026, 11, 7), calendar: cal) == d(2026, 11, 7, 0))
        let yearly = Recurrence(.yearly(month: 2, day: 29))
        #expect(yearly.next(onOrAfter: d(2026, 11, 7), calendar: cal) == d(2027, 2, 28, 0))
        #expect(yearly.due(from: d(2027, 2, 28), through: d(2029, 3, 1), calendar: cal).dates.count == 3)
    }

    @Test func rupiah() {
        #expect(Rupiah.format(45_000) == "Rp 45.000")
        #expect(Rupiah.format(3_980_000, signed: true) == "+Rp 3.980.000")
        #expect(Rupiah.format(-50_000) == "−Rp 50.000")
    }
}
