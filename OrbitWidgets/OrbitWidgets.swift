// Phase 0 spike widget — delete after the spike passes.
import AppIntents
import SwiftUI
import WidgetKit
import OrbitData

struct SpikeEntry: TimelineEntry {
    let date: Date
    let count: Int
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry { SpikeEntry(date: .now, count: 0) }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(SpikeEntry(date: .now, count: OrbitData.spikeNoteCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [SpikeEntry(date: .now, count: OrbitData.spikeNoteCount())], policy: .never))
    }
}

struct OrbitWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SpikeKind.widget, provider: SpikeProvider()) { entry in
            VStack(spacing: 8) {
                Text("\(entry.count)")
                    .font(.custom("InterTight-Black", size: 48, relativeTo: .largeTitle))
                    .contentTransition(.numericText(value: Double(entry.count)))
                Button(intent: AddSpikeNoteIntent()) {
                    Image(systemName: "plus")
                }
                .invalidatableContent()
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Orbit Spike")
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    OrbitWidgets()
} timeline: {
    SpikeEntry(date: .now, count: 3)
}
