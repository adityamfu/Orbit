import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

@main
struct OrbitApp: App {
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @AppStorage(SettingsKey.appearance, store: .orbit) private var appearance = SettingsSnapshot.defaults.appearance

    private let container: ModelContainer

    init() {
        OrbitFonts.register()
        do {
            container = try OrbitData.makeContainer()
        } catch {
            // Nothing works without the store; crash loudly in development rather than run with no data.
            fatalError("Could not open the Orbit store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environment(\.locale, language.locale)
                .onChange(of: appearance, initial: true) { _, value in apply(value) }
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
