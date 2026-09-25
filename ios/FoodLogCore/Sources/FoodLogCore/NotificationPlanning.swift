// NotificationPlanning.swift
//
// Pure decision logic for local reminder notifications (meal reminders,
// streak-at-risk, daily challenges) -- what SHOULD be scheduled right now,
// given preferences and today's state. No `UserNotifications` import here
// and no side effects: the actual `UNUserNotificationCenter` calls live in
// the app layer's `NotificationScheduler` (GarminFood/App/), which calls
// `plan(...)` fresh on every foreground/log/day-roll and diffs the result
// against what's currently pending -- see that file's header for why local
// notifications need this "replan and diff" approach rather than a single
// set-and-forget schedule: a `UNNotificationRequest` can't check "has this
// meal already been logged" at fire time on its own, so the app has to make
// that call ahead of time and keep it current.
//
// Deliberately takes plain booleans (`isStreakAtRiskToday`, not a
// `Gamification.StreakEngine.Status`) rather than importing `Gamification`
// -- that package already depends on FoodLogCore (Package.swift), so the
// reverse dependency would be circular. The app layer, which already has
// both, computes these booleans and passes them in.

import Foundation
import GarminKit

public struct ReminderSetting: Sendable, Equatable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int

    public init(isEnabled: Bool, hour: Int, minute: Int) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
    }
}

/// The fasting-reminder analogue of `ReminderSetting` -- an on/off switch
/// plus a minutes-before-the-boundary OFFSET rather than a clock time: the
/// user sets the boundary itself once, as their daily fasting window
/// (`FastingSchedule`, redesign-fasting-schedule), and this only says how
/// much warning they want before it. Used for both "fast ends soon" and
/// "fast starts soon".
public struct FastingReminderSetting: Sendable, Equatable {
    public var isEnabled: Bool
    public var minutesBefore: Int

    public init(isEnabled: Bool, minutesBefore: Int) {
        self.isEnabled = isEnabled
        self.minutesBefore = minutesBefore
    }
}

public struct NotificationPreferences: Sendable, Equatable {
    public var breakfastReminder: ReminderSetting
    public var lunchReminder: ReminderSetting
    public var dinnerReminder: ReminderSetting
    public var streakReminder: ReminderSetting
    public var dailyChallengeReminder: ReminderSetting
    /// "Fasting window ending soon" -- before the daily fast ends.
    public var fastingReminder: FastingReminderSetting
    /// "Fasting starts in 15 min" -- before the daily fast begins
    /// (redesign-fasting-schedule 2.5). Defaulted in `init` so call sites
    /// that predate it keep compiling.
    public var fastingStartReminder: FastingReminderSetting

    public init(
        breakfastReminder: ReminderSetting,
        lunchReminder: ReminderSetting,
        dinnerReminder: ReminderSetting,
        streakReminder: ReminderSetting,
        dailyChallengeReminder: ReminderSetting,
        fastingReminder: FastingReminderSetting,
        fastingStartReminder: FastingReminderSetting = FastingReminderSetting(isEnabled: false, minutesBefore: 15)
    ) {
        self.breakfastReminder = breakfastReminder
        self.lunchReminder = lunchReminder
        self.dinnerReminder = dinnerReminder
        self.streakReminder = streakReminder
        self.dailyChallengeReminder = dailyChallengeReminder
        self.fastingReminder = fastingReminder
        self.fastingStartReminder = fastingStartReminder
    }

    /// Off by default, times chosen as reasonable defaults matching
    /// Garmin's own typical meal windows -- turned on explicitly by the
    /// user in Settings, never silently opted in.
    public static let disabledDefault = NotificationPreferences(
        breakfastReminder: ReminderSetting(isEnabled: false, hour: 9, minute: 0),
        lunchReminder: ReminderSetting(isEnabled: false, hour: 13, minute: 30),
        dinnerReminder: ReminderSetting(isEnabled: false, hour: 19, minute: 30),
        streakReminder: ReminderSetting(isEnabled: false, hour: 21, minute: 0),
        dailyChallengeReminder: ReminderSetting(isEnabled: false, hour: 8, minute: 0),
        fastingReminder: FastingReminderSetting(isEnabled: false, minutesBefore: 15),
        fastingStartReminder: FastingReminderSetting(isEnabled: false, minutesBefore: 15)
    )
}

public enum NotificationPlanning {
    public struct PlannedNotification: Sendable, Equatable, Identifiable {
        /// Stable per-kind identifier (e.g. "mealReminder.breakfast") -- the
        /// scheduler appends today's date to make the actual
        /// `UNNotificationRequest` identifier, so each day's instance is
        /// independent and self-heals on the next replan.
        public let id: String
        public let title: String
        public let body: String
        public let hour: Int
        public let minute: Int

        public init(id: String, title: String, body: String, hour: Int, minute: Int) {
            self.id = id
            self.title = title
            self.body = body
            self.hour = hour
            self.minute = minute
        }
    }

