import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Add or edit a category (FIN-04). Pass a category to edit; nil to create.
struct CategoryFormView: View {
    let category: MoneyCategory?
    let nextSortOrder: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: MoneyKind
    @State private var iconName: String

    init(category: MoneyCategory?, nextSortOrder: Int) {
        self.category = category
        self.nextSortOrder = nextSortOrder
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: category?.kind ?? .expense)
        _iconName = State(initialValue: category?.iconName ?? "circle")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("finance.category.name", text: $name)
                Picker("finance.category.kind", selection: $kind) {
                    Text("finance.kind.expense").tag(MoneyKind.expense)
                    Text("finance.kind.income").tag(MoneyKind.income)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField("finance.category.icon", text: $iconName)
            }
            .navigationTitle(Text(category == nil ? "finance.categories.add" : "finance.category.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if category != nil {
                Section {
                    Button("finance.category.archive", role: .destructive) {
                        FinanceRepository.setArchived(true, category!)
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let category {
            category.name = trimmed
            category.kindRaw = kind.rawValue
            category.iconName = iconName
            category.updatedAt = .now
        } else {
            context.insert(MoneyCategory(name: trimmed, kind: kind, iconName: iconName, isDefault: false,
                                         sortOrder: nextSortOrder))
        }
        FinanceRepository.save(context)
        dismiss()
    }
}

#Preview("Add expense") {
    NavigationStack { CategoryFormView(category: nil, nextSortOrder: 0) }
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Edit") {
    let container = OrbitData.makePreviewContainer()
    let cats = (try? container.mainContext.fetch(FetchDescriptor<MoneyCategory>())) ?? []
    guard let cat = cats.first else {
        return NavigationStack { CategoryFormView(category: nil, nextSortOrder: 0) }
            .modelContainer(container)
    }
    return NavigationStack { CategoryFormView(category: cat, nextSortOrder: 0) }
        .modelContainer(container)
}
