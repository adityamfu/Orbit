import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Add or edit a wallet (FIN-01). Pass a wallet to edit; nil to create.
struct WalletFormView: View {
    let wallet: Wallet?
    let nextSortOrder: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: WalletType
    @State private var initial: String

    init(wallet: Wallet?, nextSortOrder: Int) {
        self.wallet = wallet
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: wallet?.name ?? "")
        _type = State(initialValue: wallet?.type ?? .bank)
        _initial = State(initialValue: wallet.map { String($0.initialBalance) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("finance.wallet.name", text: $name)
                Picker("finance.wallet.type", selection: $type) {
                    ForEach(WalletType.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                TextField("finance.wallet.initial", text: $initial)
                    .keyboardType(.numberPad)
            }
            .navigationTitle(Text(wallet == nil ? "finance.wallets.add" : "finance.wallet.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if wallet != nil {
                Section {
                    Button("finance.wallet.archive", role: .destructive) {
                        FinanceRepository.setArchived(true, wallet!)
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let balance = Int64(initial.filter(\.isNumber)) ?? 0
        if let wallet {
            wallet.name = trimmed
            wallet.typeRaw = type.rawValue
            wallet.initialBalance = balance
            wallet.updatedAt = .now
        } else {
            context.insert(Wallet(name: trimmed, type: type, initialBalance: balance, sortOrder: nextSortOrder))
        }
        FinanceRepository.save(context)
        dismiss()
    }
}

extension WalletType {
    var titleKey: LocalizedStringKey {
        switch self {
        case .cash: "finance.walletType.cash"
        case .bank: "finance.walletType.bank"
        case .eWallet: "finance.walletType.eWallet"
        case .other: "finance.walletType.other"
        }
    }
}

#Preview("Add") {
    NavigationStack { WalletFormView(wallet: nil, nextSortOrder: 0) }
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Edit") {
    let container = OrbitData.makePreviewContainer()
    let wallet = try! container.mainContext.fetch(FetchDescriptor<Wallet>()).first!
    return NavigationStack { WalletFormView(wallet: wallet, nextSortOrder: 0) }
        .modelContainer(container)
}
