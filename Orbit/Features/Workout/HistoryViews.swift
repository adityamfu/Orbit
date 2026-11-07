import Charts
import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Every finished session, newest first; swipe to delete a mistaken one.
struct HistoryListView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ScreenHeader(Text("workout.history"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
            ForEach(sessions) { session in
                NavigationLink { SessionDetailView(session: session) } label: {
                    HistoryRow(session: session, isRecord: WorkoutHistory.hasRecord(session, among: sessions))
                }
            }
            .onDelete { offsets in
                offsets.map { sessions[$0] }.forEach { SessionRepository.discard($0, in: context) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A finished session: totals and every exercise's sets. Tap an exercise for its progress chart.
struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var confirmDelete = false

    var body: some View {
        let summary = SessionSummary(start: session.startedAt, end: session.endedAt ?? session.startedAt,
                                     sets: session.sets.map(\.record))
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(locale)))
                        .font(.subheadline)
                        .foregroundStyle(Color.orbit.textSecondary)
                    Group {
                        if let name = session.template?.name { Text(name) } else { Text("workout.emptySession") }
                    }
                    .font(Typography.largeTitle)
                    .tracking(-0.6)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

                HStack {
                    metric("session.stat.duration", locale.localized("workout.minutes \(summary.durationSec / 60)"))
                    metric("session.stat.volume", Format.kg(summary.volumeKg, digits: 0, locale: locale))
                    metric("session.stat.sets", "\(summary.completedSets)")
                }
            }

            ForEach(SessionRepository.exercises(in: session)) { entry in
                Section {
                    ForEach(entry.sets) { set in
                        HStack {
                            Text(verbatim: set.isWarmup ? "W" : "\(entry.sets.filter { !$0.isWarmup }.firstIndex(of: set).map { $0 + 1 } ?? 0)")
                                .font(.custom("InterTight-Bold", size: 17, relativeTo: .body))
                                .foregroundStyle(set.isWarmup ? Color.orbit.accent : Color.orbit.textSecondary)
                                .frame(width: 28, alignment: .leading)
                            Text(verbatim: Format.set(set.record, kind: entry.exercise.type, locale: locale))
                                .font(Typography.metric)
                        }
                    }
                } header: {
                    NavigationLink { ExerciseProgressView(exercise: entry.exercise) } label: {
                        HStack {
                            Text(exerciseKey: entry.exercise)
                            Spacer()
                            Image(systemName: "chart.xyaxis.line")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .textCase(nil)
                }
            }

            Section {
                Button("session.delete", role: .destructive) { confirmDelete = true }
            }
        }
        // Feeds the back button of the progress chart; the big title above is the visible one.
        .navigationTitle(session.template.map { Text($0.name) } ?? Text("workout.emptySession"))
        .toolbar { ToolbarItem(placement: .principal) { Text(verbatim: "") } }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("session.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("session.delete", role: .destructive) {
                SessionRepository.discard(session, in: context)
                dismiss()
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.orbit.textSecondary)
            Text(verbatim: value).font(Typography.metric).foregroundStyle(Color.orbit.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// WRK-11: top set weight and estimated 1RM over time, plus personal bests.
struct ExerciseProgressView: View {
    let exercise: Exercise
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }) private var sessions: [WorkoutSession]
    @Environment(\.locale) private var locale
    @State private var metric = Metric.e1RM

    enum Metric: Hashable { case e1RM, topSet, volume }

    var body: some View {
        let points = WorkoutHistory.progress(exerciseID: exercise.id, in: sessions)
        let best = Strength.records(sessions.flatMap { $0.sets.filter { $0.exercise?.id == exercise.id }.map(\.record) })

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(Text(exerciseKey: exercise), caption: Text(exercise.muscleGroup.titleKey))

                if points.count < 2 {
                    ContentUnavailableView("exercise.progress.empty", systemImage: "chart.xyaxis.line",
                                           description: Text("exercise.progress.empty.description"))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("exercise.progress.metric", selection: $metric) {
                            Text("exercise.progress.e1rm").tag(Metric.e1RM)
                            Text("exercise.progress.topSet").tag(Metric.topSet)
                            Text("session.stat.volume").tag(Metric.volume)
                        }
                        .pickerStyle(.segmented)

                        Chart(points) { point in
                            let value = switch metric {
                            case .e1RM: point.e1RM
                            case .topSet: point.topWeightKg
                            case .volume: point.volumeKg
                            }
                            LineMark(x: .value("Date", point.date, unit: .day), y: .value("kg", value))
                                .foregroundStyle(Color.orbit.accent)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.date, unit: .day), y: .value("kg", value))
                                .foregroundStyle(Color.orbit.accent)
                        }
                        .chartYScale(domain: .automatic(includesZero: metric == .volume))
                        .frame(height: 220)
                        .accessibilityLabel(Text("exercise.progress.a11y"))
                    }
                    .padding(16)
                    .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                }

                if best != .none {
                    Text("exercise.progress.records").font(Typography.section).padding(.top, 8)
                    VStack(spacing: 0) {
                        record("exercise.progress.heaviest", Format.kg(best.heaviestKg, locale: locale))
                        Divider()
                        record("exercise.progress.e1rm", Format.kg(best.bestE1RM, locale: locale))
                        Divider()
                        record("exercise.progress.bestSet", Format.kg(best.bestSetVolume, digits: 0, locale: locale))
                    }
                    .padding(.horizontal, 16)
                    .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                }

                if !points.isEmpty {
                    Text("workout.history").font(Typography.section).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(points.reversed()) { point in
                            HStack {
                                Text(point.date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))
                                    .foregroundStyle(Color.orbit.textSecondary)
                                Spacer()
                                Text(verbatim: "\(Format.kg(point.topWeightKg, locale: locale)) × \(point.topReps)")
                                    .font(Typography.metric)
                            }
                            .padding(.vertical, 10)
                            if point.id != points.first?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(16)
        }
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func record(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).font(Typography.metric).foregroundStyle(Color.orbit.accent)
        }
        .padding(.vertical, 12)
    }
}

