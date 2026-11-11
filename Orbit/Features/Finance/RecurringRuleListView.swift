import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Manage recurring rules: list active + archived, toggle, archive/restore, add (FIN-07).
struct RecurringRuleListView: View {
    @Query(sort: \RecurringRule.startDate) private var allRules: [RecurringRule]
    @Environment(\.modelContext) private var context

    @State private var showNew = false
    @State private var editing: RecurringRule?

    private var activeRules: [RecurringRule] { allRules.filter { $0.isActive } }
    private var archivedRules: [RecurringRule] { allRules.filter { !$0.isActive } }

    var body: some View {
        List {
            ScreenHeader(Text("finance.recurring.title")) {
                RoundAddButton(label: Text("finance.recurring.add")) { showNew = true }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            if activeRules.isEmpty {
                ContentUnavailableView {
                    Label("finance.recurring.empty", systemImage: "repeat")
                } description: {
                    Text("finance.recurring.empty.description")
                } actions: {
                    Button("finance.recurring.add") { showNew = true }
                        .buttonStyle(.orbitPrimary)
                }
                .listRowBackground(Color.clear)
            } else {
                Section("finance.recurring.active") {
                    ForEach(activeRules) { rule in
                        ruleRow(rule)
                    }
                }
            }

            if !archivedRules.isEmpty {
                Section {
                    ForEach(archivedRules) { rule in
                        ruleRow(rule, archived: true)
                    }
                } header: {
                    Text("finance.recurring.archived")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNew) {
            RecurringRuleFormView(rule: nil)
        }
        .sheet(item: $editing) { RecurringRuleFormView(rule: $0) }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RecurringRule, archived: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "repeat")
                .foregroundStyle(Color.orbit.iconTint)
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.note.isEmpty ? "finance.recurring.unnamed" : rule.note)
                    .font(.body.weight(.medium))
                    .foregroundStyle(archived ? Color.orbit.textSecondary : Color.primary)
                Text(frequencyText(rule))
                    .font(.caption)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(verbatim: Rupiah.format(rule.amount))
                    .font(Typography.metric)
                    .foregroundStyle(rule.kind == .income ? Color.orbit.accent : Color.primary)
                Text(modeText(rule))
                    .font(.caption2)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
        }
        .contentShape(.rect)
        .onTapGesture { editing = rule }
        .swipeActions(edge: .trailing) {
            Button(archived ? "finance.recurring.restore" : "finance.recurring.archive",
                   systemImage: archived ? "arrow.uturn.backward" : "archivebox") {
                FinanceRepository.setArchived(archived, rule)
            }
            .tint(archived ? Color.orbit.accent : .gray)
            Button("common.edit", systemImage: "pencil") { editing = rule }
                .tint(.blue)
        }
    }

    private func frequencyText(_ rule: RecurringRule) -> String {
        let freq = rule.frequency
        switch freq {
        case .monthly(let d):
            return String(localized: "finance.recurring.freq.monthly", defaultValue: "Monthly on day \(d)")
        case .weekly(let w):
            var cal = Calendar(identifier: .gregorian)
            let sym = cal.veryShortStandaloneWeekdaySymbols[w - 1]
            return String(localized: "finance.recurring.freq.weekly", defaultValue: "Weekly on \(sym)")
        case .yearly(let m, let d):
            return String(localized: "finance.recurring.freq.yearly", defaultValue: "Yearly on \(m)/\(d)")
        }
    }

    private func modeText(_ rule: RecurringRule) -> String {
        rule.mode == .auto
            ? String(localized: "finance.recurring.mode.auto", defaultValue: "Auto")
            : String(localized: "finance.recurring.mode.confirm", defaultValue: "Confirm")
    }
}

#Preview("Rules") {
    NavigationStack { RecurringRuleListView() }
        .modelContainer(OrbitData.makePreviewContainer())
}
