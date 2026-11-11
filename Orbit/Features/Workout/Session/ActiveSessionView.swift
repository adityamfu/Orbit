import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Running workout (DESIGN.md §5.6, canvas p.7). Always dark; shown full screen from RootView.
struct ActiveSessionView: View {
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.weightIncrement, store: .orbit) private var increment = SettingsSnapshot.defaults.weightIncrement
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @State private var picking = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

    var body: some View {
        let _ = coordinator.version
        Group {
            if let summary = coordinator.summary {
                SessionSummaryView(finished: summary) { coordinator.closeSummary() }
            } else if let session = coordinator.session {
                content(session)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private func content(_ session: WorkoutSession) -> some View {
        let entries = SessionRepository.exercises(in: session)
        let history = coordinator.history(context)
        let allSets = entries.flatMap(\.sets)
        let done = allSets.count(where: \.isCompleted)
        let current = entries.firstIndex { $0.sets.contains { !$0.isCompleted } } ?? max(entries.count - 1, 0)

        return VStack(spacing: 0) {
            header(session)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        if let name = session.template?.name { Text(name) } else { Text("workout.emptySession") }
                    }
                    .font(Typography.largeTitle)
                    .tracking(-0.6)

                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(done), total: Double(max(allSets.count, 1)))
                            .tint(Color.orbit.primary)
                        Text("session.progress \(entries.isEmpty ? 0 : current + 1) \(entries.count) \(done) \(allSets.count)")
                            .font(.subheadline)
                            .foregroundStyle(Color.orbit.textSecondary)
                    }

                    ForEach(entries) { entry in
                        ExerciseCard(entry: entry, session: session, history: history, increment: increment,
                                     language: language, isLast: entry.order == entries.last?.order)
                    }

                    Button { picking = true } label: {
                        Label("routine.form.addExercise", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.orbitSecondary)

                    Button("session.discard", role: .destructive) { confirmDiscard = true }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            if coordinator.restEnd != nil {
                RestTimerPill(exerciseName: entries.indices.contains(current)
                              ? entries[current].exercise.displayName(language: language) : "")
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: done) { old, new in new > old }
        .sensoryFeedback(.warning, trigger: coordinator.restFinished)
        .sheet(isPresented: $picking) {
            ExercisePickerView { exercise in
                SessionRepository.addExercise(exercise, to: session, history: history, increment: increment, in: context)
                coordinator.touch()
            }
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("session.finish.title", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("session.finish") { Task { await coordinator.finish(context: context) } }
        } message: {
            if done == 0 {
                Text("session.finish.nothing")
            } else if done < allSets.count {
                Text("session.finish.unticked \(allSets.count - done)")
            }
        }
        .confirmationDialog("session.discard.title", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("session.discard", role: .destructive) { coordinator.discard(context: context) }
        } message: {
            Text("session.discard.message")
        }
    }

    private func header(_ session: WorkoutSession) -> some View {
        HStack {
            Button { coordinator.isPresented = false } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.orbit.card, in: .circle)
            }
            .accessibilityLabel(Text("session.minimize"))
            Spacer()
            Text(session.startedAt, style: .timer)
                .font(.custom("InterTight-ExtraBold", size: 22, relativeTo: .title2).monospacedDigit())
            Spacer()
            Button("session.finish") { confirmFinish = true }
                .font(.headline)
                .foregroundStyle(Color.orbit.onPrimary)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Color.orbit.primary, in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Exercise card

private struct ExerciseCard: View {
    let entry: SessionExercise
    let session: WorkoutSession
    let history: [WorkoutSession]
    let increment: Double
    let language: AppLanguage
    let isLast: Bool
    @Environment(SessionCoordinator.self) private var coordinator
    @Environment(\.modelContext) private var context

    var body: some View {
        let kind = entry.exercise.type
        let previous = SessionRepository.previousSets(for: entry.exercise, before: session, history: history)
            .filter { !$0.isWarmup }
        // Warm-ups show "W"; working sets are numbered and line up with last session's working sets.
        let rows: [(set: WorkoutSet, label: String, prior: SetRecord?)] = {
            var n = 0
            return entry.sets.map { set in
                guard !set.isWarmup else { return (set, "W", nil) }
                n += 1
                return (set, "\(n)", previous.indices.contains(n - 1) ? previous[n - 1] : nil)
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exerciseKey: entry.exercise)
                    .font(.custom("InterTight-Bold", size: 22, relativeTo: .title2))
                Spacer()
                menu
            }

            if kind == .weightReps {
                TargetBox(suggestion: Progression.suggest(
                    sessions: WorkoutHistory.setsPerSession(exerciseID: entry.exercise.id, in: history),
                    repMin: entry.repRange.lowerBound, repMax: entry.repRange.upperBound,
                    increment: increment, isLowerBody: entry.exercise.isLowerBody), range: entry.repRange)
            }

            SetHeader(kind: kind)
            ForEach(rows, id: \.set.id) { row in
                SetRow(set: row.set, label: row.label, previous: row.prior, kind: kind) { toggle(row.set) } onDelete: {
                    SessionRepository.deleteSet(row.set, from: session, in: context)
                    coordinator.touch()
                }
            }

            Button {
                SessionRepository.addSet(to: session, exerciseOrder: entry.order, in: context)
                coordinator.touch()
            } label: {
                Label("session.addSet", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private var menu: some View {
        Menu {
            Button("session.addWarmup", systemImage: "flame") {
                SessionRepository.addSet(to: session, exerciseOrder: entry.order, warmup: true, in: context)
                coordinator.touch()
            }
            Button("session.moveUp", systemImage: "arrow.up") { move(-1) }.disabled(entry.order == 0)
            Button("session.moveDown", systemImage: "arrow.down") { move(1) }.disabled(isLast)
            Button("session.removeExercise", systemImage: "trash", role: .destructive) {
                SessionRepository.removeExercise(order: entry.order, from: session, in: context)
                coordinator.touch()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.bold))
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: .circle)
        }
        .accessibilityLabel(Text("session.exerciseMenu"))
    }

    private func move(_ delta: Int) {
        SessionRepository.moveExercise(order: entry.order, by: delta, in: session, in: context)
        coordinator.touch()
    }

    private func toggle(_ set: WorkoutSet) {
        let completing = !set.isCompleted
        SessionRepository.setCompleted(set, completing, in: context)
        if completing, entry.exercise.type != .cardio {
            coordinator.startRest(seconds: set.isWarmup ? min(entry.restSec, 60) : entry.restSec,
                                  exerciseName: entry.exercise.displayName(language: language))
        }
        coordinator.touch()
    }
}

/// Engine target + reason (KPI-04), e.g. "↑ Target 62,5 kg × 8–12".
private struct TargetBox: View {
    let suggestion: ProgressionSuggestion
    let range: ClosedRange<Int>
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.headline)
                .foregroundStyle(Color.orbit.primary)
            reason
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orbit.primary.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var weight: String { kg(suggestion.weightKg ?? 0) }

    private func kg(_ value: Double) -> String {
        Measurement(value: value, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2))).locale(locale))
    }

    @ViewBuilder private var title: some View {
        switch suggestion.reason {
        case .calibration: Text("session.target.calibration \(range.lowerBound) \(range.upperBound)")
        case .increase: Text("session.target.up \(weight) \(range.lowerBound) \(range.upperBound)")
        case .hold: Text("session.target.hold \(weight) \(range.lowerBound) \(range.upperBound)")
        case .decrease: Text("session.target.down \(weight) \(range.lowerBound) \(range.upperBound)")
        }
    }

    @ViewBuilder private var reason: some View {
        switch suggestion.reason {
        case .calibration: Text("session.reason.calibration")
        case .increase(let byKg, let reps): Text("session.reason.up \(reps) \(kg(byKg))")
        case .hold: Text("session.reason.hold \(range.upperBound)")
        case .decrease(let percent): Text("session.reason.down \(percent)")
        }
    }
}

