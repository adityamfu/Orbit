// Target membership: Orbit + OrbitWidgetsExtension (via the Shared folder).
import ActivityKit
import AppIntents
import Foundation

/// WRK-07 / WID-06: running workout on the Lock Screen and Dynamic Island.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Already in the app language (the widget doesn't know the exercise catalog).
        var exerciseName: String
        /// Next open set of that exercise (1-based); 0 when every set is ticked.
        var setNumber: Int
        var setCount: Int
        var setsDone: Int
        var setsTotal: Int
        /// Set while resting.
        var restEnd: Date?
    }

    var routineName: String
    var startedAt: Date
}

/// Buttons on the Live Activity. `LiveActivityIntent` runs in the app process (launched in the
/// background if needed), where `SessionActions.handler` is wired to the running session.
enum SessionAction: Sendable {
    case completeSet
    case extendRest(seconds: Int)
}

@MainActor
enum SessionActions {
    /// Async so the intent waits until the Live Activity is updated; the app may be suspended right after.
    static var handler: ((SessionAction) async -> Void)?

    static func handle(_ action: SessionAction) async {
        await handler?(action)
    }
}

struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "intent.session.completeSet"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await SessionActions.handle(.completeSet)
        return .result()
    }
}

struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "intent.session.extendRest"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await SessionActions.handle(.extendRest(seconds: 30))
        return .result()
    }
}
