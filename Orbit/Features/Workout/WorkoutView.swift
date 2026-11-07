import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Workout tab (DESIGN.md §5.5, canvas p.6). The weekly KPI card arrives with the KPI engine in Phase 5.
struct WorkoutView: View {
    @Query(sort: \RoutineTemplate.sortOrder) private var routines: [RoutineTemplate]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @AppStorage(SettingsKey.weightIncrement, store: .orbit) private var increment = SettingsSnapshot.defaults.weightIncrement

    @State private var editing: RoutineTemplate?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(Text("tab.workout")) { addMenu }

                    if routines.isEmpty {
                        emptyState
                    } else {
                        todayCard
                        sectionTitle("workout.routines")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(routines) { routine in
                                    Button { editing = routine } label: { RoutineCard(routine: routine) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }

                    if !sessions.isEmpty {
                        sectionTitle("workout.history")
                        VStack(spacing: 0) {
                            ForEach(sessions.prefix(10)) { session in
                                HistoryRow(session: session, isRecord: WorkoutHistory.hasRecord(session, among: sessions))
                                if session.id != sessions.prefix(10).last?.id { Divider().padding(.leading, 64) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Color.orbit.bg)
            .navigationTitle(Text("tab.workout"))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { routine in
                NavigationStack { RoutineEditorView(routine: routine) }
            }
        }
    }

    // MARK: Parts

    private var addMenu: some View {
        Menu {
            Button("workout.newRoutine", systemImage: "plus") { newRoutine() }
            Menu("workout.addProgram") {
                ForEach(ProgramPreset.allCases, id: \.self) { preset in
                    Button(preset.titleKey) { install(preset) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.orbit.onPrimary)
                .frame(width: 44, height: 44)
                .background(Color.orbit.primary, in: .circle)
        }
        .accessibilityLabel(Text("workout.add"))
    }

    @ViewBuilder
    private var todayCard: some View {
        let routine = WorkoutHistory.routine(for: .now, in: routines)
        let raised = routine?.orderedItems.count {
            if case .increase = WorkoutHistory.suggestion(for: $0, sessions: sessions, increment: increment)?.reason { true } else { false }
        } ?? 0

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("workout.today \(Date.now.formatted(.dateTime.weekday(.wide).locale(locale)))")
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
                Spacer()
                if raised > 0 {
                    Text("workout.targetsUp \(raised)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.orbit.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orbit.accentSoft, in: .capsule)
                }
            }
            if let routine {
                Text(routine.name)
                    .font(.custom("InterTight-ExtraBold", size: 30, relativeTo: .title))
                    .tracking(-0.5)
            } else {
                Text("workout.restDay")
                    .font(.custom("InterTight-ExtraBold", size: 30, relativeTo: .title))
                Text("workout.restDay.description")
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            // Starting a session arrives in step 3c.
            HStack(spacing: 10) {
                if let routine {
                    Button { } label: {
                        Text("workout.start \(routine.name)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.orbitPrimary)
                }
                Button("workout.emptySession") { }
                    .buttonStyle(.orbitSecondary)
                    .frame(maxWidth: routine == nil ? .infinity : nil)
            }
            .disabled(true)
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("workout.empty.title", systemImage: "dumbbell")
            } description: {
                Text("workout.empty.description")
            }
            ForEach(ProgramPreset.allCases, id: \.self) { preset in
                Button { install(preset) } label: {
                    Text(preset.titleKey).frame(maxWidth: .infinity)
                }
                .buttonStyle(preset == .pushPullLegs ? AnyButtonStyle(.orbitPrimary) : AnyButtonStyle(.orbitSecondary))
            }
            Button("workout.newRoutine") { newRoutine() }
                .padding(.top, 4)
        }
    }

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Typography.section)
            .padding(.top, 12)
            .padding(.horizontal, 4)
    }

    private func newRoutine() {
        editing = WorkoutRepository.createRoutine(name: L10n.string("workout.newRoutine.defaultName", language: language),
                                                  sortOrder: (routines.map(\.sortOrder).max() ?? -1) + 1, in: context)
    }

    private func install(_ preset: ProgramPreset) {
        _ = try? preset.install(in: context, language: language, startOrder: (routines.map(\.sortOrder).max() ?? -1) + 1)
    }
}

extension ProgramPreset {
    var titleKey: LocalizedStringKey {
        switch self {
        case .pushPullLegs: "program.ppl"
        case .upperLower: "program.upperLower"
        case .fullBody: "program.fullBody"
        }
    }
}

/// Type-erased style so one ForEach can mix primary and secondary buttons.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init(_ style: some ButtonStyle) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

private struct RoutineCard: View {
    let routine: RoutineTemplate
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routine.name)
                .font(.custom("InterTight-Bold", size: 20, relativeTo: .title3))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Text(routine.weekdays.isEmpty ? locale.localized("workout.noDays") : WeekdayPicker.summary(routine.weekdays, locale: locale))
                .lineLimit(1)
            Text("workout.exerciseCount \(routine.items.count)")
        }
        .font(.subheadline)
        .foregroundStyle(Color.orbit.textSecondary)
        .frame(width: 130, alignment: .leading)
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

private struct HistoryRow: View {
    let session: WorkoutSession
    let isRecord: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .foregroundStyle(Color.orbit.iconTint)
                .frame(width: 40, height: 40)
                .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let name = session.template?.name {
                    Text(name).font(.body.weight(.medium))
                } else {
                    Text("workout.emptySession").font(.body.weight(.medium))
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.orbit.textSecondary)
            }
            Spacer()
            if isRecord {
                Text("workout.pr")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orbit.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orbit.accent, in: .capsule)
            }
        }
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        let summary = SessionSummary(start: session.startedAt, end: session.endedAt ?? session.startedAt, sets: session.sets.map(\.record))
        let date = session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
        let minutes = locale.localized("workout.minutes \(summary.durationSec / 60)")
        let volume = Measurement(value: summary.volumeKg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
        return summary.volumeKg > 0 ? "\(date) · \(minutes) · \(volume)" : "\(date) · \(minutes)"
    }
}

#Preview("Workout") {
    WorkoutView()
        .modelContainer(OrbitData.makePreviewContainer())
}

#Preview("Empty") {
    WorkoutView()
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
}
