import AppIntents
import SwiftUI
import WidgetKit
import OrbitData
import OrbitUI

// WID-01 (Small / Medium / Large) + WID-02 (Lock Screen circular). Canvas p.10.

struct HabitsEntry: TimelineEntry {
    let date: Date
    let snapshot: HabitWidgetSnapshot
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry {
        HabitsEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : HabitsEntry(date: .now, snapshot: .load()))
    }

    /// Now + an entry at 00:00 so the widget starts the new day empty (PRD widget rule).
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [
            HabitsEntry(date: now, snapshot: .load(date: now)),
            HabitsEntry(date: midnight, snapshot: .load(date: midnight)),
        ], policy: .atEnd))
    }
}

struct HabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.habits, provider: HabitsProvider()) { entry in
            HabitsWidgetView(snapshot: entry.snapshot)
                .environment(\.locale, SettingsSnapshot(from: .orbit).language.locale)
                .containerBackground(Color.orbit.card, for: .widget)
        }
        .configurationDisplayName(Text("widget.habits.name"))
        .description(Text("widget.habits.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
    }
}

struct HabitsWidgetView: View {
    let snapshot: HabitWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: lockScreen
        case .systemSmall: small
        case .systemLarge: large
        default: medium
        }
    }

    // MARK: Families

    private var lockScreen: some View {
        Gauge(value: snapshot.progress) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text(verbatim: "\(snapshot.done)/\(snapshot.total)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel(Text("widget.habits.name"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ring(size: 44, font: Typography.metric)
                Text("tab.habits").font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            rows(limit: 2, spacing: 6, compact: true)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("tab.habits").font(.subheadline.weight(.bold))
                Spacer(minLength: 0)
                ring(size: 76, font: .custom("InterTight-ExtraBold", size: 22, relativeTo: .title2))
                Spacer(minLength: 0)
                Text("widget.habits.doneToday").font(.caption).foregroundStyle(.secondary)
            }
            rows(limit: 4, spacing: 4)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("tab.habits").font(Typography.section)
                    Text("widget.habits.doneToday").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ring(size: 52, font: Typography.metric)
            }
            rows(limit: 7, spacing: 6, icons: true, showMore: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Parts

    private func ring(size: CGFloat, font: Font) -> some View {
        MiniRing(progress: snapshot.progress, lineWidth: size / 9) {
            Text(verbatim: "\(snapshot.done)/\(snapshot.total)")
                .font(font)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("habits.today.progress \(snapshot.done) \(snapshot.total)"))
    }

    @ViewBuilder
    /// `compact` (Small) hides the "3/8" count so names fit; only Large lists "+N more".
    private func rows(limit: Int, spacing: CGFloat, icons: Bool = false, compact: Bool = false, showMore: Bool = false) -> some View {
        if snapshot.items.isEmpty {
            Text("widget.habits.empty")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(snapshot.items.prefix(limit)) { item in
                    WidgetHabitRow(item: item, showIcon: icons, showCount: !compact)
                }
                if showMore, snapshot.items.count > limit {
                    Text("widget.habits.more \(snapshot.items.count - limit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Name + interactive control. Count habits get a "+1" pill until the target is reached.
struct WidgetHabitRow: View {
    let item: HabitWidgetItem
    var showIcon = false
    var showCount = true

    var body: some View {
        HStack(spacing: 8) {
            if showIcon {
                Image(systemName: item.iconName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.orbit.iconTint)
                    .frame(width: 28, height: 28)
                    .background(Color.orbit.iconTile, in: .rect(cornerRadius: 8, style: .continuous))
            }
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showCount, item.isCount, !item.isDone {
                Text(verbatim: "\(item.value)/\(item.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        if item.isCount, !item.isDone {
            Button(intent: IncrementHabitIntent(habitID: item.id)) {
                Text(verbatim: "+1")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orbit.onAccent)
                    .frame(width: 30, height: 30)
                    .background(Color.orbit.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityLabel(Text("habits.a11y.addOne"))
        } else {
            Button(intent: ToggleHabitIntent(habitID: item.id)) {
                HabitCheckMark(item.isSkipped ? .skipped : .check(done: item.isDone), size: 30)
            }
            .buttonStyle(.plain)
            .invalidatableContent()
            .accessibilityLabel(Text(item.isDone ? "habits.a11y.undo" : "habits.a11y.markDone"))
        }
    }
}

#Preview("Medium", as: .systemMedium) {
    HabitsWidget()
} timeline: {
    HabitsEntry(date: .now, snapshot: .sample)
}

#Preview("Small", as: .systemSmall) {
    HabitsWidget()
} timeline: {
    HabitsEntry(date: .now, snapshot: .sample)
}

#Preview("Large", as: .systemLarge) {
    HabitsWidget()
} timeline: {
    HabitsEntry(date: .now, snapshot: .sample)
}

#Preview("Lock", as: .accessoryCircular) {
    HabitsWidget()
} timeline: {
    HabitsEntry(date: .now, snapshot: .sample)
}
