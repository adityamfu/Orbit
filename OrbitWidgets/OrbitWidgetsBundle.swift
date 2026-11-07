import SwiftUI
import WidgetKit
import OrbitUI

@main
struct OrbitWidgetsBundle: WidgetBundle {
    init() { OrbitFonts.register() }

    var body: some Widget {
        OrbitWidgets()
        OrbitWidgetsLiveActivity()
    }
}
