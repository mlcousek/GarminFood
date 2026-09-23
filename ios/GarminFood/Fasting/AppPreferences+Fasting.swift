// AppPreferences+Fasting.swift
//
// Turns the raw fasting preferences (AppPreferences.swift -- enabled flag
// and two minutes-of-day) into the domain `FastingSchedule` every fasting
// surface reads: the home card, the history screen, the confirm screens'
// note and the reminder planner (redesign-fasting-schedule). A separate
// file so AppPreferences.swift itself stays free of a FoodLogCore import
// and only gains the Key/stored/computed entries its own pattern needs.

import Foundation
import FoodLogCore

extension AppPreferences {
    /// The configured window, whether or not fasting is on. `nil` when the
    /// two times are equal (not a real window -- the settings section says
    /// so rather than silently picking one).
    var fastingSchedule: FastingSchedule? {
        FastingSchedule(startMinute: fastingStartMinute, endMinute: fastingEndMinute)
    }

    /// The window every fasting surface should act on: `nil` while fasting
    /// is off or the times are invalid, which hides the home card, the
    /// confirm-screen note and the reminders together.
    var activeFastingSchedule: FastingSchedule? {
        fastingEnabled ? fastingSchedule : nil
    }

    /// Applies the one-time legacy seed (task 1.3). Uses the ordinary
    /// setters, so turning fasting on here also starts tracking from now.
    func applyFastingMigration(_ seed: FastingScheduleMigration.Seed) {
        fastingStartMinute = seed.schedule.startMinute
        fastingEndMinute = seed.schedule.endMinute
        fastingEnabled = seed.isEnabled
        fastingLegacyMigrated = true
    }
}
