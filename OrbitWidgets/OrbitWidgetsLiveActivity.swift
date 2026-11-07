// Phase 0 spike Live Activity — delete after the spike passes.
import ActivityKit
import SwiftUI
import WidgetKit

struct OrbitWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpikeActivityAttributes.self) { context in
            HStack {
                Text(context.attributes.name)
                    .font(.custom("InterTight-ExtraBold", size: 22, relativeTo: .title2))
                Spacer()
                countdown(context.state)
                    .font(.custom("InterTight-Black", size: 34, relativeTo: .largeTitle))
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.attributes.name) }
                DynamicIslandExpandedRegion(.trailing) { countdown(context.state) }
            } compactLeading: {
                Image(systemName: "dumbbell")
            } compactTrailing: {
                countdown(context.state).frame(width: 44)
            } minimal: {
                Image(systemName: "dumbbell")
            }
        }
    }

    private func countdown(_ state: SpikeActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...max(state.startedAt, state.endsAt), countsDown: true)
            .monospacedDigit()
    }
}
