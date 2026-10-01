// TrainingReminderPlanner.swift
//
// Which training reminders should be pending right now
// (add-training-checkins design D8; the architecture note's section 6.3):
//
//   - morning: "How do you feel today?" on EVERY day of the window that
//     has no check-in yet -- the phone's own or the vault's light
//     (add-daily-checkin-and-pain-mode: it used to be planned only on a
//     day with a G/A/R session, so an unwritten week or a rest day never
//     asked). Its body is short ("Green, amber or red?"); in pain mode it
//     asks for the pain score too;
//   - evening: "Evening habits" on each of those days that expects habits
//     not all ticked (the phone's tick, else the vault's count, decision
//     A42). A day skeleton carries the expected habits of a day outside
//     the written weeks, so this works there too.
//
// Pure, like FoodLogCore's NotificationPlanning: the app's
// NotificationScheduler re-plans on every foreground, check-in and tick and
// diffs against what is pending (identifier prefix `training.`), because a
// local notification can't ask at fire time whether it is still needed. A
// reminder whose time has passed is left out. Nothing is planned without a
// loaded projection, or when the capabilities don't allow recording (no
// device id). A plan is NOT needed: the check-in works without one.
//
// fix-review-findings-2026-09 finding 11: `days` widens the window beyond
// today and tomorrow (the app passes a week, planned from the cached
// projection), so reminders keep firing while the app stays closed; the
// next replan still removes any a check-in or tick makes unneeded.
//
// add-daily-checkin-and-pain-mode: the two times are the owner's
// (`TrainingReminderTimes`, set in the notification settings; 04:05 and
// 20:10 by default). Depended on by: the app's TrainingModel and
// NotificationScheduler. Tests: CheckInBuilderTests, DailyCheckInTests.

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

/// When the two training reminders fire, on the phone's clock. Values
/// outside a day are clamped, so a broken stored value can't lose the
/// reminder.
public struct TrainingReminderTimes: Equatable, Sendable {
    public var morningHour: Int
    public var morningMinute: Int
    public var eveningHour: Int
    public var eveningMinute: Int

    /// 04:05 check-in, 20:10 habits (add-training-checkins tasks 0.1).
    public static let standard = TrainingReminderTimes(
        morningHour: TrainingReminderPlanner.morningTime.hour,
        morningMinute: TrainingReminderPlanner.morningTime.minute,
        eveningHour: TrainingReminderPlanner.eveningTime.hour,
        eveningMinute: TrainingReminderPlanner.eveningTime.minute
    )

    public init(morningHour: Int, morningMinute: Int, eveningHour: Int, eveningMinute: Int) {
        self.morningHour = min(max(morningHour, 0), 23)
        self.morningMinute = min(max(morningMinute, 0), 59)
        self.eveningHour = min(max(eveningHour, 0), 23)
        self.eveningMinute = min(max(eveningMinute, 0), 59)
    }
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
        days: Int = 2,
        times: TrainingReminderTimes = .standard
    ) -> [TrainingReminder] {
        guard let snapshot, days > 0 else { return [] }
        let text = TrainingText(language)
        let checkInBody = snapshot.painMode.isActive ? text(.reminderCheckInBodyPain) : text(.reminderCheckInBody)
        var result: [TrainingReminder] = []
        for offset in 0..<days {
            let date = today.adding(days: offset)
            let day = snapshot.day(date)

            if snapshot.capabilities.canCheckIn {
                // The day's light (the phone's check-in is already on it),
                // or the phone's own on a date the file doesn't have.
                let hasLight = day?.light?.known != nil || snapshot.checkIns.light(on: date) != nil
                if !hasLight {
                    let reminder = TrainingReminder(
                        kind: .morningCheckIn,
                        date: date,
                        hour: times.morningHour,
                        minute: times.morningMinute,
                        title: text(.reminderCheckInTitle),
                        body: checkInBody
                    )
                    if isAhead(reminder, now: now, timeZone: timeZone) { result.append(reminder) }
                }
            }

            if snapshot.capabilities.canTickHabits, let day, !day.habitsExpected.isEmpty {
                let open = day.habitsExpected.contains { !snapshot.habitDone($0, on: date).done }
                if open {
                    let reminder = TrainingReminder(
                        kind: .eveningHabits,
                        date: date,
                        hour: times.eveningHour,
                        minute: times.eveningMinute,
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
