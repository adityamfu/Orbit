import SwiftUI

/// Custom screen title in Inter Tight with an optional caption (marked with the orb-chip)
/// and a trailing action. Used instead of `.navigationTitle` so every title uses the brand font.
public struct ScreenHeader<Trailing: View>: View {
    let title: Text
    let caption: Text?
    let trailing: Trailing

    public init(_ title: Text, caption: Text? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let caption {
                    HStack(spacing: 6) {
                        OrbChip().fill(Color.orbit.accent).orbChipFrame(height: 7)
                            .accessibilityHidden(true)
                        caption
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.orbit.textSecondary)
                    }
                }
                title
                    .font(Typography.largeTitle)
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

#Preview("Light") {
    ScreenHeader(Text(verbatim: "Hari Ini"), caption: Text(verbatim: "Sabtu, 7 November")) {
        Image(systemName: "gearshape")
    }
    .padding()
}

#Preview("Dark, large type") {
    ScreenHeader(Text(verbatim: "Pengaturan"))
        .padding()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
