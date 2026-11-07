import Foundation

/// The whole backup file. Each phase adds its data arrays here and bumps `currentSchemaVersion`
/// when the format changes in a way older builds cannot read.
public struct Backup: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var settings: SettingsSnapshot

    public init(schemaVersion: Int = Backup.currentSchemaVersion, exportedAt: Date, settings: SettingsSnapshot) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

public enum BackupError: Error, Equatable {
    /// The file was made by a newer Orbit build than this one.
    case newerSchema(Int)
}

public enum BackupService {
    public static func export(from defaults: UserDefaults, now: Date = .now) throws -> Data {
        try encoder.encode(Backup(exportedAt: now, settings: SettingsSnapshot(from: defaults)))
    }

    /// Parses and validates without touching anything, so the UI can confirm before replacing.
    public static func read(_ data: Data) throws -> Backup {
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.schemaVersion <= Backup.currentSchemaVersion else {
            throw BackupError.newerSchema(backup.schemaVersion)
        }
        return backup
    }

    /// "Replace all" import.
    public static func restore(_ backup: Backup, into defaults: UserDefaults) {
        backup.settings.write(to: defaults)
    }

    public static func fileName(for date: Date = .now) -> String {
        "Orbit-backup-\(date.formatted(.iso8601.year().month().day()))"
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
