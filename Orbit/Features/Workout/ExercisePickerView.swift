import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Exercise library grouped by muscle, searchable in the app language, plus custom exercises (WRK-01).
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }) private var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.language, store: .orbit) private var language = SettingsSnapshot.defaults.language
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        // Display names once per render, so search and sort match what's on screen.
        let named = exercises.map { (exercise: $0, name: $0.displayName(language: language)) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    let items = named.filter { $0.exercise.muscleGroup == group }
                    if !items.isEmpty {
                        Section(group.titleKey) {
                            ForEach(items, id: \.exercise.id) { entry in
                                Button {
                                    onPick(entry.exercise)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(verbatim: entry.name).foregroundStyle(Color.primary)
                                        Spacer()
                                        Text(entry.exercise.isCustom ? "exercise.custom" : entry.exercise.equipment.titleKey)
                                            .font(.subheadline)
                                            .foregroundStyle(Color.orbit.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                if named.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: Text("exercise.picker.search"))
            .navigationTitle(Text("exercise.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("exercise.new", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseForm { exercise in
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

/// A user-made exercise (name, type, muscle group, rest).
private struct CustomExerciseForm: View {
    let onCreate: (Exercise) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: ExerciseKind = .weightReps
    @State private var muscle: MuscleGroup = .chest
    @State private var isLowerBody = false
    @State private var rest = 90

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("exercise.form.name", text: $name)
                }
                Section {
                    Picker("exercise.form.type", selection: $type) {
                        ForEach(ExerciseKind.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                    Picker("exercise.form.muscle", selection: $muscle) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }
                    Toggle("exercise.form.lowerBody", isOn: $isLowerBody)
                } footer: {
                    Text("exercise.form.lowerBody.footer")
                }
                if type != .cardio {
                    Section {
                        Stepper(value: $rest, in: 0...300, step: 15) { Text("routine.item.rest \(rest)") }
                    }
                }
            }
            .onChange(of: muscle) { _, new in isLowerBody = new == .legs }
            .navigationTitle(Text("exercise.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        let exercise = WorkoutRepository.createExercise(
                            name: name.trimmingCharacters(in: .whitespaces), type: type, muscleGroup: muscle,
                            isLowerBody: isLowerBody, restSec: type == .cardio ? 0 : rest, in: context)
                        dismiss()
                        onCreate(exercise)
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension MuscleGroup {
    var titleKey: LocalizedStringKey {
        switch self {
        case .chest: "muscle.chest"
        case .back: "muscle.back"
        case .legs: "muscle.legs"
        case .shoulders: "muscle.shoulders"
        case .arms: "muscle.arms"
        case .core: "muscle.core"
        case .cardio: "muscle.cardio"
        }
    }
}

extension Equipment {
    var titleKey: LocalizedStringKey {
        switch self {
        case .barbell: "equipment.barbell"
        case .dumbbell: "equipment.dumbbell"
        case .machine: "equipment.machine"
        case .cable: "equipment.cable"
        case .bodyweight: "equipment.bodyweight"
        case .other: "equipment.other"
        }
    }
}

extension ExerciseKind {
    var titleKey: LocalizedStringKey {
        switch self {
        case .weightReps: "exerciseKind.weightReps"
        case .bodyweight: "exerciseKind.bodyweight"
        case .duration: "exerciseKind.duration"
        case .cardio: "exerciseKind.cardio"
        }
    }
}

#Preview {
    ExercisePickerView { _ in }
        .modelContainer(OrbitData.makePreviewContainer())
}
