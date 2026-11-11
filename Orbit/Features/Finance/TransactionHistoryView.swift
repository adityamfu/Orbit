import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Transaction history with search and filters (FIN-09).
struct TransactionHistoryView: View {
    @Query(sort: \FinanceTransaction.date, order: .reverse) private var allTransactions: [FinanceTransaction]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query(filter: #Predicate<MoneyCategory> { !$0.isArchived }, sort: \MoneyCategory.sortOrder) private var categories: [MoneyCategory]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var search = ""
    /// `"expense"`, `"income"`, `"transfer"`, or `nil` for all. Matches `kindRaw` in the store.
    @State private var kindFilter: String? = nil
    @State private var walletFilter: UUID? = nil
    @State private var categoryFilter: UUID? = nil
    @State private var dateFrom: Date? = nil
    @State private var dateThru: Date? = nil

    private var filtered: [FinanceTransaction] {
        allTransactions.filter { t in
            if !search.isEmpty {
                let haystack = (t.note + " " + (t.category?.displayName() ?? "") + " " + (t.wallet?.name ?? "") + " " + (t.toWallet?.name ?? "")).lowercased()
                if !haystack.contains(search.lowercased()) { return false }
            }
            if let kindFilter, t.kindRaw != kindFilter { return false }
            if let walletFilter, t.wallet?.id != walletFilter { return false }
            if let categoryFilter, t.category?.id != categoryFilter { return false }
            if let from = dateFrom, t.date < from { return false }
            if let thru = dateThru, t.date > thru { return false }
            return true
        }
    }

    var body: some View {
        List {
            ScreenHeader(Text("finance.history.title"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            Section {
                TextField("finance.history.search", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("finance.history.filter.type", selection: $kindFilter) {
                    Text("finance.history.filter.all").tag(Optional<String>.none)
                    Text("finance.history.filter.expense").tag(Optional<String>.some("expense"))
                    Text("finance.history.filter.income").tag(Optional<String>.some("income"))
                    Text("finance.history.filter.transfer").tag(Optional<String>.some("transfer"))
                }
                .pickerStyle(.segmented)
                Picker("finance.history.filter.wallet", selection: $walletFilter) {
                    Text("finance.history.filter.all").tag(Optional<UUID>.none)
                    ForEach(wallets) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                }
                Picker("finance.history.filter.category", selection: $categoryFilter) {
                    Text("finance.history.filter.all").tag(Optional<UUID>.none)
                    ForEach(categories) { Text(verbatim: $0.displayName()).tag(Optional($0.id)) }
                }
                DatePicker("finance.history.filter.from", selection: Binding(
                    get: { dateFrom ?? .distantPast }, set: { dateFrom = $0 == .distantPast ? nil : $0 }),
                           displayedComponents: .date)
                DatePicker("finance.history.filter.to", selection: Binding(
                    get: { dateThru ?? .distantFuture }, set: { dateThru = $0 == .distantFuture ? nil : $0 }),
                           displayedComponents: .date)
            }

            if filtered.isEmpty {
                emptyState
            } else {
                ForEach(days(grouped: filtered), id: \.key) { day, items in
                    Text(dayTitle(day))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.orbit.textSecondary)
                        .textCase(.uppercase)
                        .padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(items) { t in
                            TransactionRow(transaction: t,
                                           fee: t.linkedFeeID.flatMap { feeMap[$0] })
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
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Day-keyed groups for the list; newest first.
    private func days(grouped: [FinanceTransaction]) -> [(key: Date, items: [FinanceTransaction])] {
        Dictionary(grouping: grouped) { Calendar.current.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (key: $0.key, items: $0.value) }
    }

    private var feeMap: [UUID: Int64] {
        let feeIDs = Set(allTransactions.compactMap(\.linkedFeeID))
        let fees = allTransactions.filter { feeIDs.contains($0.id) }
        return Dictionary(uniqueKeysWithValues: fees.map { ($0.id, $0.amount) })
    }

    private func dayTitle(_ day: Date) -> String {
        Calendar.current.isDateInToday(day)
            ? locale.localized("finance.today")
            : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("finance.history.empty", systemImage: "clock")
        } description: {
            Text("finance.history.empty.description")
        } actions: {
            Button("finance.history.empty.action") { }
                .buttonStyle(.orbitPrimary)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview("History") {
    NavigationStack { TransactionHistoryView() }
        .modelContainer(OrbitData.makePreviewContainer())
}
