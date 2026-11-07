import Foundation

public enum OrbitData {
    public static let appGroup = "group.com.moondg.orbit"
}

public extension UserDefaults {
    /// Settings shared by app and widgets (App Group). Use with `@AppStorage(key, store: .orbit)`.
    static var orbit: UserDefaults { UserDefaults(suiteName: OrbitData.appGroup)! }
}

/// UserDefaults keys. Defaults live in `SettingsSnapshot.defaults`.
public enum SettingsKey {
    public static let language = "language"
    public static let appearance = "appearance"
    public static let firstWeekday = "firstWeekday"
    public static let cycleStartDay = "cycleStartDay"
    public static let weightIncrement = "weightIncrement"
    public static let lastBackupAt = "lastBackupAt"
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case id, en

    public var locale: Locale { Locale(identifier: self == .id ? "id_ID" : "en_US") }
}

public enum Appearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark
}

/// Every user setting, as one value. Used for backup and for reading defaults outside SwiftUI.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var appearance: Appearance
    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    public var firstWeekday: Int
    /// Day of month a budget period starts (1–28).
    public var cycleStartDay: Int
    /// Minimum weight step in kg.
    public var weightIncrement: Double

    public static let defaults = SettingsSnapshot(
        language: .id, appearance: .system, firstWeekday: 2, cycleStartDay: 1, weightIncrement: 2.5
    )

    public init(language: AppLanguage, appearance: Appearance, firstWeekday: Int, cycleStartDay: Int, weightIncrement: Double) {
        self.language = language
        self.appearance = appearance
        self.firstWeekday = firstWeekday
        self.cycleStartDay = cycleStartDay
        self.weightIncrement = weightIncrement
    }

    public init(from defaults: UserDefaults) {
        let d = Self.defaults
        language = defaults.string(forKey: SettingsKey.language).flatMap(AppLanguage.init) ?? d.language
        appearance = defaults.string(forKey: SettingsKey.appearance).flatMap(Appearance.init) ?? d.appearance
        firstWeekday = defaults.object(forKey: SettingsKey.firstWeekday) as? Int ?? d.firstWeekday
        cycleStartDay = defaults.object(forKey: SettingsKey.cycleStartDay) as? Int ?? d.cycleStartDay
        weightIncrement = defaults.object(forKey: SettingsKey.weightIncrement) as? Double ?? d.weightIncrement
    }

    public func write(to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: SettingsKey.language)
        defaults.set(appearance.rawValue, forKey: SettingsKey.appearance)
        defaults.set(firstWeekday, forKey: SettingsKey.firstWeekday)
        defaults.set(cycleStartDay, forKey: SettingsKey.cycleStartDay)
        defaults.set(weightIncrement, forKey: SettingsKey.weightIncrement)
    }
}
