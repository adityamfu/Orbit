import SwiftData
import SwiftUI
import Charts
import OrbitData
import OrbitEngine
import OrbitUI

/// Monthly report (FIN-08): income vs expense, net, category donut, 6-month trend, wallet balances.
struct MonthlyReportView: View {
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query private var budgets: [Budget]
    @Query(filter: #Predicate<MoneyCategory> { !$0.isArchived }, sort: \MoneyCategory.sortOrder) private var categories: [MoneyCategory]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.cycleStartDay, store: .orbit) private var cycleDay = SettingsSnapshot.defaults.cycleStartDay

    @State private var period = Period.key(.now, cycleDay: SettingsSnapshot(from: .orbit).cycleStartDay)

    var body: some View {
        let interval = Period.interval(period, cycleDay: cycleDay)
        let summary = PeriodSummary(transactions, in: interval)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(Text("finance.report.title")) {
                    HStack(spacing: 8) {
                        financeArrow("chevron.left", by: -1)
                        Text(verbatim: periodTitle).font(.headline)
                        financeArrow("chevron.right", by: 1)
                            .disabled(period >= Period.key(.now, cycleDay: cycleDay))
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                // Income / expense / net cards.
                HStack(spacing: 10) {
                    StatTile(icon: "arrow.down.app.fill", label: "finance.report.income",
                             value: Rupiah.format(summary.income, signed: true),
                             color: Color.orbit.accent)
                    StatTile(icon: "arrow.up.app.fill", label: "finance.report.expense",
                             value: Rupiah.format(-summary.expense), color: Color.primary)
                    StatTile(icon: "minus", label: "finance.report.net",
                             value: Rupiah.format(summary.net, signed: summary.net != 0),
                             color: summary.net >= 0 ? Color.orbit.accent : Color.red)
                }

                // Category donut (expenses only).
                if !summary.spentByCategory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("finance.report.byCategory").font(Typography.section)
                        CategoryDonut(spentByCategory: summary.spentByCategory,
                                      categories: categories, locale: locale)
                    }
                    .padding(16)
                    .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                }

                // 6-month trend.
                VStack(alignment: .leading, spacing: 8) {
                    Text("finance.report.trend").font(Typography.section)
                    TrendChart(transactions: transactions, period: period, cycleDay: cycleDay, locale: locale)
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))

                // Wallet balances.
                VStack(alignment: .leading, spacing: 8) {
                    Text("finance.report.wallets").font(Typography.section)
                    if wallets.isEmpty {
                        Text("finance.report.noWallets")
                            .font(.subheadline)
                            .foregroundStyle(Color.orbit.textSecondary)
                    } else {
                        ForEach(wallets) { wallet in
                            HStack {
                                Image(systemName: wallet.type.defaultIcon)
                                    .foregroundStyle(Color.orbit.iconTint)
                                    .frame(width: 32, height: 32)
                                    .background(Color.orbit.iconTile, in: .circle)
                                    .accessibilityHidden(true)
                                Text(verbatim: wallet.name).font(.body.weight(.medium))
                                Spacer()
                                Text(verbatim: Rupiah.format(wallet.balance))
                                    .font(Typography.metric)
                                    .foregroundStyle(wallet.balance < 0 ? Color.red : Color.primary)
                            }
                            .padding(.vertical, 6)
                            if wallet.id != wallets.last?.id { Divider().padding(.leading, 52) }
                        }
                    }
                }
                .padding(16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
            .padding(16)
        }
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodTitle: String {
        let i = Period.interval(period, cycleDay: cycleDay)
        if cycleDay == 1 {
            return i.start.formatted(.dateTime.month(.wide).year().locale(locale))
        }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: i.end)!
        return "\(i.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(last.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
    }

    private func financeArrow(_ icon: String, by months: Int) -> some View {
        Button { period = Period.adding(months, to: period) } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .circle)
        }
        .buttonStyle(.plain)
    }
}

/// Small stat card: icon, label, value, color.
private struct StatTile: View {
    let icon: String
    let label: LocalizedStringKey
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orbit.textSecondary)
            Text(label).font(.caption).foregroundStyle(Color.orbit.textSecondary)
            Text(verbatim: value).font(Typography.metric).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orbit.card, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

/// Donut of expense by category (SectorMark).
private struct CategoryDonut: View {
    let spentByCategory: [UUID: Int64]
    let categories: [MoneyCategory]
    let locale: Locale

    private var data: [(category: MoneyCategory, amount: Int64)] {
        spentByCategory
            .compactMap { (id, amount) in
                categories.first { $0.id == id }.map { ($0, amount) }
            }
            .sorted { $0.amount > $1.amount }
    }

    private var total: Int64 { data.map(\.amount).reduce(0, +) }

    var body: some View {
        Chart(data, id: \.category.id) { item in
            SectorMark(
                angle: .value("Amount", item.amount),
                innerRadius: .ratio(0.55),
                outerRadius: 110
            )
            .foregroundStyle(by: .value("Category", item.category.displayName()))
        }
        .chartLegend(position: .bottom, alignment: .center, spacing: 12)
        .frame(height: 220)
        .accessibilityLabel(Text("finance.report.byCategory"))
        .accessibilityValue(Text(verbatim: "\(data.count) categories, \(Rupiah.format(total)) total"))
    }
}

/// 6-month trend: income vs expense per month (BarMark).
private struct TrendChart: View {
    let transactions: [FinanceTransaction]
    let period: Int
    let cycleDay: Int
    let locale: Locale

    private var months: [Int] {
        (0..<6).reversed().map { Period.adding(-$0, to: period) }
    }

    private var data: [(month: Int, income: Int64, expense: Int64)] {
        months.map { key in
            let interval = Period.interval(key, cycleDay: cycleDay)
            let filtered = transactions.filter { interval.contains($0.date) && $0.date < interval.end }
            let income = filtered.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
            let expense = filtered.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
            return (key, income, expense)
        }
    }

    var body: some View {
        Chart {
            ForEach(data, id: \.month) { item in
                BarMark(
                    x: .value("Month", monthLabel(item.month)),
                    y: .value("Income", item.income)
                )
                .foregroundStyle(Color.orbit.accent)
                BarMark(
                    x: .value("Month", monthLabel(item.month)),
                    y: .value("Expense", item.expense)
                )
                .foregroundStyle(Color.primary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).locale(locale))
            }
        }
        .frame(height: 180)
        .accessibilityLabel(Text("finance.report.trend"))
    }

    private func monthLabel(_ key: Int) -> Date {
        let interval = Period.interval(key, cycleDay: cycleDay)
        return interval.start
    }
}

#Preview("Report") {
    NavigationStack { MonthlyReportView() }
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty, English") {
    NavigationStack { MonthlyReportView() }
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
        .environment(\.locale, Locale(identifier: "en_US"))
}
