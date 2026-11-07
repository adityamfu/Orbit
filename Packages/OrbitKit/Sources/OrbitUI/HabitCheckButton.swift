import SwiftUI

/// The look of a habit's trailing control. Pure visual, so widgets can wrap it in `Button(intent:)`.
public struct HabitCheckMark: View {
    public enum State: Equatable {
        case check(done: Bool)
        case count(value: Int, target: Int)
        case skipped
    }

    let state: State
    let size: CGFloat

    public init(_ state: State, size: CGFloat = 34) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch state {
            case .check(let done):
                if done {
                    Circle().fill(Color.orbit.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Color.orbit.onAccent)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 2)
                }
            case .count(let value, let target):
                MiniRing(progress: Double(value) / Double(max(target, 1)), lineWidth: 3) {
                    Image(systemName: value >= target ? "checkmark" : "plus")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Color.orbit.accent)
                }
            case .skipped:
                Circle().fill(Color.orbit.iconTile)
                Image(systemName: "forward.end")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    var isDone: Bool {
        switch state {
        case .check(let done): done
        case .count(let value, let target): value >= target
        case .skipped: true
        }
    }
}

/// Trailing control of a habit row in the app: the check mark as a button, with haptics.
public struct HabitCheckButton: View {
    public typealias State = HabitCheckMark.State

    let mark: HabitCheckMark
    let label: Text
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `label` is the VoiceOver name of the action, e.g. "Mark done".
    public init(_ state: State, label: Text, action: @escaping () -> Void) {
        self.mark = HabitCheckMark(state)
        self.label = label
        self.action = action
    }

    public var body: some View {
        let isDone = mark.isDone
        Button(action: action) {
            mark
                .scaleEffect(isDone && !reduceMotion ? 1 : 0.94)
                .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.4), value: isDone)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isDone ? .isSelected : [])
        .sensoryFeedback(.success, trigger: isDone) { old, new in !old && new }
    }
}

/// Round 38 pt "+" button in screen headers.
public struct RoundAddButton: View {
    let label: Text
    let action: () -> Void

    public init(label: Text, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.orbit.onPrimary)
                .frame(width: 44, height: 44)
                .background(Color.orbit.primary, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Capsule button filled with the lime primary, black content (DESIGN.md §3.1).
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        // One line when it fits; wraps instead of clipping at large Dynamic Type sizes.
        ViewThatFits(in: .horizontal) {
            configuration.label.lineLimit(1)
            configuration.label
        }
            .multilineTextAlignment(.center)
            .font(.headline)
            .foregroundStyle(Color.orbit.onPrimary)
            .padding(.horizontal, 24)
            .frame(minHeight: 50)
            .background(Color.orbit.primary, in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var orbitPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

#Preview {
    VStack(spacing: 16) {
        HStack {
            HabitCheckButton(.check(done: false), label: Text(verbatim: "Done")) {}
            HabitCheckButton(.check(done: true), label: Text(verbatim: "Done")) {}
            HabitCheckButton(.count(value: 3, target: 8), label: Text(verbatim: "+1")) {}
            HabitCheckButton(.count(value: 8, target: 8), label: Text(verbatim: "+1")) {}
            HabitCheckButton(.skipped, label: Text(verbatim: "Skipped")) {}
        }
        RoundAddButton(label: Text(verbatim: "Add")) {}
        Button(String("Tambah habit pertamamu")) {}.buttonStyle(.orbitPrimary)
    }
    .padding()
}

/// Capsule button on a grey tile, for the second choice next to a primary button ("Sesi kosong").
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 20)
            .frame(minHeight: 50)
            .background(Color.orbit.iconTile, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var orbitSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
