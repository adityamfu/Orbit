import SwiftUI
import OrbitUI

/// One stat card in the 2×2 grid (TOD-02).
struct TodayStatCard: View {
    let title: LocalizedStringKey
    let icon: String
    let value: String
    let subtitle: String
    let color: Color
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.orbit.textSecondary)
                Spacer()
            }
            Text(value).font(Typography.statHero).foregroundStyle(color).tracking(-1.5)
            Text(subtitle).font(.caption).foregroundStyle(Color.orbit.textSecondary)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.orbit.track)
                        Capsule().fill(color).frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 28, style: .continuous))
    }
}

#Preview("Stat cards") {
    VStack(spacing: 12) {
        TodayStatCard(title: "Streak", icon: "flame", value: "12", subtitle: "15 hari terpanjang", color: Color.orbit.accent)
        TodayStatCard(title: "Target", icon: "target", value: "75%", subtitle: "pencapaian target minggu", color: Color.orbit.accent, progress: 0.75)
    }
    .padding()
    .background(Color.orbit.bg)
}
