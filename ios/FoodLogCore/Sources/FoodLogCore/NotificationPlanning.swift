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

public struct NotificationPreferences: Sendable, Equatable {
    public var breakfastReminder: ReminderSetting
    public var lunchReminder: ReminderSetting
    public var dinnerReminder: ReminderSetting
    public var streakReminder: ReminderSetting
    public var dailyChallengeReminder: ReminderSetting

    public init(
        breakfastReminder: ReminderSetting,
        lunchReminder: ReminderSetting,
        dinnerReminder: ReminderSetting,
        streakReminder: ReminderSetting,
        dailyChallengeReminder: ReminderSetting
    ) {
        self.breakfastReminder = breakfastReminder
        self.lunchReminder = lunchReminder
        self.dinnerReminder = dinnerReminder
        self.streakReminder = streakReminder
        self.dailyChallengeReminder = dailyChallengeReminder
    }

    /// Off by default, times chosen as reasonable defaults matching
    /// Garmin's own typical meal windows -- turned on explicitly by the
    /// user in Settings, never silently opted in.
    public static let disabledDefault = NotificationPreferences(
        breakfastReminder: ReminderSetting(isEnabled: false, hour: 9, minute: 0),
        lunchReminder: ReminderSetting(isEnabled: false, hour: 13, minute: 30),
        dinnerReminder: ReminderSetting(isEnabled: false, hour: 19, minute: 30),
        streakReminder: ReminderSetting(isEnabled: false, hour: 21, minute: 0),
        dailyChallengeReminder: ReminderSetting(isEnabled: false, hour: 8, minute: 0)
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
                title: "Keep your streak alive",
                body: "You haven't logged anything today yet -- don't lose your streak.",
                hour: preferences.streakReminder.hour,
                minute: preferences.streakReminder.minute
            ))
        }
        if preferences.dailyChallengeReminder.isEnabled {
            result.append(PlannedNotification(
                id: "dailyChallengeReminder",
                title: "Today's challenges are ready",
                body: "Check today's challenges in GarminFood.",
                hour: preferences.dailyChallengeReminder.hour,
                minute: preferences.dailyChallengeReminder.minute
            ))
        }

        return result
    }

    private static func mealReminder(_ mealType: MealType, _ setting: ReminderSetting) -> PlannedNotification {
        PlannedNotification(
            id: "mealReminder.\(mealType.rawValue.lowercased())",
            title: "Log your \(mealType.displayNameLowercased)",
            body: "Don't forget to log \(mealType.displayNameLowercased) today.",
            hour: setting.hour,
            minute: setting.minute
        )
    }
}

extension MealType {
    /// Used only for notification copy -- the app layer's own
    /// `MealType.displayName` (GarminFood/App/LogContext.swift) is
    /// capitalized for UI labels, which reads oddly mid-sentence ("Log your
    /// Breakfast today"). FoodLogCore has no UI-facing display name of its
    /// own otherwise, so this stays a small, private-to-this-purpose helper.
    fileprivate var displayNameLowercased: String {
        switch self {
        case .breakfast: return "breakfast"
        case .lunch: return "lunch"
        case .dinner: return "dinner"
        case .snacks: return "snacks"
        }
    }
}
