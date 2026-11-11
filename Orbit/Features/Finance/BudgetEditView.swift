import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Edit a budget's limit for its period (FIN-06 / FIN-10).
struct BudgetEditView: View {
    let budget: Budget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var limit: String

    init(budget: Budget) {
        self.budget = budget
        _limit = State(initialValue: String(budget.limit))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("finance.budget.limit", text: $limit)
                    .keyboardType(.numberPad)
            }
            .navigationTitle(Text("finance.budget.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        budget.limit = Int64(limit.filter(\.isNumber)) ?? 0
        FinanceRepository.save(context)
        dismiss()
    }
}

#Preview("Budget edit") {
    let container = OrbitData.makePreviewContainer()
    let budgets = (try? container.mainContext.fetch(FetchDescriptor<Budget>())) ?? []
    guard let b = budgets.first else {
        return NavigationStack { Text("finance.budget.none") }.modelContainer(container)
    }
    return NavigationStack { BudgetEditView(budget: b) }
        .modelContainer(container)
}
