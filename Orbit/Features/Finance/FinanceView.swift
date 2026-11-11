import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Finance tab (DESIGN.md §5.2, canvas p.4).
struct FinanceView: View {
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    // ponytail: loads every transaction; fine for one person's data, fetch per period if it ever feels slow.
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var transactions: [FinanceTransaction]
    @Query private var budgets: [Budget]
    @Query(sort: \RecurringRule.startDate) private var allRecurringRules: [RecurringRule]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.cycleStartDay, store: .orbit) private var cycleDay = SettingsSnapshot.defaults.cycleStartDay

    @State private var period = Period.key(.now, cycleDay: SettingsSnapshot(from: .orbit).cycleStartDay)
    @State private var showAdd = false
    @State private var showNewWallet = false
    @State private var showWallets = false
    @State private var showCategories = false
    @State private var showHistory = false
    @State private var showRecurring = false
    @State private var showReport = false
    @State private var recurringDue: [RecurringRule] = []
    @State private var editingBudget: Budget?

    var body: some View {
        let interval = Period.interval(period, cycleDay: cycleDay)
        let summary = PeriodSummary(transactions, in: interval)
        let recurringRules = allRecurringRules.filter { $0.isActive }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(Text("tab.finance")) {
                        HStack(spacing: 8) {
                            RoundAddButton(label: Text("finance.add")) {
                                if wallets.isEmpty { showNewWallet = true } else { showAdd = true }
                            }
                            financeAction("finance.wallets.title", "wallet.bifold") { showWallets = true }
                            financeAction("finance.categories.title", "folder") { showCategories = true }
                            financeAction("finance.history.title", "clock") { showHistory = true }
                            financeAction("finance.recurring.title", "repeat") { showRecurring = true }
                            financeAction("finance.report.title", "chart.pie") { showReport = true }
                        }
                    }

                    SummaryCard(period: $period, cycleDay: cycleDay, summary: summary)

                    if !recurringDue.isEmpty {
                        recurringDueCard
                    }

                    if wallets.isEmpty {
                        ContentUnavailableView {
                            Label("finance.empty.title", systemImage: "wallet.bifold")
                        } description: {
                            Text("finance.empty.description")
                        } actions: {
                            Button("finance.wallet.add") { showNewWallet = true }.buttonStyle(.orbitPrimary)
                        }
                    } else {
                        walletsSection
                        budgetSection(summary: summary)
                        transactionsSection(in: interval)
                    }
                }
                .padding(16)
            }
            .background(Color.orbit.bg)
            .navigationTitle(Text("tab.finance"))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) { QuickAddView().presentationDetents([.large]) }
            .sheet(isPresented: $showNewWallet) { WalletFormView(wallet: nil, nextSortOrder: wallets.count) }
            .sheet(isPresented: $showWallets) { NavigationStack { WalletListView() } }
            .sheet(isPresented: $showCategories) { NavigationStack { CategoryListView() } }
            .sheet(isPresented: $showHistory) { NavigationStack { TransactionHistoryView() } }
            .sheet(isPresented: $showRecurring) { NavigationStack { RecurringRuleListView() } }
            .sheet(isPresented: $showReport) { NavigationStack { MonthlyReportView() } }
            .sheet(item: $editingBudget) { budget in BudgetEditView(budget: budget) }
            .task {
                recurringDue = FinanceRepository.postRecurringRules(in: context)
            }
            .onChange(of: cycleDay) { _, day in period = Period.key(.now, cycleDay: day) }
        }
    }

    private func financeAction(_ key: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(key))
    }

    /// Confirmation card for recurring rules in confirm mode whose due date has passed (FIN-07).
    private var recurringDueCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("finance.recurring.due.title").font(.headline)
                Spacer()
                Button("common.done") {
                    recurringDue = []
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orbit.accent)
            }
            ForEach(recurringDue) { rule in
                HStack(spacing: 10) {
                    Image(systemName: "repeat")
                        .foregroundStyle(Color.orbit.iconTint)
                        .frame(width: 32, height: 32)
                        .background(Color.orbit.iconTile, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: rule.note.isEmpty ? "finance.recurring.unnamed" : rule.note)
                            .font(.body.weight(.medium))
                        Text(verbatim: "\(Rupiah.format(rule.amount)) · \(modeText(rule))")
                            .font(.caption)
                            .foregroundStyle(Color.orbit.textSecondary)
                    }
                    Spacer()
                    Button("finance.recurring.post") {
                        postRule(rule)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orbit.accent)
                    Button("finance.recurring.skip") {
                        skipRule(rule)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orbit.textSecondary)
                }
                .padding(10)
                .background(Color.orbit.card, in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 4)
    }

    private func modeText(_ rule: RecurringRule) -> String {
        rule.mode == .auto
            ? String(localized: "finance.recurring.mode.auto", defaultValue: "Auto")
            : String(localized: "finance.recurring.mode.confirm", defaultValue: "Confirm")
    }

    private func postRule(_ rule: RecurringRule) {
        FinanceRepository.postRecurringRules(in: context)
        recurringDue = FinanceRepository.postRecurringRules(in: context)
    }

    private func skipRule(_ rule: RecurringRule) {
        let recurrence = Recurrence(rule.frequency)
        let (_, next) = recurrence.due(from: rule.nextDueDate, through: .now)
        rule.nextDueDate = next
        rule.updatedAt = .now
        FinanceRepository.save(context)
        recurringDue = FinanceRepository.postRecurringRules(in: context)
    }

    // MARK: Sections

    private var walletsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("finance.wallets").font(Typography.section)
                Spacer()
                Text("finance.wallets.total \(Rupiah.format(wallets.reduce(0) { $0 + $1.balance }))")
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            .padding(.top, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(wallets) { WalletCard(wallet: $0) }
                    Button { showNewWallet = true } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 64, height: 88)
                            .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("finance.wallet.add"))
                }
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func budgetSection(summary: PeriodSummary) -> some View {
        let current = budgets.filter { $0.periodKey == period && $0.category != nil }
            .sorted { $0.category!.sortOrder < $1.category!.sortOrder }
        if !current.isEmpty {
            let today = Period.day(.now, in: period, cycleDay: cycleDay)
            let thisPeriod = period == Period.key(.now, cycleDay: cycleDay)
            let elapsed = thisPeriod ? Double(today.day) / Double(today.of) : (period < Period.key(.now, cycleDay: cycleDay) ? 1 : 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("finance.budget").font(Typography.section)
                    Spacer()
                    if thisPeriod {
                        Text("finance.budget.day \(today.day) \(today.of)")
                            .font(.subheadline)
                            .foregroundStyle(Color.orbit.textSecondary)
                    }
                }
                .padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(current) { budget in
                        BudgetRow(budget: budget, spent: summary.spentByCategory[budget.categoryID] ?? 0,
                                  elapsed: elapsed, showMarker: thisPeriod) {
                            editingBudget = budget
                        }
                        if budget.id != current.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                if thisPeriod {
                    Text("finance.budget.markerHint").font(.caption).foregroundStyle(Color.orbit.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func transactionsSection(in interval: DateInterval) -> some View {
        // Admin fees are shown inside their transfer's row, not on their own.
        let feeIDs = Set(transactions.compactMap(\.linkedFeeID))
        let shown = transactions.filter { interval.contains($0.date) && $0.date < interval.end && !feeIDs.contains($0.id) }
        let fees = Dictionary(transactions.filter { feeIDs.contains($0.id) }.map { ($0.id, $0.amount) }) { a, _ in a }
        let days = Dictionary(grouping: shown.prefix(30)) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }

        VStack(alignment: .leading, spacing: 8) {
            Text("finance.recent").font(Typography.section).padding(.top, 12)
            if shown.isEmpty {
                Text("finance.recent.empty")
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
            ForEach(days, id: \.key) { day, items in
                Text(dayTitle(day))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.orbit.textSecondary)
                    .textCase(.uppercase)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(items) { t in
                        TransactionRow(transaction: t, fee: t.linkedFeeID.flatMap { fees[$0] })
                            .contextMenu {
                                Button("finance.transaction.delete", systemImage: "trash", role: .destructive) {
                                    FinanceRepository.delete(t, in: context)
                                }
                            }
                        if t.id != items.last?.id { Divider().padding(.leading, 52) }
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        Calendar.current.isDateInToday(day)
            ? locale.localized("finance.today")
            : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
    }
}

/// Black card in both modes (DESIGN §5.2 ✨): month selector, net flow, income vs expense bar.
private struct SummaryCard: View {
    @Binding var period: Int
    let cycleDay: Int
    let summary: PeriodSummary
    @Environment(\.locale) private var locale

    var body: some View {
        let total = max(summary.income + summary.expense, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                arrow("chevron.left", label: "habit.calendar.previous", by: -1)
                Spacer()
                Text(verbatim: title).font(.headline)
                Spacer()
                arrow("chevron.right", label: "habit.calendar.next", by: 1)
                    .disabled(period >= Period.key(.now, cycleDay: cycleDay))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("finance.summary.net").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                Text(verbatim: Rupiah.format(summary.net, signed: summary.net != 0))
                    .font(Typography.amountHero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            GeometryReader { geo in
                if summary.income + summary.expense == 0 {
                    Capsule().fill(.white.opacity(0.15))
                } else {
                    HStack(spacing: 4) {
                        Capsule().fill(.white).frame(width: max(4, (geo.size.width - 4) * CGFloat(summary.income) / CGFloat(total)))
                        Capsule().fill(Color.orbit.primary)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            HStack(alignment: .top) {
                amount("finance.summary.income", summary.income, color: .white)
                Spacer()
                amount("finance.summary.expense", summary.expense, color: Color.orbit.primary)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Color.orbit.ink, in: .rect(cornerRadius: 28, style: .continuous))
    }

    private var title: String {
        let i = Period.interval(period, cycleDay: cycleDay)
        if cycleDay == 1 { return i.start.formatted(.dateTime.month(.wide).year().locale(locale)) }
        let last = Calendar.current.date(byAdding: .day, value: -1, to: i.end)!
        return "\(i.start.formatted(.dateTime.day().month(.abbreviated).locale(locale))) – \(last.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
    }

    private func arrow(_ icon: String, label: LocalizedStringKey, by months: Int) -> some View {
        Button { period = Period.adding(months, to: period) } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func amount(_ title: LocalizedStringKey, _ value: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Text(verbatim: Rupiah.format(value)).font(Typography.metric).foregroundStyle(color)
        }
    }
}

private struct WalletCard: View {
    let wallet: Wallet

    var body: some View {
        let balance = wallet.balance
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: wallet.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orbit.textSecondary)
                .lineLimit(1)
            Text(verbatim: Rupiah.format(balance))
                .font(Typography.metric)
                .foregroundStyle(balance < 0 ? Color.red : Color.primary)  // FIN-01: negative balances are flagged
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 140, height: 56, alignment: .leading)
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// FIN-06: name, status chip, bar with a "today" tick, spent / limit.
struct BudgetRow: View {
    let budget: Budget
    let spent: Int64
    let elapsed: Double
    let showMarker: Bool
    let onEdit: () -> Void

    var body: some View {
        let status = BudgetStatus(spent: spent, limit: budget.limit, elapsed: elapsed)
        let fraction = budget.limit > 0 ? min(Double(spent) / Double(budget.limit), 1) : 1
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: budget.category?.displayName() ?? "").font(.body.weight(.medium))
                Spacer()
                StatusChip(status: status)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.orbit.track)
                    Capsule().fill(status == .safe ? Color.primary : Color.orbit.accent)
                        .frame(width: geo.size.width * fraction)
                    if showMarker {
                        Rectangle().fill(Color.orbit.textSecondary).frame(width: 2, height: 12)
                            .offset(x: geo.size.width * elapsed - 1)
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(verbatim: "\(Rupiah.format(spent)) / \(Rupiah.format(budget.limit))")
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct StatusChip: View {
    let status: BudgetStatus

    var body: some View {
        Group {
            switch status {
            case .safe:
                Text("finance.budget.safe").foregroundStyle(Color.primary)
                    .background(Color.orbit.iconTile, in: .capsule)
            case .warning:
                Text("finance.budget.warning").foregroundStyle(Color.orbit.accent)
                    .overlay(Capsule().strokeBorder(Color.orbit.accent, lineWidth: 1.5))
            case .over(let percent):
                Text("finance.budget.over \(percent)").foregroundStyle(Color.orbit.onAccent)
                    .background(Color.orbit.accent, in: .capsule)
            }
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .fixedSize()
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    /// Admin fee booked with this transfer.
    let fee: Int64?
    @Environment(\.locale) private var locale

    var body: some View {
        let t = transaction
        HStack(spacing: 12) {
            Image(systemName: t.kind == .transfer ? "arrow.left.arrow.right" : t.category?.iconName ?? "circle")
                .foregroundStyle(Color.orbit.iconTint)
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body.weight(.medium)).lineLimit(1)
                Text(verbatim: subtitle).font(.subheadline).foregroundStyle(Color.orbit.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: amountText)
                .font(Typography.metric)
                .fixedSize()
                .foregroundStyle(t.kind == .income ? Color.orbit.accent : t.kind == .transfer ? Color.orbit.textSecondary : Color.primary)
        }
        .padding(.vertical, 10)
    }

    private var title: String {
        if !transaction.note.isEmpty { return transaction.note }
        if transaction.kind == .transfer { return locale.localized("finance.kind.transfer") }
        return transaction.category?.displayName() ?? ""
    }

    private var subtitle: String {
        let t = transaction
        if t.kind == .transfer {
            let route = "\(t.wallet?.name ?? "?") → \(t.toWallet?.name ?? "?")"
            return fee.map { "\(route) · \(locale.localized("finance.transfer.feeShort \(Rupiah.format($0))"))" } ?? route
        }
        return [t.note.isEmpty ? nil : t.category?.displayName(), t.wallet?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private var amountText: String {
        switch transaction.kind {
        case .expense: Rupiah.format(-transaction.amount)
        case .income: Rupiah.format(transaction.amount, signed: true)
        case .transfer: Rupiah.format(transaction.amount)
        }
    }
}

#Preview("Finance") {
    FinanceView().modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty") {
    FinanceView().modelContainer(try! OrbitData.makeContainer(inMemory: true))
}
