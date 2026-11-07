import SwiftUI
import OrbitData
import OrbitUI

struct TodayView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(Text("tab.today"), caption: Text(dateCaption)) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.title3)
                                .foregroundStyle(Color.primary)
                                .frame(width: 44, height: 44)
                                .background(Color.orbit.card, in: .circle)
                        }
                        .accessibilityLabel(Text("settings.title"))
                    }

                    if let expiry = BuildInfo.expirationDate {
                        let days = BuildInfo.daysRemaining(until: expiry)
                        if days <= 2 { ExpiryBanner(days: days) }
                    }

                    // Heatmap, stats, habits and workout cards arrive in Phase 6.
                    ContentUnavailableView {
                        Label("tab.today", systemImage: "circle.circle")
                    } description: {
                        Text("placeholder.description")
                    }
                }
                .padding(16)
            }
            .background(Color.orbit.bg)
            // Title only feeds the back button in pushed screens ("‹ Hari Ini"); the bar stays hidden.
            .navigationTitle(Text("tab.today"))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var dateCaption: String {
        Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }
}

/// TOD-06: free-account builds stop opening after 7 days.
struct ExpiryBanner: View {
    let days: Int

    var body: some View {
        Label {
            if days <= 0 {
                Text("build.expiry.today")
            } else {
                Text("build.expiry.days \(days)")
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orbit.accent)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orbit.accentSoft, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

#Preview("Today") {
    TodayView()
}

#Preview("Expiry banner") {
    VStack {
        ExpiryBanner(days: 2)
        ExpiryBanner(days: 0)
    }
    .padding()
    .environment(\.locale, Locale(identifier: "id_ID"))
}
