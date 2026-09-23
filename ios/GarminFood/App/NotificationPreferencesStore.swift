// NotificationPreferencesStore.swift
//
// Persists `FoodLogCore.NotificationPreferences` -- same `UserDefaults`
// pattern as `AppPreferences.swift` (no App Group, nothing in the widget
// extension needs these values). A separate store from `AppPreferences`
// rather than folding these fields in there: reminders are a big enough,
// separately-navigated settings screen (`NotificationSettingsView`) to earn
// their own persistence unit, matching how `SyncQueueView`/`DiagnosticsLogView`
// are also their own screens rather than crammed into the main Settings form.

import Foundation
import Observation
import FoodLogCore

@MainActor
@Observable
final class NotificationPreferencesStore {
    private enum Key {
        static let breakfastEnabled = "notifications.breakfast.enabled"
        static let breakfastHour = "notifications.breakfast.hour"
        static let breakfastMinute = "notifications.breakfast.minute"
        static let lunchEnabled = "notifications.lunch.enabled"
        static let lunchHour = "notifications.lunch.hour"
        static let lunchMinute = "notifications.lunch.minute"
        static let dinnerEnabled = "notifications.dinner.enabled"
        static let dinnerHour = "notifications.dinner.hour"
        static let dinnerMinute = "notifications.dinner.minute"
        static let streakEnabled = "notifications.streak.enabled"
        static let streakHour = "notifications.streak.hour"
        static let streakMinute = "notifications.streak.minute"
        static let challengeEnabled = "notifications.dailyChallenge.enabled"
        static let challengeHour = "notifications.dailyChallenge.hour"
        static let challengeMinute = "notifications.dailyChallenge.minute"
        static let fastingEnabled = "notifications.fasting.enabled"
        static let fastingMinutesBefore = "notifications.fasting.minutesBefore"
        // redesign-fasting-schedule 2.5: "fast starts soon".
        static let fastingStartEnabled = "notifications.fasting.start.enabled"
        static let fastingStartMinutesBefore = "notifications.fasting.start.minutesBefore"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var preferences: NotificationPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = NotificationPreferences.disabledDefault
        preferences = NotificationPreferences(
            breakfastReminder: Self.read(defaults, Key.breakfastEnabled, Key.breakfastHour, Key.breakfastMinute, fallback.breakfastReminder),
            lunchReminder: Self.read(defaults, Key.lunchEnabled, Key.lunchHour, Key.lunchMinute, fallback.lunchReminder),
            dinnerReminder: Self.read(defaults, Key.dinnerEnabled, Key.dinnerHour, Key.dinnerMinute, fallback.dinnerReminder),
            streakReminder: Self.read(defaults, Key.streakEnabled, Key.streakHour, Key.streakMinute, fallback.streakReminder),
            dailyChallengeReminder: Self.read(defaults, Key.challengeEnabled, Key.challengeHour, Key.challengeMinute, fallback.dailyChallengeReminder),
            fastingReminder: FastingReminderSetting(
                isEnabled: defaults.object(forKey: Key.fastingEnabled) as? Bool ?? fallback.fastingReminder.isEnabled,
                minutesBefore: defaults.object(forKey: Key.fastingMinutesBefore) as? Int ?? fallback.fastingReminder.minutesBefore
            ),
            fastingStartReminder: FastingReminderSetting(
                isEnabled: defaults.object(forKey: Key.fastingStartEnabled) as? Bool ?? fallback.fastingStartReminder.isEnabled,
                minutesBefore: defaults.object(forKey: Key.fastingStartMinutesBefore) as? Int ?? fallback.fastingStartReminder.minutesBefore
            )
        )
    }

    func setBreakfastReminder(_ setting: ReminderSetting) {
        preferences.breakfastReminder = setting
        write(setting, Key.breakfastEnabled, Key.breakfastHour, Key.breakfastMinute)
    }

    func setLunchReminder(_ setting: ReminderSetting) {
        preferences.lunchReminder = setting
        write(setting, Key.lunchEnabled, Key.lunchHour, Key.lunchMinute)
    }

    func setDinnerReminder(_ setting: ReminderSetting) {
        preferences.dinnerReminder = setting
        write(setting, Key.dinnerEnabled, Key.dinnerHour, Key.dinnerMinute)
    }

    func setStreakReminder(_ setting: ReminderSetting) {
        preferences.streakReminder = setting
        write(setting, Key.streakEnabled, Key.streakHour, Key.streakMinute)
    }

    func setDailyChallengeReminder(_ setting: ReminderSetting) {
        preferences.dailyChallengeReminder = setting
        write(setting, Key.challengeEnabled, Key.challengeHour, Key.challengeMinute)
    }

    func setFastingReminder(_ setting: FastingReminderSetting) {
        preferences.fastingReminder = setting
        defaults.set(setting.isEnabled, forKey: Key.fastingEnabled)
        defaults.set(setting.minutesBefore, forKey: Key.fastingMinutesBefore)
    }

    func setFastingStartReminder(_ setting: FastingReminderSetting) {
        preferences.fastingStartReminder = setting
        defaults.set(setting.isEnabled, forKey: Key.fastingStartEnabled)
        defaults.set(setting.minutesBefore, forKey: Key.fastingStartMinutesBefore)
    }

    private func write(_ setting: ReminderSetting, _ enabledKey: String, _ hourKey: String, _ minuteKey: String) {
        defaults.set(setting.isEnabled, forKey: enabledKey)
        defaults.set(setting.hour, forKey: hourKey)
        defaults.set(setting.minute, forKey: minuteKey)
    }

    private static func read(_ defaults: UserDefaults, _ enabledKey: String, _ hourKey: String, _ minuteKey: String, _ fallback: ReminderSetting) -> ReminderSetting {
        ReminderSetting(
            isEnabled: defaults.object(forKey: enabledKey) as? Bool ?? fallback.isEnabled,
            hour: defaults.object(forKey: hourKey) as? Int ?? fallback.hour,
            minute: defaults.object(forKey: minuteKey) as? Int ?? fallback.minute
        )
    }
}
