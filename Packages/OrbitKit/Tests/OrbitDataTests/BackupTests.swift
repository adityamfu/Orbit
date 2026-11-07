import Foundation
import SwiftData
import Testing
import OrbitEngine
@testable import OrbitData

func freshDefaults() -> UserDefaults {
    let name = "orbit-test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

func freshContext() throws -> ModelContext {
    ModelContext(try OrbitData.makeContainer(inMemory: true))
}

struct BackupTests {
    @Test func roundTripKeepsSettingsHabitsAndLogs() throws {
        let source = freshDefaults()
        let custom = SettingsSnapshot(language: .en, appearance: .dark, firstWeekday: 1, cycleStartDay: 25, weightIncrement: 1.25)
        custom.write(to: source)
        let ctx = try freshContext()
        let water = Habit(name: "Minum air", iconName: "drop", type: .count, targetCount: 8, unit: "gelas",
                          schedule: .weekdays([2, 4]), reminderMinutes: [480, 1260], sortOrder: 1)
        let cook = Habit(name: "Masak", iconName: "frying.pan", schedule: .timesPerWeek(3), isArchived: true)
        ctx.insert(water)
        ctx.insert(cook)
        HabitRepository.setValue(5, for: water, day: 20261106, in: ctx)
        HabitRepository.setSkipped(true, for: water, day: 20261105, calculator: HabitCalculator(firstWeekday: 2), in: ctx)
        HabitRepository.toggle(cook, day: 20261104, in: ctx)
        try ctx.save()

        let data = try BackupService.export(from: source, context: ctx)
        let targetDefaults = freshDefaults()
        let targetCtx = try freshContext()
        try BackupService.restore(try BackupService.read(data), into: targetDefaults, context: targetCtx)

        #expect(SettingsSnapshot(from: targetDefaults) == custom)
        let again = try BackupService.read(BackupService.export(from: targetDefaults, context: targetCtx))
        let first = try BackupService.read(data)
        #expect(again.habits == first.habits)
        #expect(first.habits.count == 2)
        #expect(first.habits.first { $0.name == "Minum air" }?.logs.count == 2)
    }

    @Test func restoreReplacesExistingHabits() throws {
        let ctx = try freshContext()
        ctx.insert(Habit(name: "Lama", iconName: "star"))
        try ctx.save()
        let backup = Backup(exportedAt: .now, settings: .defaults, habits: [])
        try BackupService.restore(backup, into: freshDefaults(), context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Habit>()) == 0)
    }

    @Test func importsVersion1FilesWithoutHabits() throws {
        let v1 = """
        {"schemaVersion":1,"exportedAt":"2026-11-07T04:08:40Z",
         "settings":{"appearance":"system","cycleStartDay":1,"firstWeekday":2,"language":"id","weightIncrement":2.5}}
        """
        let backup = try BackupService.read(Data(v1.utf8))
        #expect(backup.habits.isEmpty)
        #expect(backup.settings == .defaults)
    }

    @Test func rejectsNewerSchema() throws {
        var backup = Backup(exportedAt: .now, settings: .defaults)
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
