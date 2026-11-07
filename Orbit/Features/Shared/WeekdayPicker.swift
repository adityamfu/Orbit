import SwiftUI
import OrbitUI

/// Seven round toggles, Monday first (habit schedule, routine days).
struct WeekdayPicker: View {
    /// `Calendar` weekdays: 1 = Sunday … 7 = Saturday.
    @Binding var selection: Set<Int>
    @Environment(\.locale) private var locale

    var body: some View {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return HStack {
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(on ? Color.orbit.onAccent : Color.primary)
                        .background(on ? Color.orbit.accent : Color.orbit.iconTile, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(cal.standaloneWeekdaySymbols[day - 1]))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// "Sen · Sab" style list, Monday first.
    static func summary(_ days: [Int], locale: Locale) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = locale
        let symbols = cal.shortStandaloneWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { symbols[$0 - 1] }.joined(separator: " · ")
    }
}

#Preview {
    @Previewable @State var days: Set<Int> = [2, 4, 6]
    WeekdayPicker(selection: $days).padding()
}
