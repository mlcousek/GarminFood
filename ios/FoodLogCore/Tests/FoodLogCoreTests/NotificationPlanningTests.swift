// NotificationPlanningTests.swift
//
// Pure decision-logic tests for NotificationPlanning.swift.

import XCTest
@testable import FoodLogCore

final class NotificationPlanningTests: XCTestCase {
    func testDisabledDefaultPlansNothing() {
        let plan = NotificationPlanning.plan(
            preferences: .disabledDefault,
            mealsLoggedToday: [],
            isStreakAtRiskToday: true
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testEnabledMealReminderIsPlannedWhenNotYetLogged() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.breakfastReminder.isEnabled = true

        let plan = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [], isStreakAtRiskToday: false)

        XCTAssertEqual(plan.map(\.id), ["mealReminder.breakfast"])
    }

    func testMealReminderIsSkippedOnceThatMealIsLogged() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.breakfastReminder.isEnabled = true

        let plan = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [.breakfast], isStreakAtRiskToday: false)

        XCTAssertTrue(plan.isEmpty, "a meal already logged today needs no reminder")
    }

    func testStreakReminderOnlyFiresWhenAtRisk() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.streakReminder.isEnabled = true

        let atRisk = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [], isStreakAtRiskToday: true)
        let safe = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [], isStreakAtRiskToday: false)

        XCTAssertEqual(atRisk.map(\.id), ["streakReminder"])
        XCTAssertTrue(safe.isEmpty)
    }

    func testDailyChallengeReminderIsUnconditional() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.dailyChallengeReminder.isEnabled = true

        let plan = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [.breakfast, .lunch, .dinner], isStreakAtRiskToday: false)

        XCTAssertEqual(plan.map(\.id), ["dailyChallengeReminder"])
    }

    func testEveryReminderEnabledAndNothingLoggedPlansAllFive() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.breakfastReminder.isEnabled = true
        prefs.lunchReminder.isEnabled = true
        prefs.dinnerReminder.isEnabled = true
        prefs.streakReminder.isEnabled = true
        prefs.dailyChallengeReminder.isEnabled = true

        let plan = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [], isStreakAtRiskToday: true)

        XCTAssertEqual(Set(plan.map(\.id)), [
            "mealReminder.breakfast", "mealReminder.lunch", "mealReminder.dinner", "streakReminder", "dailyChallengeReminder",
        ])
    }

    func testPlannedNotificationCarriesTheConfiguredTime() {
        var prefs = NotificationPreferences.disabledDefault
        prefs.lunchReminder = ReminderSetting(isEnabled: true, hour: 12, minute: 45)

        let plan = NotificationPlanning.plan(preferences: prefs, mealsLoggedToday: [], isStreakAtRiskToday: false)

        XCTAssertEqual(plan.first?.hour, 12)
        XCTAssertEqual(plan.first?.minute, 45)
    }
}
