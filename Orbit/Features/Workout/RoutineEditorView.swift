import SwiftData
import SwiftUI
import OrbitData
import OrbitEngine
import OrbitUI

/// Edit a routine in place (WRK-03): name, days, exercises with sets / rep range / rest.
struct RoutineEditorView: View {
    @Bindable var routine: RoutineTemplate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var confirmDelete = false
    /// Bumped after relationship edits: SwiftData doesn't reliably redraw on `items` changes.
    @State private var version = 0

    var body: some View {
        let _ = version
        let items = routine.orderedItems
        Form {
            Section {
                TextField("routine.form.name", text: $routine.name)
                    .font(.body.weight(.medium))
            }

            Section("routine.form.days") {
                WeekdayPicker(selection: Binding(get: { Set(routine.weekdays) }, set: { routine.weekdays = $0.sorted() }))
            }

            Section {
                ForEach(items) { item in
                    NavigationLink {
                        TemplateItemEditor(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            ExerciseName(exercise: item.exercise).font(.body.weight(.medium))
                            TemplateItemSummary(item: item)
                                .font(.subheadline)
                                .foregroundStyle(Color.orbit.textSecondary)
                        }
                    }
                }
                .onDelete { offsets in
                    WorkoutRepository.removeItems(at: offsets, from: routine, in: context)
                    version += 1
                }
                .onMove { source, destination in
                    WorkoutRepository.moveItems(in: routine, fromOffsets: source, toOffset: destination, in: context)
                    version += 1
                }
                Button("routine.form.addExercise", systemImage: "plus") { picking = true }
            } header: {
                Text("routine.form.exercises")
            } footer: {
                if !items.isEmpty { Text("routine.form.reorderHint") }
            }

            Section {
                Button("routine.form.delete", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(Text(routine.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .confirmationAction) {
                Button("common.done") {
                    WorkoutRepository.save(context)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $picking) {
            ExercisePickerView { exercise in
                WorkoutRepository.addItem(exercise, to: routine, in: context)
                version += 1
            }
        }
        .confirmationDialog("routine.form.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("routine.form.delete", role: .destructive) {
                WorkoutRepository.deleteRoutine(routine, in: context)
                dismiss()
            }
        } message: {
            Text("routine.form.delete.message")
        }
        .onDisappear { WorkoutRepository.save(context) }
    }
}

/// Sets, rep range (or seconds) and rest for one exercise in a routine.
private struct TemplateItemEditor: View {
    @Bindable var item: TemplateItem
    @Environment(\.modelContext) private var context

    var body: some View {
        let kind = item.exercise?.type ?? .weightReps
        Form {
            if kind == .cardio {
                Section {
                    Text("routine.item.cardioNote").foregroundStyle(Color.orbit.textSecondary)
                }
            } else {
                Section {
                    Stepper(value: $item.targetSets, in: 1...10) { Text("routine.item.sets \(item.targetSets)") }
                    if kind == .duration {
                        Stepper(value: $item.repMin, in: 5...item.repMax, step: 5) { Text("routine.item.minSeconds \(item.repMin)") }
                        Stepper(value: $item.repMax, in: item.repMin...600, step: 5) { Text("routine.item.maxSeconds \(item.repMax)") }
                    } else {
                        Stepper(value: $item.repMin, in: 1...item.repMax) { Text("routine.item.minReps \(item.repMin)") }
                        Stepper(value: $item.repMax, in: item.repMin...50) { Text("routine.item.maxReps \(item.repMax)") }
                    }
                } footer: {
                    if kind == .weightReps { Text("routine.item.rangeHint") }
                }
                Section {
                    Stepper(value: $item.restSec, in: 0...300, step: 15) { Text("routine.item.rest \(item.restSec)") }
                }
            }
        }
        .navigationTitle(item.exercise.map { Text(exerciseKey: $0) } ?? Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { WorkoutRepository.save(context) }
    }
}

/// "3 set · 8–12 rep · istirahat 90 dtk"
struct TemplateItemSummary: View {
    let item: TemplateItem

    var body: some View {
        switch item.exercise?.type ?? .weightReps {
        case .cardio: Text("routine.item.cardio")
        case .duration: Text("routine.item.summaryDuration \(item.targetSets) \(item.repMin) \(item.repMax) \(item.restSec)")
        default: Text("routine.item.summary \(item.targetSets) \(item.repMin) \(item.repMax) \(item.restSec)")
        }
    }
}

/// Built-in names are catalog keys (they follow the app language); custom names are shown as typed.
struct ExerciseName: View {
    let exercise: Exercise?

    var body: some View {
        if let exercise { Text(exerciseKey: exercise) } else { Text(verbatim: "—") }
    }
}

extension Text {
    init(exerciseKey exercise: Exercise) {
        if exercise.isCustom {
            self.init(verbatim: exercise.name)
        } else {
            self.init(LocalizedStringKey(exercise.name))
        }
    }
}

#Preview {
    let container = OrbitData.makePreviewContainer()
    let routine = try! container.mainContext.fetch(FetchDescriptor<RoutineTemplate>()).first!
    return NavigationStack { RoutineEditorView(routine: routine) }
        .modelContainer(container)
}
