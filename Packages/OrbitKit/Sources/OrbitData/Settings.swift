import Foundation

public enum OrbitData {
    public static let appGroup = "group.com.moondg.orbitapp"

    /// WidgetCenter and UNUserNotificationCenter crash outside an app or extension bundle
    /// (e.g. `swift test` on the Mac), so side effects check this first.
    public static var isAppOrExtension: Bool {
        ["app", "appex"].contains(Bundle.main.bundleURL.pathExtension)
    }
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
    public static let streakSaverEnabled = "streakSaverEnabled"
    public static let streakSaverMinutes = "streakSaverMinutes"
    public static let lastBackupAt = "lastBackupAt"
    public static let firstLaunch = "firstLaunch"
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case id, en

    public var locale: Locale { Locale(identifier: self == .id ? "id_ID" : "en_US") }
}

public enum Appearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark
}

/// Every user setting, as one value. Used for backup and for reading settings outside SwiftUI.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var appearance: Appearance
    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    public var firstWeekday: Int
    /// Day of month a budget period starts (1–28).
    public var cycleStartDay: Int
    /// Minimum weight step in kg.
    public var weightIncrement: Double
    /// HAB-06: evening nudge when habits due today aren't done.
    public var streakSaverEnabled: Bool
    /// Minutes after midnight (20:00 = 1200).
    public var streakSaverMinutes: Int

    public static let defaults = SettingsSnapshot(
        language: .id, appearance: .system, firstWeekday: 2, cycleStartDay: 1, weightIncrement: 2.5,
        streakSaverEnabled: true, streakSaverMinutes: 20 * 60
    )

    public init(language: AppLanguage, appearance: Appearance, firstWeekday: Int, cycleStartDay: Int, weightIncrement: Double,
                streakSaverEnabled: Bool = true, streakSaverMinutes: Int = 20 * 60) {
        self.language = language
        self.appearance = appearance
        self.firstWeekday = firstWeekday
        self.cycleStartDay = cycleStartDay
        self.weightIncrement = weightIncrement
        self.streakSaverEnabled = streakSaverEnabled
        self.streakSaverMinutes = streakSaverMinutes
    }

    /// Fields added after Phase 1 fall back to defaults, so older backups still import.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.defaults
        language = try c.decode(AppLanguage.self, forKey: .language)
        appearance = try c.decode(Appearance.self, forKey: .appearance)
        firstWeekday = try c.decode(Int.self, forKey: .firstWeekday)
        cycleStartDay = try c.decode(Int.self, forKey: .cycleStartDay)
        weightIncrement = try c.decode(Double.self, forKey: .weightIncrement)
        streakSaverEnabled = try c.decodeIfPresent(Bool.self, forKey: .streakSaverEnabled) ?? d.streakSaverEnabled
        streakSaverMinutes = try c.decodeIfPresent(Int.self, forKey: .streakSaverMinutes) ?? d.streakSaverMinutes
    }

    public init(from defaults: UserDefaults) {
        let d = Self.defaults
        language = defaults.string(forKey: SettingsKey.language).flatMap(AppLanguage.init) ?? d.language
        appearance = defaults.string(forKey: SettingsKey.appearance).flatMap(Appearance.init) ?? d.appearance
        firstWeekday = defaults.object(forKey: SettingsKey.firstWeekday) as? Int ?? d.firstWeekday
        cycleStartDay = defaults.object(forKey: SettingsKey.cycleStartDay) as? Int ?? d.cycleStartDay
        weightIncrement = defaults.object(forKey: SettingsKey.weightIncrement) as? Double ?? d.weightIncrement
        streakSaverEnabled = defaults.object(forKey: SettingsKey.streakSaverEnabled) as? Bool ?? d.streakSaverEnabled
        streakSaverMinutes = defaults.object(forKey: SettingsKey.streakSaverMinutes) as? Int ?? d.streakSaverMinutes
    }

    public func write(to defaults: UserDefaults) {
        defaults.set(language.rawValue, forKey: SettingsKey.language)
        defaults.set(appearance.rawValue, forKey: SettingsKey.appearance)
        defaults.set(firstWeekday, forKey: SettingsKey.firstWeekday)
        defaults.set(cycleStartDay, forKey: SettingsKey.cycleStartDay)
        defaults.set(weightIncrement, forKey: SettingsKey.weightIncrement)
        defaults.set(streakSaverEnabled, forKey: SettingsKey.streakSaverEnabled)
        defaults.set(streakSaverMinutes, forKey: SettingsKey.streakSaverMinutes)
    }
}

/// Catalog strings outside SwiftUI views (notifications, intents), in the language chosen in the app
/// rather than the system language. Strings live in the app / widget bundle (`Shared/Localizable.xcstrings`).
public enum L10n {
    public static func string(_ value: String.LocalizationValue, language: AppLanguage? = nil) -> String {
        let lang = language ?? SettingsSnapshot(from: .orbit).language
        return String(localized: LocalizedStringResource(value, locale: lang.locale))
    }

    /// Same, for a key only known at runtime (e.g. a built-in exercise name stored in the database).
    /// Falls back to the key itself when the bundle has no translation (e.g. in `swift test`).
    public static func string(key: String, language: AppLanguage? = nil) -> String {
        let lang = language ?? SettingsSnapshot(from: .orbit).language
        let bundle = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
