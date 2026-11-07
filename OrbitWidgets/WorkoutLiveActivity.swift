import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import OrbitData
import OrbitUI

/// WRK-07 / WID-06 (DESIGN.md §7): dark card, exercise + set, big lime countdown while resting,
/// "Set selesai" and "+30 dtk". On iPhones without a Dynamic Island only the Lock Screen part shows.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .environment(\.locale, SettingsSnapshot(from: .orbit).language.locale)
                .activityBackgroundTint(Color(white: 0.11))
                .activitySystemActionForegroundColor(Color.orbit.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: state.exerciseName).font(.headline).lineLimit(1)
                        SetLabel(state: state).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Clock(attributes: context.attributes, state: state)
                        .font(.custom("InterTight-ExtraBold", size: 28, relativeTo: .title).monospacedDigit())
                        .foregroundStyle(state.restEnd == nil ? Color.white : Color.orbit.primary)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Buttons(state: state).padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill").foregroundStyle(Color.orbit.primary)
            } compactTrailing: {
                Clock(attributes: context.attributes, state: state)
                    .monospacedDigit()
                    .foregroundStyle(state.restEnd == nil ? Color.white : Color.orbit.primary)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(Color.orbit.primary)
            }
            .keylineTint(Color.orbit.primary)
        }
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: attributes.routineName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text(verbatim: state.exerciseName)
                        .font(.custom("InterTight-Bold", size: 20, relativeTo: .title3))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    SetLabel(state: state)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Group {
                        if state.restEnd != nil { Text("session.rest") } else { Text("activity.elapsed") }
                    }
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    Clock(attributes: attributes, state: state)
                        .font(.custom("InterTight-ExtraBold", size: 36, relativeTo: .largeTitle).monospacedDigit())
                        .foregroundStyle(state.restEnd == nil ? Color.white : Color.orbit.primary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            }
            ProgressView(value: Double(state.setsDone), total: Double(max(state.setsTotal, 1)))
                .tint(Color.orbit.primary)
            Buttons(state: state)
        }
        .padding(16)
    }
}

/// "Set 2 dari 4" or "Semua set selesai".
private struct SetLabel: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.setNumber == 0 {
            Text("activity.allDone")
        } else {
            Text("activity.set \(state.setNumber) \(state.setCount)")
        }
    }
}

/// Rest countdown while resting, otherwise the workout's running time.
private struct Clock: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let end = state.restEnd, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else {
            Text(attributes.startedAt, style: .timer)
        }
    }
}

private struct Buttons: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.setNumber > 0 {
                Button(intent: CompleteSetIntent()) {
                    Label("activity.completeSet", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.orbit.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.orbit.primary, in: .capsule)
                }
                .buttonStyle(.plain)
            }
            Button(intent: ExtendRestIntent()) {
                Text("activity.plus30")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 84, minHeight: 40)
                    .background(Color.white.opacity(0.15), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("Lock screen", as: .content, using: WorkoutActivityAttributes(routineName: "Push Day", startedAt: .now.addingTimeInterval(-1_450))) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(exerciseName: "Bench Press", setNumber: 3, setCount: 4, setsDone: 7, setsTotal: 17,
                                           restEnd: .now.addingTimeInterval(84))
    WorkoutActivityAttributes.ContentState(exerciseName: "Bench Press", setNumber: 3, setCount: 4, setsDone: 7, setsTotal: 17, restEnd: nil)
}
