import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Manage wallets: archive/restore, rename, add (FIN-01 management).
struct WalletListView: View {
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.sortOrder) private var wallets: [Wallet]
    @Query(filter: #Predicate<Wallet> { $0.isArchived }) private var archived: [Wallet]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale

    @State private var showNew = false
    @State private var editing: Wallet?

    var body: some View {
        List {
            ScreenHeader(Text("finance.wallets.title")) {
                RoundAddButton(label: Text("finance.wallets.add")) { showNew = true }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            if wallets.isEmpty {
                emptyState
            } else {
                ForEach(wallets) { wallet in
                    HStack(spacing: 12) {
                        Image(systemName: wallet.type.defaultIcon)
                            .foregroundStyle(Color.orbit.iconTint)
                            .frame(width: 40, height: 40)
                            .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: wallet.name).font(.body.weight(.medium))
                            Text(verbatim: Rupiah.format(wallet.balance))
                                .font(Typography.metric)
                                .foregroundStyle(wallet.balance < 0 ? Color.red : Color.orbit.textSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                    .onTapGesture { editing = wallet }
                    .swipeActions(edge: .trailing) {
                        Button(wallet.isArchived ? "finance.wallet.restore" : "finance.wallet.archive",
                               systemImage: wallet.isArchived ? "arrow.uturn.backward" : "archivebox") {
                            FinanceRepository.setArchived(!wallet.isArchived, wallet)
                        }
                        .tint(wallet.isArchived ? Color.orbit.accent : .gray)
                        Button("common.edit", systemImage: "pencil") { editing = wallet }
                            .tint(.blue)
                    }
                }
                .onMove { move($0, $1) }
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { wallet in
                        HStack(spacing: 12) {
                            Image(systemName: wallet.type.defaultIcon)
                                .foregroundStyle(Color.orbit.iconTint)
                                .frame(width: 40, height: 40)
                                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                                .accessibilityHidden(true)
                            Text(wallet.name)
                            Spacer()
                            Button("finance.wallet.restore") {
                                FinanceRepository.setArchived(false, wallet)
                            }
                            .buttonStyle(.borderless)
                            .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("finance.wallets.archived")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) { WalletFormView(wallet: nil, nextSortOrder: wallets.count) }
        .sheet(item: $editing) { WalletFormView(wallet: $0, nextSortOrder: wallets.count) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("finance.wallets.empty", systemImage: "wallet.bifold")
        } description: {
            Text("finance.wallets.empty.description")
        } actions: {
            Button("finance.wallets.empty.action") { showNew = true }
                .buttonStyle(.orbitPrimary)
        }
        .listRowBackground(Color.clear)
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        let moving = source.map { wallets[$0] }
        var ordered = wallets.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        ordered.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        for (index, wallet) in ordered.enumerated() where wallet.sortOrder != index {
            wallet.sortOrder = index
        }
        wallets.first?.modelContext.map { FinanceRepository.save($0) }
    }
}

#Preview("Wallets") {
    NavigationStack { WalletListView() }
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty, English") {
    NavigationStack { WalletListView() }
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
        .environment(\.locale, Locale(identifier: "en_US"))
}