    /// - Parameters:
    ///   - mealsLoggedToday: meal types that already have at least one entry
    ///     today (synced or queued) -- a reminder for an already-logged meal
    ///     is pointless and is left out of the plan.
    ///   - isStreakAtRiskToday: `Gamification.StreakEngine.Status.
    ///     isAtRiskToday`, computed by the caller.
    public static func plan(
        preferences: NotificationPreferences,
        mealsLoggedToday: Set<MealType>,
        isStreakAtRiskToday: Bool
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []

        if preferences.breakfastReminder.isEnabled, !mealsLoggedToday.contains(.breakfast) {
            result.append(mealReminder(.breakfast, preferences.breakfastReminder))
        }
        if preferences.lunchReminder.isEnabled, !mealsLoggedToday.contains(.lunch) {
            result.append(mealReminder(.lunch, preferences.lunchReminder))
        }
        if preferences.dinnerReminder.isEnabled, !mealsLoggedToday.contains(.dinner) {
            result.append(mealReminder(.dinner, preferences.dinnerReminder))
        }
        if preferences.streakReminder.isEnabled, isStreakAtRiskToday {
            result.append(PlannedNotification(
                id: "streakReminder",
                title: String(localized: "Keep your streak alive", bundle: .module, comment: "Streak-at-risk reminder notification title."),
                body: String(localized: "You haven't logged anything today yet -- don't lose your streak.", bundle: .module, comment: "Streak-at-risk reminder notification body."),
                hour: preferences.streakReminder.hour,
                minute: preferences.streakReminder.minute
            ))
        }
        if preferences.dailyChallengeReminder.isEnabled {
            result.append(PlannedNotification(
                id: "dailyChallengeReminder",
                title: String(localized: "Today's challenges are ready", bundle: .module, comment: "Daily-challenge reminder notification title."),
                body: String(localized: "Check today's challenges in GarminFood.", bundle: .module, comment: "Daily-challenge reminder notification body."),
                hour: preferences.dailyChallengeReminder.hour,
                minute: preferences.dailyChallengeReminder.minute
            ))
        }

        return result
    }

    private static func mealReminder(_ mealType: MealType, _ setting: ReminderSetting) -> PlannedNotification {
        PlannedNotification(
            id: "mealReminder.\(mealType.rawValue.lowercased())",
            title: mealType.reminderTitle,
            body: mealType.reminderBody,
            hour: setting.hour,
            minute: setting.minute
        )
    }

    /// A fasting reminder at a fixed clock time, repeating daily
    /// (redesign-fasting-schedule 2.5).
    ///
    /// Unlike every `PlannedNotification` above (one date-scoped request
    /// per day, re-created on each replan -- add-reminders-and-diagnostics
    /// design D2), these are meant to be scheduled as REPEATING daily
    /// requests: the fasting window is the same every day and neither
    /// reminder has a "skip it today" condition, so there is nothing a
    /// daily replan would need to suppress -- and a repeating trigger keeps
    /// firing on days the app isn't opened at all. `id` encodes the fire
    /// time AND the boundary it warns about, so a change to either produces
    /// a different id and the scheduler's diff replaces the stale request.
    public struct PlannedFastingReminder: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let hour: Int
        public let minute: Int

