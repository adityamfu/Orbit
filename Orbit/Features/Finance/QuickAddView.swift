import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Quick add (DESIGN.md §5.3, canvas p.3): kind, big amount, category grid, wallet / date / note, keypad.
struct QuickAddView: View {
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query(filter: #Predicate<MoneyCategory> { !$0.isArchived }, sort: \MoneyCategory.sortOrder) private var categories: [MoneyCategory]
    @Query private var budgets: [Budget]
    @Query private var transactions: [FinanceTransaction]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.cycleStartDay, store: .orbit) private var cycleDay = SettingsSnapshot.defaults.cycleStartDay

    @State private var kind = MoneyKind.expense
    @State private var digits = ""
    @State private var categoryID: UUID?
    @State private var walletID: UUID?
    @State private var toWalletID: UUID?
    @State private var date = Date.now
    @State private var note = ""
    @State private var fee = ""
    @State private var saved = false

    private var amount: Int64 { Int64(digits) ?? 0 }
    private var wallet: Wallet? { wallets.first { $0.id == walletID } ?? wallets.first }
    private var toWallet: Wallet? { wallets.first { $0.id == toWalletID } ?? wallets.first { $0.id != wallet?.id } }
    private var shownCategories: [MoneyCategory] { categories.filter { $0.kind == kind } }
    private var category: MoneyCategory? { shownCategories.first { $0.id == categoryID } }

    private var canSave: Bool {
        guard amount > 0, wallet != nil else { return false }
        return kind == .transfer ? (toWallet != nil && toWallet?.id != wallet?.id) : category != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("finance.kind", selection: $kind) {
                    Text("finance.kind.expense").tag(MoneyKind.expense)
                    Text("finance.kind.income").tag(MoneyKind.income)
                    Text("finance.kind.transfer").tag(MoneyKind.transfer)
                }
                .pickerStyle(.segmented)

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 4) {
                            Text(verbatim: Rupiah.format(amount))
                                .font(Typography.amountHero)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .contentTransition(.numericText())
                            budgetHint
                                .font(.subheadline)
                                .foregroundStyle(Color.orbit.textSecondary)
                        }
                        .padding(.vertical, 8)

                        if kind == .transfer {
                            transferFields
                        } else {
                            categoryGrid
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // Outside the scroll so wallet / date / note stay visible however many categories there are.
                detailChips

                AmountKeypad(digits: $digits)

                Button(action: save) {
                    Group {
                        switch kind {
                        case .expense: Text("finance.save.expense")
                        case .income: Text("finance.save.income")
                        case .transfer: Text("finance.save.transfer")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.orbitPrimary)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.orbit.bg)
            .navigationTitle(Text("finance.add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
            }
            .onChange(of: kind) { categoryID = nil }
            .sensoryFeedback(.success, trigger: saved)
        }
    }

    // MARK: Parts

    /// "Sisa budget Makan & Minum: Rp 1.035.000"
    @ViewBuilder private var budgetHint: some View {
        let period = Period.key(date, cycleDay: cycleDay)
        if kind == .expense, let category, let budget = budgets.first(where: { $0.categoryID == category.id && $0.periodKey == period }) {
            let spent = PeriodSummary(transactions, in: Period.interval(period, cycleDay: cycleDay)).spentByCategory[category.id] ?? 0
            Text("finance.add.budgetLeft \(category.displayName()) \(Rupiah.format(budget.limit - spent - amount))")
        } else {
            Text(verbatim: " ")
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(shownCategories) { c in
                let on = c.id == categoryID
                Button { categoryID = c.id } label: {
                    VStack(spacing: 6) {
                        Image(systemName: c.iconName).font(.body.weight(.medium))
                        Text(verbatim: c.displayName()).font(.caption.weight(on ? .bold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(on ? Color.orbit.accent : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .padding(.horizontal, 4)
                    .background(on ? Color.orbit.accentSoft : Color.orbit.card, in: .rect(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(on ? Color.orbit.accent : .clear, lineWidth: 2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var transferFields: some View {
        VStack(spacing: 8) {
            HStack {
                walletMenu(selection: $walletID, current: wallet)
                Image(systemName: "arrow.right").foregroundStyle(Color.orbit.textSecondary)
                walletMenu(selection: $toWalletID, current: toWallet)
            }
            HStack {
                Text("finance.transfer.fee").foregroundStyle(Color.orbit.textSecondary)
                TextField(text: $fee) { Text(verbatim: "0") }
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.orbit.card, in: .capsule)
        }
    }

    private var detailChips: some View {
        HStack(spacing: 8) {
            if kind != .transfer { walletMenu(selection: $walletID, current: wallet) }
            DatePicker("finance.add.date", selection: $date, in: ...Date.now.addingTimeInterval(86_400 * 365))
                .labelsHidden()
                .fixedSize()
            TextField("finance.add.note", text: $note)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Color.orbit.card, in: .capsule)
        }
    }

    private func walletMenu(selection: Binding<UUID?>, current: Wallet?) -> some View {
        Menu {
            Picker("finance.wallets", selection: selection) {
                ForEach(wallets) { Text(verbatim: $0.name).tag(Optional($0.id)) }
            }
        } label: {
            Text(verbatim: current?.name ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Color.orbit.card, in: .capsule)
        }
    }

    private func save() {
        guard canSave, let wallet else { return }
        FinanceRepository.add(kind: kind, amount: amount, wallet: wallet, toWallet: toWallet, category: category, date: date,
                              note: note.trimmingCharacters(in: .whitespaces), fee: Int64(fee.filter(\.isNumber)) ?? 0,
                              in: context)
        saved.toggle()
        dismiss()
    }
}

/// 1–9, 000, 0, delete (DESIGN §5.3), with Inter Tight digits.
struct AmountKeypad: View {
    @Binding var digits: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0"], id: \.self) { key in
                Button { type(key) } label: {
                    Text(verbatim: key).font(.custom("InterTight-Bold", size: 26, relativeTo: .title2)).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(KeyStyle(dim: key == "000"))
            }
            Button { digits = String(digits.dropLast()) } label: {
                Image(systemName: "delete.left").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(KeyStyle(dim: true))
            .accessibilityLabel(Text("finance.keypad.delete"))
        }
    }

    private func type(_ key: String) {
        let next = (digits + key).drop { $0 == "0" }
        if next.count <= 12 { digits = String(next) }  // up to Rp 999 miliar
    }

    private struct KeyStyle: ButtonStyle {
        let dim: Bool
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color.primary)
                .background(dim ? Color.orbit.iconTile : Color.orbit.card, in: .rect(cornerRadius: 14, style: .continuous))
                .opacity(configuration.isPressed ? 0.6 : 1)
        }
    }
}

#Preview {
    QuickAddView().modelContainer(OrbitData.makePreviewContainer())
}
