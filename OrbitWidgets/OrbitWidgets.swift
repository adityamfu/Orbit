// Placeholder so the extension has one widget; replaced by the Habit widget in Phase 2.
import SwiftUI
import WidgetKit
import OrbitUI

struct BrandEntry: TimelineEntry {
    let date: Date
}

struct BrandProvider: TimelineProvider {
    func placeholder(in context: Context) -> BrandEntry { BrandEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (BrandEntry) -> Void) {
        completion(BrandEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BrandEntry>) -> Void) {
        completion(Timeline(entries: [BrandEntry(date: .now)], policy: .never))
    }
}

struct BrandWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OrbitBrand", provider: BrandProvider()) { _ in
            VStack(alignment: .leading) {
                OrbChip().fill(Color.orbit.accent).orbChipFrame(height: 14)
                Spacer()
                Text(verbatim: "Orbit").font(Typography.largeTitle).tracking(-0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(Color.orbit.card, for: .widget)
        }
        .configurationDisplayName(Text(verbatim: "Orbit"))
        .description(Text("widget.brand.description"))
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: .systemSmall) {
    BrandWidget()
} timeline: {
    BrandEntry(date: .now)
}
