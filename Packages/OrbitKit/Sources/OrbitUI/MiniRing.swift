import SwiftUI

/// Progress ring for KPIs, the habit week strip, widgets and the lock screen.
public struct MiniRing<Label: View>: View {
    let progress: Double
    let lineWidth: CGFloat
    let label: Label

    public init(progress: Double, lineWidth: CGFloat = 4, @ViewBuilder label: () -> Label = { EmptyView() }) {
        self.progress = min(max(progress, 0), 1)
        self.lineWidth = lineWidth
        self.label = label()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.orbit.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orbit.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .padding(lineWidth / 2)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: progress)
    }
}

#Preview {
    HStack(spacing: 16) {
        MiniRing(progress: 0).frame(width: 36, height: 36)
        MiniRing(progress: 0.4).frame(width: 36, height: 36)
        MiniRing(progress: 1).frame(width: 36, height: 36)
        MiniRing(progress: 2 / 6, lineWidth: 10) {
            Text(verbatim: "2/6").font(Typography.metric)
        }
        .frame(width: 96, height: 96)
    }
    .padding()
}
