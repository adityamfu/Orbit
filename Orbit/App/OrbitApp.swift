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
        _ = try? CategoryLibrary.seedIfNeeded(ModelContext(container))
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
                // orbit://workout from the Workout widget: start today's routine or reopen the running session.
                .onOpenURL { url in
                    guard url.host == "workout" else { return }
                    let routines = (try? container.mainContext.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
                    coordinator.start(template: WorkoutHistory.routine(for: .now, in: routines),
                                      increment: SettingsSnapshot(from: .orbit).weightIncrement, context: container.mainContext)
                }
                // Notifications follow the data and the app language (NTF rules: re-plan on open and on change).
                .onChange(of: language) { NotificationScheduler.requestReschedule() }
                // Sync Apple Health when the app opens or returns to foreground (HLT-04).
                // shortcut: HealthKit queries run on the main actor via semaphore.wait(), so the UI may
                //   freeze briefly on first import. Ceiling: noticeable pause on cold start with lots of
                //   Health data. Upgrade path: move importWorkouts to a background Task with async HKQuery.
                .task {
                    if HealthKitService.shared.isAvailable {
                        try? await HealthKitService.shared.requestAuthorization()
                        _ = await HealthKitService.shared.importWorkouts(into: container.mainContext)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        NotificationScheduler.requestReschedule()
                        if HealthKitService.shared.isAvailable {
                            Task {
                                try? await HealthKitService.shared.requestAuthorization()
                                _ = await HealthKitService.shared.importWorkouts(into: container.mainContext)
                            }
                        }
                    }
                }
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
