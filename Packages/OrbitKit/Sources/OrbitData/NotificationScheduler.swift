import Foundation
import SwiftData
import UserNotifications
import OrbitEngine

/// One local notification to schedule.
public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case reminder(habitName: String)
        /// Evening nudge with the number of habits still open that day.
        case streakSaver(pending: Int)
    }

    /// Stable, so re-planning replaces instead of duplicating.
    public var id: String
    public var date: Date
    public var kind: Kind
}

/// Decides which notifications should exist (pure; `NotificationScheduler` applies the result).
/// iOS keeps at most 64 pending notifications, so only the nearest 64 over the next week are kept.
public enum NotificationPlanner {
    public static let limit = 64

    public static func plan(habits: [Habit], calculator: HabitCalculator, settings: SettingsSnapshot,
                            now: Date, days: Int = 7) -> [PlannedNotification] {
        let cal = calculator.calendar
        let active = habits.filter { !$0.isArchived }
        let inputs = active.map { (habit: $0, rule: $0.rule(calendar: cal), logs: $0.dayLogs) }
        let today = DayKey.day(now, calendar: cal)
        var result: [PlannedNotification] = []

        for offset in 0..<days {
            let day = DayKey.adding(offset, to: today, calendar: cal)
            guard let dayStart = DayKey.date(fromDay: day, calendar: cal) else { continue }
            func at(_ minutes: Int) -> Date {
                cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart) ?? dayStart
            }

            for input in inputs where !input.habit.reminderMinutes.isEmpty {
                let due: Bool
                if let perWeek = input.rule.timesPerWeek {
                    // Weekly habits: remind until this week's count is reached.
                    due = day >= input.rule.startDay
                        && calculator.doneInWeek(input.rule, logs: input.logs, containing: day) < perWeek
                } else {
                    due = calculator.isScheduled(input.rule, on: day)
                }
                guard due, !calculator.isDone(input.rule, input.logs[day]) else { continue }
                for minutes in input.habit.reminderMinutes {
                    let date = at(minutes)
                    guard date > now else { continue }
                    result.append(PlannedNotification(id: "reminder-\(input.habit.id)-\(day)-\(minutes)", date: date,
                                                      kind: .reminder(habitName: input.habit.name)))
                }
            }

            if settings.streakSaverEnabled {
                let date = at(settings.streakSaverMinutes)
                let pending = inputs.count { calculator.isScheduled($0.rule, on: day) && !calculator.isDone($0.rule, $0.logs[day]) }
                if date > now, pending > 0 {
                    result.append(PlannedNotification(id: "streak-\(day)", date: date, kind: .streakSaver(pending: pending)))
                }
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }
}

/// The only place that talks to UNUserNotificationCenter (CLAUDE.md rule 7). Call `reschedule()` after
/// data, language or notification settings change, and when the app becomes active.
public enum NotificationScheduler {
    /// Asks once; returns whether notifications are allowed.
    @discardableResult
    public static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await reschedule()
        return granted
    }

    public static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Fire-and-forget version for synchronous callers (every habit save).
    public static func requestReschedule() {
        guard OrbitData.isAppOrExtension else { return }
        Task { await reschedule() }
    }

    /// Replaces every pending Orbit notification with a fresh plan.
    public static func reschedule(now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else {
            center.removeAllPendingNotificationRequests()
            return
        }
        guard let container = try? OrbitData.makeContainer(),
              let habits = try? ModelContext(container).fetch(FetchDescriptor<Habit>()) else { return }
        let settings = SettingsSnapshot(from: .orbit)
        let plan = NotificationPlanner.plan(habits: habits, calculator: .fromSettings(), settings: settings, now: now)

        center.removeAllPendingNotificationRequests()
        for item in plan {
            let content = UNMutableNotificationContent()
            switch item.kind {
            case .reminder(let name):
                content.title = name
                content.body = L10n.string("notif.reminder.body", language: settings.language)
            case .streakSaver(let pending):
                content.title = L10n.string("notif.streakSaver.title", language: settings.language)
                content.body = L10n.string("notif.streakSaver.body \(pending)", language: settings.language)
            }
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
        }
    }
}
