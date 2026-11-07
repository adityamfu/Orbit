import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Icon-only tab bar (DESIGN.md §4). Labels stay for VoiceOver.
struct RootView: View {
    var body: some View {
        TabView {
            Tab { TodayView() } label: { tabLabel("tab.today", "circle.circle") }
            Tab { ComingSoonView(title: "tab.finance", icon: "wallet.bifold") } label: { tabLabel("tab.finance", "wallet.bifold") }
            Tab { ComingSoonView(title: "tab.habits", icon: "checkmark.circle") } label: { tabLabel("tab.habits", "checkmark.circle") }
            Tab { ComingSoonView(title: "tab.workout", icon: "dumbbell") } label: { tabLabel("tab.workout", "dumbbell") }
            Tab { ComingSoonView(title: "tab.insights", icon: "chart.line.uptrend.xyaxis") } label: {
                tabLabel("tab.insights", "chart.line.uptrend.xyaxis")
            }
        }
        .tint(Color.orbit.accent)
    }

    private func tabLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        // Outline icons like the design; the tab bar would otherwise switch to .fill.
        Label(title, systemImage: icon).labelStyle(.iconOnly).environment(\.symbolVariants, .none)
    }
}

/// Placeholder for tabs built in later phases.
struct ComingSoonView: View {
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                ScreenHeader(Text(title))
                ContentUnavailableView {
                    Label(title, systemImage: icon)
                } description: {
                    Text("placeholder.description")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.orbit.bg)
        }
    }
}

#Preview("Light") {
    RootView()
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Dark, English") {
    RootView()
        .modelContainer(OrbitData.makePreviewContainer())
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
}
