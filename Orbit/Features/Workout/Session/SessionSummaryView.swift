import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// WRK-09: after "Selesai" — duration, volume, sets, and new personal records (WRK-10).
struct SessionSummaryView: View {
    let finished: SessionCoordinator.FinishedSession
    let onClose: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 24)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.orbit.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("session.done.title")
                    .font(Typography.largeTitle)
                    .tracking(-0.6)
                Group {
                    if let title = finished.title { Text(title) } else { Text("workout.emptySession") }
                }
                .font(.title3)
                .foregroundStyle(Color.orbit.textSecondary)
            }

            HStack(spacing: 12) {
                stat("session.stat.duration", locale.localized("workout.minutes \(max(1, finished.summary.durationSec / 60))"))
                stat("session.stat.volume", kg(finished.summary.volumeKg, digits: 0))
                stat("session.stat.sets", "\(finished.summary.completedSets)")
            }

            if !finished.records.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("session.records", systemImage: "trophy.fill")
                        .font(Typography.section)
                        .foregroundStyle(Color.orbit.primary)
                    ForEach(finished.records) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exerciseKey: record.exercise).font(.headline)
                            Text(verbatim: record.kinds.map { describe($0, record.best) }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Color.orbit.textSecondary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orbit.card, in: .rect(cornerRadius: 24, style: .continuous))
            }

            Spacer()
            Button(action: onClose) {
                Text("session.close").frame(maxWidth: .infinity)
            }
            .buttonStyle(.orbitPrimary)
        }
        .padding(20)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orbit.textSecondary)
            Text(verbatim: value)
                .font(Typography.stat)
                .foregroundStyle(Color.orbit.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orbit.card, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func kg(_ value: Double, digits: Int = 1) -> String {
        Measurement(value: value, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...digits))).locale(locale))
    }

    private func describe(_ kind: RecordKind, _ best: PersonalRecords) -> String {
        switch kind {
        case .heaviest: locale.localized("session.record.heaviest \(kg(best.heaviestKg))")
        case .e1RM: locale.localized("session.record.e1rm \(kg(best.bestE1RM))")
        case .setVolume: locale.localized("session.record.setVolume \(kg(best.bestSetVolume, digits: 0))")
        }
    }
}
