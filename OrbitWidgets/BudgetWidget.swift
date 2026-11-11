import SwiftUI
import WidgetKit
import OrbitData
import OrbitEngine
import OrbitUI

// WID-05 (Small / Medium): sisa budget bulan ini + peringatan kategori, tombol quick add.

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetWidgetSnapshot
}

struct BudgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : BudgetEntry(date: .now, snapshot: .load()))
    }

    /// Now + midnight, when the budget period rolls over.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [
            BudgetEntry(date: now, snapshot: .load(date: now)),
            BudgetEntry(date: midnight, snapshot: .load(date: midnight)),
        ], policy: .atEnd))
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.budget, provider: BudgetProvider()) { entry in
            BudgetWidgetView(snapshot: entry.snapshot)
                .environment(\.locale, SettingsSnapshot(from: .orbit).language.locale)
                .containerBackground(Color.orbit.card, for: .widget)
        }
        .configurationDisplayName(Text("widget.budget.name"))
        .description(Text("widget.budget.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct BudgetWidgetView: View {
    let snapshot: BudgetWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("widget.budget.title").font(.subheadline.weight(.bold)).lineLimit(1)
                Spacer()
            }
            Text(verbatim: Rupiah.format(snapshot.totalRemaining))
                .font(Typography.amountHero)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if snapshot.totalLimit > 0 {
                let fraction = min(Double(snapshot.totalSpent) / Double(snapshot.totalLimit), 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.orbit.track)
                        Capsule().fill(snapshot.overallStatus == .safe ? Color.primary : Color.orbit.accent)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                Text(verbatim: "\(Rupiah.format(snapshot.totalSpent)) / \(Rupiah.format(snapshot.totalLimit))")
                    .font(.caption2)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            Spacer(minLength: 0)
            if let url = URL(string: "orbit://add/expense") {
                Link(destination: url) {
                    Text("widget.budget.quickAdd")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orbit.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.orbit.primary, in: .capsule)
                }
                .invalidatableContent()
            }
        }
        .padding(12)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("widget.budget.title").font(Typography.section).lineLimit(1)
                Spacer()
                statusChip
            }
            Text(verbatim: Rupiah.format(snapshot.totalRemaining))
                .font(Typography.amountHero)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if snapshot.totalLimit > 0 {
                Text("widget.budget.spent \(Rupiah.format(snapshot.totalSpent)) / \(Rupiah.format(snapshot.totalLimit))")
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            if !snapshot.items.isEmpty {
                Divider()
                ForEach(snapshot.items.prefix(4)) { item in
                    BudgetRow(item: item)
                }
            }
            Spacer(minLength: 0)
            if let url = URL(string: "orbit://add/expense") {
                Link(destination: url) {
                    Text("widget.budget.quickAdd")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.orbit.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Color.orbit.primary, in: .capsule)
                }
                .invalidatableContent()
            }
        }
        .padding(12)
    }

    private var statusChip: some View {
        Group {
            switch snapshot.overallStatus {
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
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .fixedSize()
    }
}

/// One category row in the medium widget.
private struct BudgetRow: View {
    let item: BudgetWidgetItem

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: item.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(item.isOver ? Color.orbit.textSecondary : .primary)
            Spacer(minLength: 4)
            Text(verbatim: "\(Rupiah.format(item.remaining)) / \(Rupiah.format(item.limit))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.orbit.textSecondary)
            StatusChipMini(status: item.status)
        }
    }
}

private struct StatusChipMini: View {
    let status: BudgetStatus

    var body: some View {
        Group {
            switch status {
            case .safe:
                Text("finance.budget.safe").foregroundStyle(Color.primary)
                    .background(Color.orbit.iconTile, in: .capsule)
            case .warning:
                Text("finance.budget.warning").foregroundStyle(Color.orbit.accent)
                    .overlay(Capsule().strokeBorder(Color.orbit.accent, lineWidth: 1))
            case .over(let percent):
                Text("finance.budget.over \(percent)").foregroundStyle(Color.orbit.onAccent)
                    .background(Color.orbit.accent, in: .capsule)
            }
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .fixedSize()
    }
}

#Preview("Small", as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .sample)
}

#Preview("Medium", as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BudgetEntry(date: .now, snapshot: .sample)
}
