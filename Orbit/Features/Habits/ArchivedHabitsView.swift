import SwiftData
import SwiftUI
import OrbitData
import OrbitUI

/// Archived habits keep their history; restoring puts them back at the end of the list.
struct ArchivedHabitsView: View {
    @Query(filter: #Predicate<Habit> { $0.isArchived }, sort: \Habit.name) private var archived: [Habit]
    @Query(filter: #Predicate<Habit> { !$0.isArchived }) private var active: [Habit]

    var body: some View {
        List {
            ScreenHeader(Text("habits.archived"))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))

            if archived.isEmpty {
                ContentUnavailableView("habits.archived.empty", systemImage: "archivebox")
                    .listRowBackground(Color.clear)
            }
            ForEach(archived) { habit in
                HStack(spacing: 12) {
                    Image(systemName: habit.iconName)
                        .foregroundStyle(Color.orbit.iconTint)
                        .frame(width: 40, height: 40)
                        .background(Color.orbit.iconTile, in: .rect(cornerRadius: 11, style: .continuous))
                        .accessibilityHidden(true)
                    Text(habit.name)
                    Spacer()
                    Button("habits.action.restore") { restore(habit) }
                        .buttonStyle(.borderless)
                        .fontWeight(.semibold)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.orbit.bg)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func restore(_ habit: Habit) {
        habit.sortOrder = (active.map(\.sortOrder).max() ?? -1) + 1
        HabitRepository.setArchived(false, habit)
    }
}

#Preview {
    let container = OrbitData.makePreviewContainer()
    let habits = try! container.mainContext.fetch(FetchDescriptor<Habit>())
    habits.prefix(2).forEach { $0.isArchived = true }
    return NavigationStack { ArchivedHabitsView() }
        .modelContainer(container)
}
