import SwiftUI

/// The comet mark from the logo (DESIGN.md §2.3): half-circle left end, flat top with a sharp
/// top-right corner, and a full-height quarter circle curving down on the right.
/// Measured from the master asset (144×68). Use sparingly — at most one per visible screen.
public struct OrbChip: Shape {
    public static let aspectRatio: CGFloat = 144.0 / 68.0

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let h = rect.height
        return UnevenRoundedRectangle(
            topLeadingRadius: h / 2,
            bottomLeadingRadius: h / 2,
            bottomTrailingRadius: h,
            topTrailingRadius: 0,
            style: .circular
        ).path(in: rect)
    }
}

public extension View {
    /// Sizes a view (usually `OrbChip()`) to the chip's proportions at the given height.
    func orbChipFrame(height: CGFloat) -> some View {
        frame(width: height * OrbChip.aspectRatio, height: height)
    }
}

#Preview {
    VStack(spacing: 24) {
        OrbChip().fill(Color.orbit.accent).orbChipFrame(height: 68)
        OrbChip().fill(Color.orbit.primary).orbChipFrame(height: 34)
            .padding().background(Color.orbit.ink)
        OrbChip().fill(Color.orbit.accent).orbChipFrame(height: 8)
    }
    .padding()
}
