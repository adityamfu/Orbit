// Phase 0 spike — delete after the spike passes.
// Target membership: Orbit + OrbitWidgetsExtension.
import ActivityKit
import AppIntents
import Foundation
import WidgetKit
import OrbitData

enum SpikeKind {
    nonisolated static let widget = "SpikeWidget"
}

struct SpikeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
    }

    var name: String
}

struct AddSpikeNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add note"

    func perform() async throws -> some IntentResult {
        try OrbitData.addSpikeNote()
        WidgetCenter.shared.reloadTimelines(ofKind: SpikeKind.widget)
        return .result()
    }
}
