import Foundation

public enum MoneyKind: String, CaseIterable, Codable, Sendable {
    case expense, income, transfer
}

/// Budget periods (FIN-05, FIN-10). A period starts on `cycleDay` and is named after the month it
/// starts in: with cycleDay 25, 25 Nov – 24 Dec is `202611`.
public enum Period {
    public static func key(_ date: Date, cycleDay: Int, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var year = c.year!, month = c.month!
        if c.day! < cycleDay {
            month -= 1
            if month == 0 { month = 12; year -= 1 }
        }
        return year * 100 + month
    }

    public static func interval(_ key: Int, cycleDay: Int, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: key / 100, month: key % 100, day: cycleDay))!
        return DateInterval(start: start, end: calendar.date(byAdding: .month, value: 1, to: start)!)
    }

    public static func adding(_ months: Int, to key: Int) -> Int {
        let total = (key / 100) * 12 + (key % 100 - 1) + months
        return (total / 12) * 100 + total % 12 + 1
    }

    /// "Hari ke-7 dari 30": day number of `date` within the period, and the period length.
    public static func day(_ date: Date, in key: Int, cycleDay: Int, calendar: Calendar = .current) -> (day: Int, of: Int) {
        let i = interval(key, cycleDay: cycleDay, calendar: calendar)
        let of = calendar.dateComponents([.day], from: i.start, to: i.end).day!
        let day = calendar.dateComponents([.day], from: i.start, to: calendar.startOfDay(for: date)).day! + 1
        return (min(max(day, 1), of), of)
    }
}

/// FIN-06: compare the share of the budget spent with the share of the period gone.
public enum BudgetStatus: Equatable, Hashable, Sendable {
    case safe
    case warning
    /// Percent over the limit (Lewat 4%).
    case over(percent: Int)

    /// Spending may run 10 points ahead of the calendar before it counts as "Waspada".
    public static let tolerance = 0.10

    public init(spent: Int64, limit: Int64, elapsed: Double) {
        guard limit > 0 else {
            self = spent > 0 ? .over(percent: 100) : .safe
            return
        }
        if spent > limit {
            self = .over(percent: Int((Double(spent - limit) / Double(limit) * 100).rounded(.up)))
        } else {
            self = Double(spent) / Double(limit) > elapsed + Self.tolerance ? .warning : .safe
        }
    }
}

/// One posted transaction, engine-side.
public struct MoneyEntry: Sendable, Equatable {
    public var kind: MoneyKind
    public var amount: Int64
    public var walletID: UUID
    public var toWalletID: UUID?

    public init(kind: MoneyKind, amount: Int64, walletID: UUID, toWalletID: UUID? = nil) {
        self.kind = kind
        self.amount = amount
        self.walletID = walletID
        self.toWalletID = toWalletID
    }
}

public enum Ledger {
    /// Initial balance + income − expense − transfers out + transfers in. May go negative.
    public static func balance(of walletID: UUID, initial: Int64, entries: [MoneyEntry]) -> Int64 {
        entries.reduce(initial) { total, e in
            switch e.kind {
            case .income: e.walletID == walletID ? total + e.amount : total
            case .expense: e.walletID == walletID ? total - e.amount : total
            case .transfer:
                total - (e.walletID == walletID ? e.amount : 0) + (e.toWalletID == walletID ? e.amount : 0)
            }
        }
    }
}

/// FIN-07: when a recurring transaction is due. Monthly days past the month's end clamp to the last day
/// but keep their anchor (31 Jan → 28 Feb → 31 Mar).
public struct Recurrence: Sendable, Equatable {
    public enum Frequency: Sendable, Equatable {
        /// `Calendar` weekday, 1 = Sunday.
        case weekly(weekday: Int)
        case monthly(day: Int)
        case yearly(month: Int, day: Int)
    }

    public var frequency: Frequency

    public init(_ frequency: Frequency) { self.frequency = frequency }

    /// Start of the first due day on or after `date`.
    public func next(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        switch frequency {
        case .weekly(let weekday):
            let offset = (weekday - calendar.component(.weekday, from: day) + 7) % 7
            return calendar.date(byAdding: .day, value: offset, to: day)!
        case .monthly(let dayOfMonth):
            let c = calendar.dateComponents([.year, .month], from: day)
            let here = Self.clamped(year: c.year!, month: c.month!, day: dayOfMonth, calendar)
            if here >= day { return here }
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: here)!
            let n = calendar.dateComponents([.year, .month], from: nextMonth)
            return Self.clamped(year: n.year!, month: n.month!, day: dayOfMonth, calendar)
        case .yearly(let month, let dayOfMonth):
            let year = calendar.component(.year, from: day)
            let here = Self.clamped(year: year, month: month, day: dayOfMonth, calendar)
            return here >= day ? here : Self.clamped(year: year + 1, month: month, day: dayOfMonth, calendar)
        }
    }

    /// Every due day from `nextDue` up to and including `now`, and the due day after them. Running it again
    /// with the returned `next` never repeats a date, so missed months are caught up without duplicates.
    public func due(from nextDue: Date, through now: Date, calendar: Calendar = .current) -> (dates: [Date], next: Date) {
        var dates: [Date] = []
        var d = calendar.startOfDay(for: nextDue)
        while d <= now {
            dates.append(d)
            d = next(onOrAfter: calendar.date(byAdding: .day, value: 1, to: d)!, calendar: calendar)
        }
        return (dates, d)
    }

    private static func clamped(year: Int, month: Int, day: Int, _ calendar: Calendar) -> Date {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let days = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, days)))!
    }
}

/// Money is always shown as rupiah in `id_ID`, whatever the app language.
public enum Rupiah {
    static let locale = Locale(identifier: "id_ID")

    /// "Rp 45.000"; `signed` adds "+" / "−" ("+Rp 3.980.000").
    public static func format(_ amount: Int64, signed: Bool = false) -> String {
        let text = "Rp " + abs(amount).formatted(.number.grouping(.automatic).locale(locale))
        guard signed || amount < 0 else { return text }
        return (amount < 0 ? "−" : "+") + text
    }
}
