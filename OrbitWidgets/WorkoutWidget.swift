import SwiftUI
import WidgetKit
import OrbitData
import OrbitUI

// WID-03 (Small / Medium) + WID-04 (Lock Screen rectangular). "Mulai" opens orbit://workout,
// which starts today's routine (or reopens the running session).

struct WorkoutEntry: TimelineEntry {
    let date: Date
    let snapshot: WorkoutWidgetSnapshot
}

struct WorkoutProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry { WorkoutEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WorkoutEntry(date: .now, snapshot: .load()))
    }

    /// Now + midnight, when today's routine changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let now = Date.now
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [
            WorkoutEntry(date: now, snapshot: .load(date: now)),
            WorkoutEntry(date: midnight, snapshot: .load(date: midnight)),
        ], policy: .atEnd))
    }
}

struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.workout, provider: WorkoutProvider()) { entry in
            WorkoutWidgetView(snapshot: entry.snapshot)
                .environment(\.locale, SettingsSnapshot(from: .orbit).language.locale)
                .containerBackground(Color.orbit.card, for: .widget)
        }
        .configurationDisplayName(Text("widget.workout.name"))
        .description(Text("widget.workout.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct WorkoutWidgetView: View {
    let snapshot: WorkoutWidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryRectangular {
            lockScreen
        } else {
            HStack(alignment: .top, spacing: 16) {
                main
                if family == .systemMedium, snapshot.activeSince == nil, !snapshot.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.exercises.prefix(5), id: \.self) { Text(verbatim: $0).lineLimit(1) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                if snapshot.activeSince != nil { Text("widget.workout.active") } else { Text("widget.workout.title") }
            } icon: {
                Image(systemName: "dumbbell.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Group {
                if let name = snapshot.activeName ?? snapshot.routineName { Text(verbatim: name) } else { Text("workout.restDay") }
            }
            .font(.custom("InterTight-ExtraBold", size: 24, relativeTo: .title2))
            .lineLimit(2)
            .minimumScaleFactor(0.7)

            if let since = snapshot.activeSince {
                Text(since, style: .timer).font(Typography.metric).foregroundStyle(Color.orbit.accent)
            } else if snapshot.routineName != nil {
                Text("workout.exerciseCount \(snapshot.exercises.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if snapshot.activeSince != nil || snapshot.routineName != nil {
                Link(destination: URL(string: "orbit://workout")!) {
                    Group {
                        if snapshot.activeSince != nil { Text("session.resume") } else { Text("widget.workout.start") }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.orbit.onPrimary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.orbit.primary, in: .capsule)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                if let name = snapshot.activeName ?? snapshot.routineName { Text(verbatim: name) } else { Text("workout.restDay") }
            } icon: {
                Image(systemName: "dumbbell.fill")
            }
            .font(.headline)
            .widgetAccentable()
            if let since = snapshot.activeSince {
                Text(since, style: .timer).monospacedDigit()
            } else if snapshot.routineName != nil {
                Text("widget.workout.notStarted \(snapshot.exercises.count)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Small", as: .systemSmall) { WorkoutWidget() } timeline: { WorkoutEntry(date: .now, snapshot: .sample) }
#Preview("Medium", as: .systemMedium) { WorkoutWidget() } timeline: { WorkoutEntry(date: .now, snapshot: .sample) }
#Preview("Lock", as: .accessoryRectangular) { WorkoutWidget() } timeline: { WorkoutEntry(date: .now, snapshot: .sample) }
