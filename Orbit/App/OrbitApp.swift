import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

@main
struct OrbitApp: App {
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @AppStorage(SettingsKey.appearance, store: .orbit) private var appearance = SettingsSnapshot.defaults.appearance
    @Environment(\.scenePhase) private var scenePhase
    private let coordinator = SessionCoordinator.shared

    private let container: ModelContainer

    init() {
        OrbitFonts.register()
        do {
            container = try Self.openStore()
        } catch {
            // Nothing works without the store; crash loudly in development rather than run with no data.
            fatalError("Could not open the Orbit store: \(error)")
        }
        // Built-in exercise library (WRK-01); no-op once seeded, retried next launch if it fails.
        _ = try? ExerciseLibrary.seedIfNeeded(ModelContext(container))
        // Reopen a session left running, and wire Live Activity buttons (they can launch the app in the background).
        coordinator.attach(container)
    }

    /// After an update the widget extension can open (and migrate) the shared store at the same
    /// moment as the app; the loser gets a "model incompatible" error. Retrying after the other
    /// process finishes opens the already-migrated store.
    private static func openStore(attempts: Int = 4) throws -> ModelContainer {
        var lastError: (any Error)?
        for attempt in 0..<attempts {
            do {
                return try OrbitData.makeContainer()
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.4 * Double(attempt + 1))
            }
        }
        throw lastError!
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environment(coordinator)
                .environment(\.locale, language.locale)
                .onChange(of: appearance, initial: true) { _, value in apply(value) }
                // Notifications follow the data and the app language (NTF rules: re-plan on open and on change).
                .onChange(of: language) { NotificationScheduler.requestReschedule() }
                .onChange(of: scenePhase) { _, phase in if phase == .active { NotificationScheduler.requestReschedule() } }
        }
    }

    /// `.preferredColorScheme(nil)` doesn't switch back to System on iOS 18 once Light/Dark was forced,
    /// so the style is set on the window instead (the only UIKit touch in the app).
    private func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
