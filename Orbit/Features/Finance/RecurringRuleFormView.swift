import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Add or edit a recurring rule (FIN-07). Pass a rule to edit; nil to create.
struct RecurringRuleFormView: View {
    let rule: RecurringRule?
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query(filter: #Predicate<MoneyCategory> { !$0.isArchived }, sort: \MoneyCategory.sortOrder) private var categories: [MoneyCategory]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MoneyKind
    @State private var amount = ""
    @State private var walletID: UUID?
    @State private var toWalletID: UUID?
    @State private var categoryID: UUID?
    @State private var frequency: Frequency
    @State private var dayOfMonth: Int
    @State private var weekday: Int
    @State private var yearMonth: Int
    @State private var yearDay: Int
    @State private var startDate: Date
    @State private var endDate: Date?
    @State private var hasEndDate = false
    @State private var mode: RecurringMode
    @State private var note = ""

    enum Frequency: CaseIterable, Identifiable {
        case monthly, weekly, yearly
        var id: Int { hashValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .monthly: "finance.recurring.freq.monthly"
            case .weekly: "finance.recurring.freq.weekly"
            case .yearly: "finance.recurring.freq.yearly"
            }
        }
    }

    init(rule: RecurringRule?) {
        self.rule = rule
        _kind = State(initialValue: rule?.kind ?? .expense)
        _amount = State(initialValue: rule.map { String($0.amount) } ?? "")
        _walletID = State(initialValue: rule?.walletID)
        _toWalletID = State(initialValue: rule?.toWalletID)
        _categoryID = State(initialValue: rule?.categoryID)
        _frequency = State(initialValue: .monthly)
        _dayOfMonth = State(initialValue: 1)
        _weekday = State(initialValue: 2)
        _yearMonth = State(initialValue: 1)
        _yearDay = State(initialValue: 1)
        let freq = rule?.frequency ?? .monthly(day: 1)
        switch freq {
        case .monthly(let d): _dayOfMonth = State(initialValue: d)
        case .weekly(let w): _frequency = State(initialValue: .weekly); _weekday = State(initialValue: w)
        case .yearly(let m, let d): _frequency = State(initialValue: .yearly); _yearMonth = State(initialValue: m); _yearDay = State(initialValue: d)
        }
        _startDate = State(initialValue: rule?.startDate ?? .now)
        _endDate = State(initialValue: rule?.endDate)
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _mode = State(initialValue: rule?.mode ?? .confirm)
        _note = State(initialValue: rule?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("finance.recurring.section.template") {
                    Picker("finance.recurring.kind", selection: $kind) {
                        Text("finance.kind.expense").tag(MoneyKind.expense)
                        Text("finance.kind.income").tag(MoneyKind.income)
                        Text("finance.kind.transfer").tag(MoneyKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    TextField("finance.recurring.amount", text: $amount)
                        .keyboardType(.numberPad)
                }

                Section("finance.recurring.section.accounts") {
                    if kind == .transfer {
                        HStack {
                            Text("finance.recurring.from")
                            Spacer()
                            walletMenu(selection: $walletID, label: walletName(for: walletID))
                        }
                        HStack {
                            Text("finance.recurring.to")
                            Spacer()
                            walletMenu(selection: $toWalletID, label: walletName(for: toWalletID))
                        }
                    } else {
                        HStack {
                            Text("finance.recurring.wallet")
                            Spacer()
                            walletMenu(selection: $walletID, label: walletName(for: walletID))
                        }
                        Picker("finance.recurring.category", selection: $categoryID) {
                            Text("finance.recurring.category.none").tag(Optional<UUID>.none)
                            ForEach(shownCategories, id: \.id) { Text(verbatim: $0.displayName()).tag(Optional($0.id)) }
                        }
                    }
                }

                Section("finance.recurring.section.schedule") {
                    Picker("finance.recurring.frequency", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.titleKey).tag($0) }
                    }
                    switch frequency {
                    case .monthly:
                        Stepper("finance.recurring.dayOfMonth \(dayOfMonth)", value: $dayOfMonth, in: 1...28)
                    case .weekly:
                        WeekdayPicker(selection: .init(get: { Set([weekday]) }, set: { weekday = $0.first ?? 2 }))
                    case .yearly:
                        Stepper("finance.recurring.month \(yearMonth)", value: $yearMonth, in: 1...12)
                        Stepper("finance.recurring.dayOfMonth \(yearDay)", value: $yearDay, in: 1...28)
                    }
                }

                Section("finance.recurring.section.dates") {
                    DatePicker("finance.recurring.start", selection: $startDate, displayedComponents: .date)
                    Toggle("finance.recurring.endDate", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("finance.recurring.end", selection: Binding(
                            get: { endDate ?? .now }, set: { endDate = $0 }),
                                   displayedComponents: .date)
                    }
                }

                Section("finance.recurring.section.mode") {
                    Picker("finance.recurring.mode", selection: $mode) {
                        Text("finance.recurring.mode.auto").tag(RecurringMode.auto)
                        Text("finance.recurring.mode.confirm").tag(RecurringMode.confirm)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("finance.recurring.note", text: $note)
                } header: {
                    Text("finance.recurring.section.note")
                }

                if let rule {
                    Section {
                        Button("finance.recurring.archive", role: .destructive) {
                            FinanceRepository.setArchived(true, rule)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Text(rule == nil ? "finance.recurring.add" : "finance.recurring.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var shownCategories: [MoneyCategory] {
        categories.filter { $0.kind == kind && !$0.isArchived }
    }

    private var canSave: Bool {
        guard let walletID, wallets.contains(where: { $0.id == walletID }),
              let amount = Int64(self.amount.filter(\.isNumber)), amount > 0 else { return false }
        if kind == .transfer {
            return toWalletID.map { $0 != walletID } ?? false
        }
        return categoryID != nil
    }

    private func walletName(for id: UUID?) -> String {
        guard let id, let w = wallets.first(where: { $0.id == id }) else { return "—" }
        return w.name
    }

    private func walletMenu(selection: Binding<UUID?>, label: String) -> some View {
        Menu {
            Picker("finance.recurring.wallets", selection: selection) {
                Text("—").tag(Optional<UUID>.none)
                ForEach(wallets, id: \.id) { Text(verbatim: $0.name).tag(Optional($0.id)) }
            }
        } label: {
            Text(verbatim: label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Color.orbit.card, in: .capsule)
        }
    }

    private func save() {
        guard canSave,
              let walletID,
              let wallet = wallets.first(where: { $0.id == walletID }),
              let amount = Int64(amount.filter(\.isNumber)) else { return }

        let toWallet: Wallet? = toWalletID.flatMap { id in wallets.first { $0.id == id } }
        let category: MoneyCategory? = categoryID.flatMap { id in categories.first { $0.id == id } }

        let freq: Recurrence.Frequency
        switch frequency {
        case .monthly: freq = .monthly(day: dayOfMonth)
        case .weekly: freq = .weekly(weekday: weekday)
        case .yearly: freq = .yearly(month: yearMonth, day: yearDay)
        }

        let end = hasEndDate ? endDate : nil
        let nextDue = Recurrence(freq).next(onOrAfter: startDate)

        if let rule {
            rule.kindRaw = kind.rawValue
            rule.amount = amount
            rule.walletID = wallet.id
            rule.toWalletID = toWallet?.id
            rule.categoryID = category?.id
            rule.frequency = freq
            rule.startDate = startDate
            rule.endDate = end
            rule.modeRaw = mode.rawValue
            rule.note = note
            rule.nextDueDate = nextDue
            rule.updatedAt = .now
        } else {
            let r = RecurringRule(kind: kind, amount: amount, walletID: wallet.id,
                                  toWalletID: toWallet?.id, categoryID: category?.id,
                                  note: note, frequency: freq, startDate: startDate,
                                  endDate: end, mode: mode)
            r.nextDueDate = nextDue
            context.insert(r)
        }
        FinanceRepository.save(context)
        dismiss()
    }
}

#Preview("New expense") {
    NavigationStack { RecurringRuleFormView(rule: nil) }
        .modelContainer(OrbitData.makePreviewContainer())
}