/// WRK-11: working-set volume per week for one muscle group (single accent series, per DESIGN §5.2).
struct WeeklyVolumeCard: View {
    let sessions: [WorkoutSession]
    let firstWeekday: Int
    @Environment(\.locale) private var locale
    @State private var muscle = MuscleGroup.chest

    var body: some View {
        let all = WorkoutHistory.weeklyVolume(sessions, weeks: 8, firstWeekday: firstWeekday)
        let trained = MuscleGroup.allCases.filter { m in all.contains { $0.muscle == m && $0.kg > 0 } }
        let data = all.filter { $0.muscle == muscle }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("workout.volume.title").font(.subheadline.weight(.semibold)).foregroundStyle(Color.orbit.textSecondary)
                Spacer()
                Picker("exercise.form.muscle", selection: $muscle) {
                    ForEach(trained.isEmpty ? MuscleGroup.allCases : trained, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Chart(data) { item in
                BarMark(x: .value("Week", item.weekStart, unit: .weekOfYear), y: .value("kg", item.kg))
                    .foregroundStyle(Color.orbit.accent)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(locale))
                }
            }
            .frame(height: 160)
            .accessibilityLabel(Text("workout.volume.a11y"))
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
        .onAppear { if let first = trained.first, !trained.contains(muscle) { muscle = first } }
    }
}

/// Shared number formatting for workout screens.
enum Format {
    static func kg(_ value: Double, digits: Int = 1, locale: Locale) -> String {
        Measurement(value: value, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...digits))).locale(locale))
    }

    static func set(_ r: SetRecord, kind: ExerciseKind, locale: Locale) -> String {
        switch kind {
        case .weightReps: "\(kg(r.weightKg ?? 0, digits: 2, locale: locale)) × \(r.reps ?? 0)"
        case .bodyweight: "× \(r.reps ?? 0)"
        case .duration: locale.localized("session.seconds \(r.durationSec ?? 0)")
        case .cardio: [
            r.durationSec.map { locale.localized("workout.minutes \($0 / 60)") },
            r.distanceM.map { "\(($0 / 1000).formatted(.number.precision(.fractionLength(0...2)).locale(locale))) km" },
        ].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
