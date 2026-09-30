// TrainingReminderPlanner.swift
//
// Which training reminders should be pending right now
// (add-training-checkins design D8; the architecture note's section 6.3):
//
//   - morning: "How do you feel today?" at 04:05 on each of today and
//     tomorrow that has a session with options (a G/A/R day) and no
//     check-in yet -- the phone's own or the vault's light;
//   - evening: "Evening habits" at 20:10 on each of those days that
//     expects habits not all ticked (the phone's tick, else the vault's
//     count, decision A42).
//
// Pure, like FoodLogCore's NotificationPlanning: the app's
// NotificationScheduler re-plans on every foreground, check-in and tick and
// diffs against what is pending (identifier prefix `training.`), because a
// local notification can't ask at fire time whether it is still needed. A
// reminder whose time has passed is left out. Nothing is planned without a
// plan, or when the capabilities don't allow recording (no device id).
//
// fix-review-findings-2026-09 finding 11: `days` widens the window beyond
// today and tomorrow (the app passes a week, planned from the cached
// projection), so reminders keep firing while the app stays closed; the
// next replan still removes any a check-in or tick makes unneeded. Days the
// plan doesn't cover plan nothing.
//
// Times are defaults (tasks 0.1). Depended on by: the app's
// NotificationScheduler. Tests: TrainingReminderPlannerTests.

import Foundation

public struct TrainingReminder: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable {
        case morningCheckIn = "checkin"
        case eveningHabits = "habits"
    }

    public let kind: Kind
    public let date: LocalDate
    public let hour: Int
    public let minute: Int
    public let title: String
    public let body: String

    /// Stable per kind and day: `checkin.2030-10-23`.
    public var id: String { "\(kind.rawValue).\(date)" }
}

public enum TrainingReminderPlanner {
    public static let morningTime = (hour: 4, minute: 5)
    public static let eveningTime = (hour: 20, minute: 10)

    /// Reminders for `today` and the following days (`days` in all,
    /// default today and tomorrow) that are still ahead of `now` (read in
    /// `timeZone`, the device's: reminders fire on the phone's clock).
    public static func plan(
        snapshot: TrainingSnapshot?,
        today: LocalDate,
        now: Date,
        timeZone: TimeZone,
        language: TrainingLanguage,
        days: Int = 2
    ) -> [TrainingReminder] {
        guard let snapshot, let plan = snapshot.plan, days > 0 else { return [] }
        let text = TrainingText(language)
        var result: [TrainingReminder] = []
        for date in (0..<days).map({ today.adding(days: $0) }) {
            guard let day = plan.day(date) else { continue }

            if snapshot.capabilities.canCheckIn,
               day.sessions.contains(where: { !$0.options.isEmpty }),
               day.light?.known == nil {
                let reminder = TrainingReminder(
                    kind: .morningCheckIn,
                    date: date,
                    hour: morningTime.hour,
                    minute: morningTime.minute,
                    title: text(.reminderCheckInTitle),
                    body: text(.reminderCheckInBody)
                )
                if isAhead(reminder, now: now, timeZone: timeZone) { result.append(reminder) }
            }

            if snapshot.capabilities.canTickHabits, !day.habitsExpected.isEmpty {
                let open = day.habitsExpected.contains { !snapshot.habitDone($0, on: date).done }
                if open {
                    let reminder = TrainingReminder(
                        kind: .eveningHabits,
                        date: date,
                        hour: eveningTime.hour,
                        minute: eveningTime.minute,
                        title: text(.reminderHabitsTitle),
                        body: text(.reminderHabitsBody)
                    )
                    if isAhead(reminder, now: now, timeZone: timeZone) { result.append(reminder) }
                }
            }
        }
        return result
    }

    /// The moment `reminder` fires, on the phone's clock.
    public static func fireDate(_ reminder: TrainingReminder, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = reminder.date.year
        components.month = reminder.date.month
        components.day = reminder.date.day
        components.hour = reminder.hour
        components.minute = reminder.minute
        return calendar.date(from: components)
    }

    private static func isAhead(_ reminder: TrainingReminder, now: Date, timeZone: TimeZone) -> Bool {
        guard let fire = fireDate(reminder, timeZone: timeZone) else { return false }
        return fire > now
    }
}
