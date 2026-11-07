// Phase 0 spike screen — delete after the spike passes (strings intentionally not localized).
import ActivityKit
import HealthKit
import SwiftUI
import WidgetKit
import OrbitData

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var count = 0
    @State private var status = "–"
    private let health = HKHealthStore()

    var body: some View {
        VStack(spacing: 16) {
            Text("\(count)")
                .font(.custom("InterTight-Black", size: 96, relativeTo: .largeTitle))
                .contentTransition(.numericText(value: Double(count)))
            Text("Inter Tight ExtraBold")
                .font(.custom("InterTight-ExtraBold", size: 22, relativeTo: .title2))

            Button("Tambah catatan") {
                status = (try? OrbitData.addSpikeNote()) == nil ? "Gagal simpan" : "Tersimpan"
                WidgetCenter.shared.reloadTimelines(ofKind: SpikeKind.widget)
                refresh()
            }
            Button("Minta izin Health") { Task { await requestHealth() } }
            Button("Mulai Live Activity") { startActivity() }

            Text(status).font(.footnote).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderedProminent)
        .onAppear(perform: refresh)
        // The widget writes from another process, so re-read when coming back.
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        withAnimation { count = OrbitData.spikeNoteCount() }
    }

    private func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Health tidak tersedia"; return }
        do {
            try await health.requestAuthorization(toShare: [], read: [HKQuantityType(.stepCount)])
            status = "Prompt Health selesai"
        } catch {
            status = "Health error: \(error.localizedDescription)"
        }
    }

    private func startActivity() {
        let now = Date.now
        do {
            _ = try Activity.request(
                attributes: SpikeActivityAttributes(name: "Push Day"),
                content: .init(state: .init(startedAt: now, endsAt: now + 90), staleDate: nil)
            )
            status = "Live Activity jalan, kunci layar"
        } catch {
            status = "Live Activity error: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
