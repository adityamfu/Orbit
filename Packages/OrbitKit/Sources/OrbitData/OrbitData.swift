import Foundation
import SwiftData

public enum OrbitData {
    public static let appGroup = "group.com.moondg.orbit"

    /// The single SwiftData store, shared by app and widget through the App Group.
    public static func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(groupContainer: .identifier(appGroup))
        return try ModelContainer(for: SpikeNote.self, configurations: config)
    }

    // MARK: Phase 0 spike — delete after the spike passes.

    public static func spikeNoteCount() -> Int {
        guard let container = try? makeContainer() else { return -1 }
        return (try? ModelContext(container).fetchCount(FetchDescriptor<SpikeNote>())) ?? -1
    }

    public static func addSpikeNote() throws {
        let context = ModelContext(try makeContainer())
        context.insert(SpikeNote())
        try context.save()
    }
}

@Model
public final class SpikeNote {
    public var createdAt: Date
    public init(createdAt: Date = .now) { self.createdAt = createdAt }
}
