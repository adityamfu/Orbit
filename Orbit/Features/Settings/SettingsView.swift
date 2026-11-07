import SwiftUI
import UniformTypeIdentifiers
import OrbitData
import OrbitUI

struct SettingsView: View {
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @AppStorage(SettingsKey.appearance, store: .orbit) private var appearance = SettingsSnapshot.defaults.appearance
    @AppStorage(SettingsKey.firstWeekday, store: .orbit) private var firstWeekday = SettingsSnapshot.defaults.firstWeekday
    @AppStorage(SettingsKey.cycleStartDay, store: .orbit) private var cycleStartDay = SettingsSnapshot.defaults.cycleStartDay
    @AppStorage(SettingsKey.weightIncrement, store: .orbit) private var weightIncrement = SettingsSnapshot.defaults.weightIncrement
    /// Seconds since 1970; 0 = never backed up.
    @AppStorage(SettingsKey.lastBackupAt, store: .orbit) private var lastBackupAt: Double = 0
    @Environment(\.locale) private var locale

    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: Backup?
    /// 1 = first confirmation, 2 = final confirmation (SET-06 double confirm).
    @State private var importStep = 0
    @State private var importError: BackupImportError?

    var body: some View {
        Form {
            ScreenHeader(Text("settings.title"))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 0))

            Section {
                Picker("settings.section.language", selection: $language) {
                    Text(verbatim: "Indonesia").tag(AppLanguage.id)
                    Text(verbatim: "English").tag(AppLanguage.en)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("settings.section.language")
            } footer: {
                Text("settings.language.footer")
            }

            Section("settings.section.appearance") {
                Picker("settings.section.appearance", selection: $appearance) {
                    Text("settings.appearance.system").tag(Appearance.system)
                    Text("settings.appearance.light").tag(Appearance.light)
                    Text("settings.appearance.dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("settings.section.general") {
                Picker("settings.firstWeekday", selection: $firstWeekday) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.cycle", selection: $cycleStartDay) {
                    ForEach(1...28, id: \.self) { day in
                        Text("settings.cycle.day \(day)").tag(day)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("settings.weightIncrement", selection: $weightIncrement) {
                    ForEach([1.0, 1.25, 2.5, 5.0], id: \.self) { kg in
                        Text(kilograms(kg)).tag(kg)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                Button("backup.export", action: export)
                Button("backup.import") { showImporter = true }
            } header: {
                Text("settings.section.data")
            } footer: {
                if lastBackupAt > 0 {
                    Text("backup.last \(dateText(Date(timeIntervalSince1970: lastBackupAt)))")
                } else {
                    Text("backup.never")
                }
            }

            Section("settings.section.about") {
                LabeledContent("settings.version", value: BuildInfo.version)
                LabeledContent("settings.buildExpiry") {
                    Text(BuildInfo.expirationDate.map(dateText) ?? "—")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: BackupService.fileName()
        ) { result in
            if case .success = result { lastBackupAt = Date.now.timeIntervalSince1970 }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], onCompletion: readImport)
        .confirmationDialog(
            "backup.import.confirm.title",
            isPresented: step(1),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { _ in
            Button("backup.import.replace", role: .destructive) { importStep = 2 }
        } message: { backup in
            Text("backup.import.confirm.message \(dateText(backup.exportedAt))")
        }
        .alert("backup.import.final.title", isPresented: step(2), presenting: pendingImport) { backup in
            Button("backup.import.final.confirm", role: .destructive) {
                BackupService.restore(backup, into: .orbit)
                pendingImport = nil
            }
            Button("common.cancel", role: .cancel) { pendingImport = nil }
        } message: { _ in
            Text("backup.import.final.message")
        }
        .alert("backup.error.title", isPresented: .init(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("common.ok", role: .cancel) {}
        } message: {
            if importError == .newer {
                Text("backup.error.newer")
            } else {
                Text("backup.error.invalid")
            }
        }
    }

    private func step(_ n: Int) -> Binding<Bool> {
        Binding(get: { importStep == n }, set: { if !$0 && importStep == n { importStep = 0 } })
    }

    private func export() {
        guard let data = try? BackupService.export(from: .orbit) else { return }
        exportDocument = BackupDocument(data: data)
        showExporter = true
    }

    private func readImport(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingImport = try BackupService.read(Data(contentsOf: url))
            importStep = 1
        } catch BackupError.newerSchema {
            importError = .newer
        } catch {
            importError = .invalid
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.standaloneWeekdaySymbols[weekday - 1]
    }

    private func kilograms(_ kg: Double) -> String {
        Measurement(value: kg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }
}

enum BackupImportError { case newer, invalid }

/// JSON backup file for `.fileExporter`.
nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview("Light") {
    NavigationStack { SettingsView() }
}

#Preview("Dark, English, large type") {
    NavigationStack { SettingsView() }
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
