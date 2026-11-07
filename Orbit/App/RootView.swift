import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Icon-only tab bar (DESIGN.md §4). Labels stay for VoiceOver.
struct RootView: View {
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        TabView {
            Tab { TodayView().sessionMiniBar() } label: { tabLabel("tab.today", "circle.circle") }
            Tab { FinanceView().sessionMiniBar() } label: { tabLabel("tab.finance", "wallet.bifold") }
            Tab { HabitsView().sessionMiniBar() } label: { tabLabel("tab.habits", "checkmark.circle") }
            Tab { WorkoutView().sessionMiniBar() } label: { tabLabel("tab.workout", "dumbbell") }
            Tab { ComingSoonView(title: "tab.insights", icon: "chart.line.uptrend.xyaxis").sessionMiniBar() } label: {
                tabLabel("tab.insights", "chart.line.uptrend.xyaxis")
            }
        }
        .tint(Color.orbit.accent)
        // WRK-14: the running session is full screen and always dark.
        .fullScreenCover(isPresented: $coordinator.isPresented) {
            ActiveSessionView()
        }
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
        .environment(SessionCoordinator())
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Dark, English") {
    RootView()
        .environment(SessionCoordinator())
        .modelContainer(OrbitData.makePreviewContainer())
        .environment(\.locale, Locale(identifier: "en_US"))
        .preferredColorScheme(.dark)
}
