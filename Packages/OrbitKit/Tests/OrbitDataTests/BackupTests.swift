import Foundation
import Testing
@testable import OrbitData

struct BackupTests {
    func freshDefaults() -> UserDefaults {
        let name = "orbit-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func roundTripKeepsEverySetting() throws {
        let source = freshDefaults()
        let custom = SettingsSnapshot(language: .en, appearance: .dark, firstWeekday: 1, cycleStartDay: 25, weightIncrement: 1.25)
        custom.write(to: source)

        let data = try BackupService.export(from: source)
        let target = freshDefaults()
        BackupService.restore(try BackupService.read(data), into: target)

        #expect(SettingsSnapshot(from: target) == custom)
    }

    @Test func emptyDefaultsExportDefaults() throws {
        let backup = try BackupService.read(BackupService.export(from: freshDefaults()))
        #expect(backup.settings == .defaults)
        #expect(backup.schemaVersion == Backup.currentSchemaVersion)
    }

    @Test func rejectsNewerSchema() throws {
        var backup = try BackupService.read(BackupService.export(from: freshDefaults()))
        backup.schemaVersion = Backup.currentSchemaVersion + 1
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        #expect(throws: BackupError.newerSchema(backup.schemaVersion)) {
            try BackupService.read(try enc.encode(backup))
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try BackupService.read(Data("not json".utf8)) }
    }
}

struct BuildInfoTests {
    @Test func readsExpiryFromSignedProfile() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-11-14T03:00:00Z</date></dict></plist>
        """
        // Real profiles wrap the plist in binary CMS bytes on both sides.
        let blob = Data([0x30, 0x82, 0x00, 0xFF]) + Data(plist.utf8) + Data([0x00, 0xA0, 0x82])
        let expected = try Date("2026-11-14T03:00:00Z", strategy: .iso8601)
        #expect(BuildInfo.expirationDate(fromProfile: blob) == expected)
        #expect(BuildInfo.expirationDate(fromProfile: Data([0x01, 0x02])) == nil)
    }

    @Test func daysRemainingRoundsDown() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(BuildInfo.daysRemaining(until: now.addingTimeInterval(86_400 * 2.5), now: now) == 2)
        #expect(BuildInfo.daysRemaining(until: now.addingTimeInterval(-86_400 * 1.5), now: now) == -1)
    }
}
