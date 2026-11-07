import SwiftUI

/// Trailing control of a habit row: check circle, skipped mark, or a +1 ring for count habits.
public struct HabitCheckButton: View {
    public enum State: Equatable {
        case check(done: Bool)
        case count(value: Int, target: Int)
        case skipped
    }

    let state: State
    let label: Text
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `label` is the VoiceOver name of the action, e.g. "Mark done".
    public init(_ state: State, label: Text, action: @escaping () -> Void) {
        self.state = state
        self.label = label
        self.action = action
    }

    private var isDone: Bool {
        switch state {
        case .check(let done): done
        case .count(let value, let target): value >= target
        case .skipped: true
        }
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                switch state {
                case .check(let done):
                    if done {
                        Circle().fill(Color.orbit.accent)
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.orbit.onAccent)
                    } else {
                        Circle().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 2)
                    }
                case .count(let value, let target):
                    MiniRing(progress: Double(value) / Double(max(target, 1)), lineWidth: 3) {
                        Image(systemName: value >= target ? "checkmark" : "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.orbit.accent)
                    }
                case .skipped:
                    Circle().fill(Color.orbit.iconTile)
                    Image(systemName: "forward.end")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)
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
            configuration.label.fixedSize()
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
