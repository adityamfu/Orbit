import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// PRD §4.10 Onboarding (P0): bahasa → dompet pertama → kebiasaan awal → program latihan → selesai.
/// Ditampilkan sekali saat pertama kali buka app.
struct OnboardingView: View {
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @AppStorage(SettingsKey.firstLaunch, store: .orbit) private var firstLaunch = true
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var page = 0
    @State private var walletName = ""
    @State private var walletType: WalletType = .bank
    @State private var walletBalance = ""
    @State private var selectedHabits: Set<UUID> = []
    @State private var selectedProgram: ProgramPreset? = nil

    /// Starter habits offered at onboarding (id, plain name, icon, schedule).
    private let starterHabits: [(id: UUID, name: String, icon: String, schedule: HabitRule.Schedule)] = [
        (UUID(), "Minum air", "drop", .daily),
        (UUID(), "Stretching pagi", "waveform.path.ecg", .daily),
        (UUID(), "Baca buku", "book", .weekdays([2, 3, 4, 5, 6])),
        (UUID(), "Tidur sebelum 23.00", "moon", .daily),
    ]

    var body: some View {
        TabView(selection: $page) {
            languagePage.tag(0)
            walletPage.tag(1)
            habitsPage.tag(2)
            routinePage.tag(3)
            donePage.tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    // MARK: - Pages

    private var languagePage: some View {
        VStack(spacing: 24) {
            ScreenHeader(Text("onboarding.language"))
            Picker("onboarding.language", selection: $language) {
                Text("Indonesia").tag(AppLanguage.id)
                Text("English").tag(AppLanguage.en)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)
            Text("onboarding.language.desc")
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Spacer()
        }
        .padding(.top, 40)
    }

    private var walletPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(Text("onboarding.wallet"))
            TextField("onboarding.wallet.name", text: $walletName)
                .textFieldStyle(.roundedBorder)
            Picker("onboarding.wallet.type", selection: $walletType) {
                ForEach(WalletType.allCases, id: \.self) { Text($0.titleKey).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("onboarding.wallet.balance", text: $walletBalance)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            Text("onboarding.wallet.desc")
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
            Spacer()
        }
        .padding(24)
    }

    private var habitsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(Text("onboarding.habits"))
            Text("onboarding.habits.desc")
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
            List {
                ForEach(starterHabits, id: \.id) { item in
                    Button {
                        if selectedHabits.contains(item.id) { selectedHabits.remove(item.id) }
                        else { selectedHabits.insert(item.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .foregroundStyle(selectedHabits.contains(item.id) ? Color.orbit.accent : Color.orbit.iconTint)
                                .frame(width: 36, height: 36)
                                .background(selectedHabits.contains(item.id) ? Color.orbit.accentSoft : Color.orbit.iconTile,
                                            in: .rect(cornerRadius: 10, style: .continuous))
                            Text(verbatim: item.name).font(.body)
                            Spacer()
                            if selectedHabits.contains(item.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.orbit.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 300)
            Spacer()
        }
        .padding(24)
    }

    private var routinePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(Text("onboarding.routine"))
            Text("onboarding.routine.desc")
                .font(.subheadline)
                .foregroundStyle(Color.orbit.textSecondary)
            ForEach(ProgramPreset.allCases, id: \.self) { program in
                Button {
                    selectedProgram = program
                } label: {
                    HStack {
                        Text(LocalizedStringKey("routine.\(program.rawValue)"))
                        Spacer()
                        if selectedProgram == program { Image(systemName: "checkmark") }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(selectedProgram == program ? Color.orbit.accentSoft : Color.orbit.card,
                            in: .rect(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selectedProgram == program ? Color.orbit.accent : .clear, lineWidth: 2)
                }
            }
            Button {
                selectedProgram = nil
            } label: {
                HStack {
                    Text("onboarding.routine.skip")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.orbit.iconTile, in: .rect(cornerRadius: 16, style: .continuous))
            Spacer()
        }
        .padding(24)
    }

    private var donePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.orbit.accent)
            Text("onboarding.done.title").font(Typography.largeTitle).tracking(-0.6)
            Text("onboarding.done.desc").font(.subheadline).foregroundStyle(Color.orbit.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
            Button("common.done", action: finish)
                .buttonStyle(.orbitPrimary)
                .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Finish

    private func finish() {
        // Language already written via @AppStorage.
        // Wallet.
        if !walletName.trimmingCharacters(in: .whitespaces).isEmpty {
            let balance = Int64(walletBalance.filter(\.isNumber)) ?? 0
            let wallet = Wallet(name: walletName.trimmingCharacters(in: .whitespaces),
                                type: walletType, initialBalance: balance, sortOrder: 0)
            context.insert(wallet)
            _ = try? CategoryLibrary.seedIfNeeded(context) // built-in categories
            // Budgets for starter categories this period.
            let period = Period.key(.now, cycleDay: SettingsSnapshot(from: .orbit).cycleStartDay)
            for key in ["category.food", "category.transport"] {
                if let cat = (try? context.fetch(FetchDescriptor<MoneyCategory>(
                    predicate: #Predicate { $0.name == key })))?.first {
                    let b = Budget(category: cat, periodKey: period, limit: 0)
                    context.insert(b); b.category = cat
                }
            }
        }
        // Starter habits.
        var order = 0
        for item in starterHabits where selectedHabits.contains(item.id) {
            let h = Habit(name: item.name, iconName: item.icon, type: .check, targetCount: 1,
                          schedule: item.schedule, startDate: .now, sortOrder: order)
            context.insert(h)
            order += 1
        }
        // Routine.
        if let program = selectedProgram {
            _ = try? program.install(in: context, language: language)
        }
        try? context.save()
        firstLaunch = false
        dismiss()
    }
}

#Preview {
    OnboardingView()
        .modelContainer(try! OrbitData.makeContainer(inMemory: true))
}
