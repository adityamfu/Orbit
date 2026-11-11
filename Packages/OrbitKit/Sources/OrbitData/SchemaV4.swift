import Foundation
import SwiftData

/// V4 (Phase 5): adds weekly KPI goals. Habit, workout and finance models are unchanged and reused.
public enum OrbitSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] {
        OrbitSchemaV3.models + [WeeklyGoal.self]
    }

    @Model
    public final class WeeklyGoal {
        @Attribute(.unique) public var id: UUID
        public var createdAt: Date
        public var updatedAt: Date
        /// `yyyyWW`, first weekday per user setting (OrbitEngine week key).
        public var weekKey: Int
        /// `sessions`, `volume`, `cardioMinutes`, or `steps`.
        public var metricRaw: String
        public var target: Double
        /// Engine's plain-language reason (Indonesian default).
        public var reason: String
        /// `suggested`, `accepted`, or `edited`.
        public var statusRaw: String

        public init(id: UUID = UUID(), weekKey: Int, metric: WeeklyMetric, target: Double, reason: String,
                    status: WeeklyGoalStatus = .suggested, createdAt: Date = .now) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.weekKey = weekKey
            self.metricRaw = metric.rawValue
            self.target = target
            self.reason = reason
            self.statusRaw = status.rawValue
        }
    }
}

public typealias WeeklyGoal = OrbitSchemaV4.WeeklyGoal

public enum WeeklyMetric: String, CaseIterable, Codable, Sendable {
    case sessions, volume, cardioMinutes, steps
}

public enum WeeklyGoalStatus: String, CaseIterable, Codable, Sendable {
    case suggested, accepted, edited
}