// MARK: - Set table

private struct SetHeader: View {
    let kind: ExerciseKind

    var body: some View {
        HStack(spacing: 8) {
            Text("session.col.set").frame(width: 30, alignment: .leading)
            Text("session.col.previous").frame(maxWidth: .infinity, alignment: .leading)
            switch kind {
            case .weightReps:
                Text("session.col.kg").frame(width: 68)
                Text("session.col.reps").frame(width: 52)
            case .bodyweight: Text("session.col.reps").frame(width: 68)
            case .duration: Text("session.col.seconds").frame(width: 68)
            case .cardio:
                Text("session.col.minutes").frame(width: 52)
                Text("session.col.km").frame(width: 52)
            }
            Color.clear.frame(width: 44, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.orbit.textSecondary)
        .padding(.horizontal, 8)
    }
}

private struct SetRow: View {
    let set: WorkoutSet
    let label: String
    let previous: SetRecord?
    let kind: ExerciseKind
    let onToggle: () -> Void
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: label)
                .font(.custom("InterTight-Bold", size: 17, relativeTo: .body))
                .foregroundStyle(set.isWarmup ? Color.orbit.primary : Color.primary)
                .frame(width: 30, alignment: .leading)
            Text(verbatim: previousText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.orbit.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            fields
            Button(action: onToggle) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(set.isCompleted ? Color.orbit.primary : Color.clear)
                    .strokeBorder(set.isCompleted ? Color.clear : Color.secondary.opacity(0.5), lineWidth: 2)
                    .frame(width: 38, height: 38)
                    .overlay {
                        if set.isCompleted {
                            Image(systemName: "checkmark").font(.headline).foregroundStyle(Color.orbit.onPrimary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)  // the unticked box is clear inside; make all of it tappable
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(set.isCompleted ? "habits.a11y.undo" : "session.a11y.completeSet"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(set.isCompleted ? Color.orbit.primary.opacity(0.14) : Color.clear,
                    in: .rect(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button("session.deleteSet", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder private var fields: some View {
        switch kind {
        case .weightReps:
            NumberField(value: Binding(get: { set.weightKg }, set: { set.weightKg = $0 }), decimal: true, done: set.isCompleted)
                .frame(width: 68)
            NumberField(value: int(\.reps), decimal: false, done: set.isCompleted).frame(width: 52)
        case .bodyweight:
            NumberField(value: int(\.reps), decimal: false, done: set.isCompleted).frame(width: 68)
        case .duration:
            NumberField(value: int(\.durationSec), decimal: false, done: set.isCompleted).frame(width: 68)
        case .cardio:
            NumberField(value: Binding(get: { set.durationSec.map { Double($0) / 60 } },
                                       set: { set.durationSec = $0.map { Int(($0 * 60).rounded()) } }),
                        decimal: true, done: set.isCompleted).frame(width: 52)
            NumberField(value: Binding(get: { set.distanceM.map { $0 / 1000 } }, set: { set.distanceM = $0.map { $0 * 1000 } }),
                        decimal: true, done: set.isCompleted).frame(width: 52)
        }
    }

    private func int(_ path: ReferenceWritableKeyPath<WorkoutSet, Int?>) -> Binding<Double?> {
        Binding(get: { set[keyPath: path].map(Double.init) }, set: { set[keyPath: path] = $0.map { Int($0.rounded()) } })
    }

    private var previousText: String {
        guard let p = previous else { return "—" }
        let n = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)).locale(locale)
        switch kind {
        case .weightReps:
            guard let w = p.weightKg, w > 0 else { return "× \(p.reps ?? 0)" }
            return "\(w.formatted(n)) × \(p.reps ?? 0)"
        case .bodyweight: return "× \(p.reps ?? 0)"
        case .duration: return locale.localized("session.seconds \(p.durationSec ?? 0)")
        case .cardio:
            let min = locale.localized("workout.minutes \((p.durationSec ?? 0) / 60)")
            return p.distanceM.map { "\(min) · \(($0 / 1000).formatted(n)) km" } ?? min
        }
    }
}

/// Numeric input that keeps the user's partial text ("62,") while typing and writes parsed values through.
private struct NumberField: View {
    @Binding var value: Double?
    let decimal: Bool
    let done: Bool
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text) { Text(verbatim: "–") }
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.custom("InterTight-Bold", size: 19, relativeTo: .body).monospacedDigit())
            .foregroundStyle(done || focused ? Color.primary : Color.secondary)
            .focused($focused)
            .frame(height: 40)
            .background(focused ? Color.white.opacity(0.06) : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? Color.orbit.primary : Color.clear, lineWidth: 1.5)
            }
            .onAppear { text = format(value) }
            .onChange(of: text) { _, new in
                if focused { value = parse(new) }
            }
            .onChange(of: value) { _, new in
                if !focused { text = format(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    text = format(value)
                    WorkoutRepository.save(context)  // keep typed values if the app is closed mid-session
                }
            }
    }

    private func format(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    private func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." })
    }
}

// MARK: - Rest timer pill

private struct RestTimerPill: View {
    let exerciseName: String
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        if let end = coordinator.restEnd {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let remaining = max(0, end.timeIntervalSince(context.date))
                    MiniRing(progress: coordinator.restDuration > 0 ? remaining / coordinator.restDuration : 0, lineWidth: 5)
                        .frame(width: 48, height: 48)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("session.rest")
                        .font(.caption)
                        .foregroundStyle(Color.orbit.textSecondary)
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                        .font(.custom("InterTight-ExtraBold", size: 28, relativeTo: .title).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                pillButton("−15") { coordinator.adjustRest(by: -15, exerciseName: exerciseName) }
                pillButton("+15") { coordinator.adjustRest(by: 15, exerciseName: exerciseName) }
                Button("session.skip") { coordinator.skipRest() }
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Color.orbit.onPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Color.orbit.primary, in: .capsule)
            }
            .padding(10)
            .background(Color.orbit.card, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.primary)
                .frame(width: 52, height: 48)
                .background(Color.white.opacity(0.08), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mini-bar

/// Shown above the tab bar while a session runs minimised.
struct SessionMiniBar: View {
    @Environment(SessionCoordinator.self) private var coordinator

    var body: some View {
        if let session = coordinator.session, !coordinator.isPresented {
            Button { coordinator.isPresented = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Color.orbit.onPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.orbit.primary, in: .circle)
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if let name = session.template?.name { Text(name) } else { Text("workout.emptySession") }
                        }
                        .font(.subheadline.weight(.semibold))
                        if let end = coordinator.restEnd {
                            Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.orbit.textSecondary)
                        } else {
                            Text(session.startedAt, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.orbit.textSecondary)
                        }
                    }
                    Spacer()
                    Text("session.resume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orbit.accent)
                }
                .padding(10)
                .background(.regularMaterial, in: .capsule)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
        }
    }
}

extension View {
    /// Adds the running-session mini-bar to a tab's content.
    func sessionMiniBar() -> some View {
        safeAreaInset(edge: .bottom) { SessionMiniBar() }
    }
}
