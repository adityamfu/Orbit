import SwiftUI
import OrbitData
import OrbitUI

@main
struct OrbitApp: App {
    init() { OrbitFonts.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
