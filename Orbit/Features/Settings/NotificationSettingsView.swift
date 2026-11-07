import SwiftUI
import UserNotifications
import OrbitData
import OrbitUI

/// Permission status + streak saver (HAB-06). Per-habit reminder times live in the habit form.
struct NotificationSettingsView: View {
    @AppStorage(SettingsKey.streakSaverEnabled, store: .orbit) private var saverOn = SettingsSnapshot.defaults.streakSaverEnabled
    @AppStorage(SettingsKey.streakSaverMinutes, store: .orbit) private var saverMinutes = SettingsSnapshot.defaults.streakSaverMinutes
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            ScreenHeader(Text("settings.notifications"))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 0))

            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("settings.notifications.on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.orbit.accent)
                case .denied:
                    Text("settings.notifications.denied")
                    Button("settings.notifications.openSettings") {
                        if let url = URL(string: "app-settings:") { openURL(url) }
                    }
                default:
                    Button("settings.notifications.allow") {
                        Task {
                            await NotificationScheduler.requestAuthorization()
                            await refresh()
                        }
                    }
                }
            } footer: {
                Text("settings.notifications.footer")
            }

            Section {
                Toggle("settings.streakSaver.toggle", isOn: $saverOn)
                if saverOn {
                    DatePicker("settings.streakSaver.time", selection: time, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("settings.streakSaver")
            } footer: {
                Text("settings.streakSaver.footer")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        // Coming back from iPhone Settings may have changed the permission.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
        .onChange(of: saverOn) { NotificationScheduler.requestReschedule() }
        .onChange(of: saverMinutes) { NotificationScheduler.requestReschedule() }
    }

    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: saverMinutes / 60, minute: saverMinutes % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            saverMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
        }
    }

    private func refresh() async {
        status = await NotificationScheduler.authorizationStatus()
    }
}

#Preview {
    NavigationStack { NotificationSettingsView() }
}
