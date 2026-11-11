import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// TOD-04: Kartu latihan hari ini — rutinitas sesuai jadwal + tombol Mulai.
struct TodayWorkoutCard: View {
    let routine: RoutineTemplate?
    let sessions: [WorkoutSession]
    let onStart: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("tab.today.workout").font(Typography.section)
                Spacer()
            }

            if let routine {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Color.orbit.iconTint)
                        .frame(width: 40, height: 40)
                        .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: routine.name).font(.body.weight(.medium).weight(.semibold))
                        Text("\(routine.orderedItems.count) latihan").font(.caption)
                            .foregroundStyle(Color.orbit.textSecondary)

                        // First 3 exercises with targets.
                        let top3 = Array(routine.orderedItems.prefix(3))
                        ForEach(0..<top3.count, id: \.self) { index in
                            let item = top3[index]
                            HStack(spacing: 4) {
                                Image(systemName: "dumbbell")
                                    .font(.caption2)
                                    .foregroundStyle(Color.orbit.textSecondary)
                                Text(verbatim: item.exercise?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Color.orbit.textSecondary)
                                Text("\(item.repMin)–\(item.repMax)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.orbit.accent)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                }

                Button(action: onStart) {
                    Text("tab.today.start")
                        .font(.headline)
                        .foregroundStyle(Color.orbit.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.orbit.primary, in: .capsule)
                }
                .buttonStyle(.plain)
            } else {
                ContentUnavailableView {
                    Label("tab.today.workout.none", systemImage: "dumbbell")
                } description: {
                    Text("tab.today.workout.none.description")
                }
            }
        }
        .padding(16)
        .background(Color.orbit.card, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

#Preview("Workout card") {
    TodayWorkoutCard(
        routine: nil,
        sessions: [],
        onStart: {}
    )
}
