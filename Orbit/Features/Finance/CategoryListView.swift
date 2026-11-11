import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Manage categories: archive/restore, edit, add. Expense and income shown separately (FIN-04).
struct CategoryListView: View {
    @Query(sort: \MoneyCategory.sortOrder) private var allCats: [MoneyCategory]

    private var expenseCats: [MoneyCategory] { allCats.filter { !$0.isArchived && $0.kind == .expense } }
    private var incomeCats: [MoneyCategory] { allCats.filter { !$0.isArchived && $0.kind == .income } }
    private var archivedCats: [MoneyCategory] { allCats.filter { $0.isArchived } }

    @Environment(\.modelContext) private var context

    @State private var showNew = false
    @State private var editing: MoneyCategory?

    var body: some View {
        List {
            ScreenHeader(Text("finance.categories.title")) {
                RoundAddButton(label: Text("finance.categories.add")) { showNew = true }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            if !expenseCats.isEmpty {
                Section("finance.categories.expense") { categoryRows(expenseCats) }
            }
            if !incomeCats.isEmpty {
                Section("finance.categories.income") { categoryRows(incomeCats) }
            }
            if expenseCats.isEmpty && incomeCats.isEmpty {
                emptyState
            }
            if !archivedCats.isEmpty {
                Section {
                    ForEach(archivedCats) { cat in
                        HStack(spacing: 12) {
                            Image(systemName: cat.iconName)
                                .foregroundStyle(Color.orbit.iconTint)
                                .frame(width: 40, height: 40)
                                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                                .accessibilityHidden(true)
                            Text(cat.name)
                            Spacer()
                            Button("finance.category.restore") {
                                FinanceRepository.setArchived(false, cat)
                            }
                            .buttonStyle(.borderless)
                            .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("finance.categories.archived")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) {
            let next = max(expenseCats.map(\.sortOrder).max() ?? -1,
                           incomeCats.map(\.sortOrder).max() ?? -1) + 1
            CategoryFormView(category: nil, nextSortOrder: next)
        }
        .sheet(item: $editing) { CategoryFormView(category: $0, nextSortOrder: 0) }
    }

    @ViewBuilder
    private func categoryRows(_ cats: [MoneyCategory]) -> some View {
        ForEach(cats) { cat in
            HStack(spacing: 12) {
                Image(systemName: cat.iconName)
                    .foregroundStyle(Color.orbit.iconTint)
                    .frame(width: 40, height: 40)
                    .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: cat.displayName()).font(.body.weight(.medium))
                    Text(cat.kind == .expense ? "finance.kind.expense" : "finance.kind.income")
                        .font(.caption)
                        .foregroundStyle(Color.orbit.textSecondary)
                }
                Spacer()
            }
            .contentShape(.rect)
            .onTapGesture { editing = cat }
            .swipeActions(edge: .trailing) {
                Button(cat.isArchived ? "finance.category.restore" : "finance.category.archive",
                       systemImage: cat.isArchived ? "arrow.uturn.backward" : "archivebox") {
                    FinanceRepository.setArchived(!cat.isArchived, cat)
                }
                .tint(cat.isArchived ? Color.orbit.accent : .gray)
                Button("common.edit", systemImage: "pencil") { editing = cat }
                    .tint(.blue)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("finance.categories.empty", systemImage: "folder")
        } description: {
            Text("finance.categories.empty.description")
        } actions: {
            Button("finance.categories.empty.action") { showNew = true }
                .buttonStyle(.orbitPrimary)
        }
        .listRowBackground(Color.clear)
    }
}

#Preview("Categories") {
    NavigationStack { CategoryListView() }
        .modelContainer(OrbitData.makePreviewContainer())
}