        public init(id: String, title: String, body: String, hour: Int, minute: Int) {
            self.id = id
            self.title = title
            self.body = body
            self.hour = hour
            self.minute = minute
        }
    }

    /// Nothing when fasting is off (`schedule == nil`). Each reminder is
    /// left out when disabled, or when its lead time isn't shorter than the
    /// phase it would fire in (a 60-minute "ends soon" warning on a
    /// 45-minute fast would fire before the fast even began).
    public static func planFastingReminders(
        schedule: FastingSchedule?,
        endsSoon: FastingReminderSetting,
        startsSoon: FastingReminderSetting
    ) -> [PlannedFastingReminder] {
        guard let schedule else { return [] }
        var result: [PlannedFastingReminder] = []

        if endsSoon.isEnabled, endsSoon.minutesBefore > 0, endsSoon.minutesBefore < schedule.fastingMinutes {
            let fire = FastingSchedule.normalized(schedule.endMinute - endsSoon.minutesBefore)
            result.append(PlannedFastingReminder(
                id: "ends.\(fire).\(schedule.endMinute)",
                title: String(localized: "Fasting window ending soon", bundle: .module, comment: "Fasting reminder notification title, shortly before the daily fast ends."),
                body: String(localized: "Your fast ends at \(clockText(schedule.endMinute)) -- eating opens in \(endsSoon.minutesBefore) minutes.", bundle: .module, comment: "Fasting reminder notification body. %@ is a 24-hour clock time (HH:mm), %lld the minutes until eating opens (plural in Localizable.stringsdict)."),
                hour: fire / 60,
                minute: fire % 60
            ))
        }
        if startsSoon.isEnabled, startsSoon.minutesBefore > 0, startsSoon.minutesBefore < schedule.eatingMinutes {
            let fire = FastingSchedule.normalized(schedule.startMinute - startsSoon.minutesBefore)
            result.append(PlannedFastingReminder(
                id: "starts.\(fire).\(schedule.startMinute)",
                title: String(localized: "Fasting starts in \(startsSoon.minutesBefore) min", bundle: .module, comment: "Fasting reminder notification title, shortly before the daily fast starts. %lld is minutes; 'min' is a unit symbol, so no plural."),
                body: String(localized: "Your fasting window starts at \(clockText(schedule.startMinute)).", bundle: .module, comment: "Fasting reminder notification body. %@ is a 24-hour clock time (HH:mm)."),
                hour: fire / 60,
                minute: fire % 60
            ))
        }
        return result
    }

    /// `HH:mm`, 24-hour -- this package has no view-layer locale
    /// formatting (no UI imports), and notification copy is built here.
    static func clockText(_ minuteOfDay: Int) -> String {
        let minute = FastingSchedule.normalized(minuteOfDay)
        return String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    // MARK: - Diff against what's pending (add-localization 3.3b)

    /// The text a notification shows -- what a pending request carries and
    /// what the current plan would give it.
    public struct NotificationText: Sendable, Equatable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// What the scheduler must do to make the pending requests it owns
    /// match the plan. Both lists are sorted, so the outcome is
    /// deterministic whatever order the dictionaries iterate in.
    public struct PendingDiff: Sendable, Equatable {
        /// Owned pending identifiers that are no longer planned.
        public let toRemove: [String]
        /// Planned identifiers to add: not pending yet, OR pending with
        /// different text. Re-adding a request under an identifier that is
        /// still pending replaces it (`UNUserNotificationCenter.add`), so a
        /// changed one needs no separate remove.
        public let toAdd: [String]

        public init(toRemove: [String], toAdd: [String]) {
            self.toRemove = toRemove
            self.toAdd = toAdd
        }
    }

    /// Compares identifiers AND text. Notification text is the one place
    /// display text gets frozen (design.md D6): a request keeps the words
    /// it was scheduled with, so after the phone's (or the app's) language
    /// changes, an identifier-only diff would leave every pending reminder
    /// in the old language -- for the REPEATING fasting reminders, forever,
    /// until their schedule changed. Comparing the text replaces them with
    /// the current language's on the next replan (spec: "Pending reminder
    /// after language change"); any other text change (a new copy
    /// revision) is picked up the same way.
    ///
    /// - Parameters:
    ///   - planned: the full identifier (as scheduled) -> text the current
    ///     plan wants pending.
    ///   - pending: every pending request's identifier -> its text, as
    ///     reported by the system; only those starting with `ownedPrefix`
    ///     are considered, so another cycle's requests are never touched.
    ///   - ownedPrefix: the identifier namespace of the calling cycle.
    public static func diff(
        planned: [String: NotificationText],
        pending: [String: NotificationText],
        ownedPrefix: String
    ) -> PendingDiff {
        let owned = pending.filter { $0.key.hasPrefix(ownedPrefix) }
        let toRemove = owned.keys.filter { planned[$0] == nil }.sorted()
        let toAdd = planned.filter { owned[$0.key] != $0.value }.keys.sorted()
        return PendingDiff(toRemove: toRemove, toAdd: toAdd)
    }
}

extension NotificationPlanning.PlannedNotification {
    /// This notification's title and body, for `NotificationPlanning.diff`.
    public var text: NotificationPlanning.NotificationText {
        NotificationPlanning.NotificationText(title: title, body: body)
    }
}

extension NotificationPlanning.PlannedFastingReminder {
    /// This reminder's title and body, for `NotificationPlanning.diff`.
    public var text: NotificationPlanning.NotificationText {
        NotificationPlanning.NotificationText(title: title, body: body)
    }
}

extension MealType {
    /// Meal reminder copy, one full sentence per meal type (add-localization
    /// design.md D5): Czech needs the meal name in the accusative
    /// ("Zapiš si snídani"), so a meal name can't be inserted into a shared
    /// "Log your %@" template. Private to notification copy -- the app
    /// layer's own `MealType.displayName` is a capitalized UI label.
    fileprivate var reminderTitle: String {
        switch self {
        case .breakfast: return String(localized: "Log your breakfast", bundle: .module, comment: "Meal reminder notification title.")
        case .lunch: return String(localized: "Log your lunch", bundle: .module, comment: "Meal reminder notification title.")
        case .dinner: return String(localized: "Log your dinner", bundle: .module, comment: "Meal reminder notification title.")
        case .snacks: return String(localized: "Log your snacks", bundle: .module, comment: "Meal reminder notification title (Garmin's Snacks meal slot).")
        }
    }

    fileprivate var reminderBody: String {
        switch self {
        case .breakfast: return String(localized: "Don't forget to log breakfast today.", bundle: .module, comment: "Meal reminder notification body.")
        case .lunch: return String(localized: "Don't forget to log lunch today.", bundle: .module, comment: "Meal reminder notification body.")
        case .dinner: return String(localized: "Don't forget to log dinner today.", bundle: .module, comment: "Meal reminder notification body.")
        case .snacks: return String(localized: "Don't forget to log snacks today.", bundle: .module, comment: "Meal reminder notification body (Garmin's Snacks meal slot).")
        }
    }
}
