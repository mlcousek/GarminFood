// NotificationWindowTests.swift
//
// fix-review-findings-2026-09 findings 10 and 11: reminders are planned for
// a rolling window of days (so they keep firing after midnight while the
// app stays closed), and granting the permission prompt triggers a re-sync
// (the sync a toggle fired while permission was undecided scheduled
// nothing).

import XCTest
@testable import FoodLogCore
import GarminKit

final class NotificationWindowTests: XCTestCase {
    private var everythingOn: NotificationPreferences {
        var preferences = NotificationPreferences.disabledDefault
        preferences.breakfastReminder.isEnabled = true
        preferences.lunchReminder.isEnabled = true
        preferences.dinnerReminder.isEnabled = true
        preferences.streakReminder.isEnabled = true
        preferences.dailyChallengeReminder.isEnabled = true
        return preferences
    }

    func testTheWindowCoversEveryDayNotJustToday() {
        let planned = NotificationPlanning.planWindow(
            preferences: everythingOn,
            mealsLoggedToday: [],
            isStreakAtRiskToday: false,
            days: 7
        )

        XCTAssertEqual(Set(planned.map(\.dayOffset)), Set(0..<7), "tomorrow's reminders already exist if the app stays closed")
        let tomorrow = planned.filter { $0.dayOffset == 1 }.map(\.notification.id)
        XCTAssertEqual(Set(tomorrow), ["mealReminder.breakfast", "mealReminder.lunch", "mealReminder.dinner", "dailyChallengeReminder"])
    }

    func testTodayKeepsTodaysRulesAndLaterDaysAssumeNothingLoggedYet() {
        let planned = NotificationPlanning.planWindow(
            preferences: everythingOn,
            mealsLoggedToday: [.breakfast],
            isStreakAtRiskToday: true,
            days: 3
        )

        let today = planned.filter { $0.dayOffset == 0 }.map(\.notification.id)
        XCTAssertFalse(today.contains("mealReminder.breakfast"), "already logged today")
        XCTAssertTrue(today.contains("streakReminder"))
        let later = planned.filter { $0.dayOffset > 0 }.map(\.notification.id)
        XCTAssertTrue(later.contains("mealReminder.breakfast"), "tomorrow's breakfast isn't logged yet")
        XCTAssertFalse(later.contains("streakReminder"), "tomorrow's streak risk can't be known ahead")
        XCTAssertEqual(
            planned.filter { $0.dayOffset == 0 }.map(\.notification),
            NotificationPlanning.plan(preferences: everythingOn, mealsLoggedToday: [.breakfast], isStreakAtRiskToday: true),
            "day 0 is exactly today's plan"
        )
    }

    func testTheDefaultWindowStaysWellInsideTheSystemLimit() {
        let planned = NotificationPlanning.planWindow(preferences: everythingOn, mealsLoggedToday: [], isStreakAtRiskToday: true)
        XCTAssertLessThanOrEqual(planned.count, 32, "iOS keeps at most 64 pending requests across every reminder kind")
    }

    func testGrantingPermissionTriggersAResyncOnlyOnTheTransition() {
        XCTAssertTrue(NotificationPlanning.needsResyncAfterPermissionChange(wasAllowed: false, isAllowed: true))
        XCTAssertFalse(NotificationPlanning.needsResyncAfterPermissionChange(wasAllowed: true, isAllowed: true), "already scheduled by the toggle's own sync")
        XCTAssertFalse(NotificationPlanning.needsResyncAfterPermissionChange(wasAllowed: false, isAllowed: false), "denied: nothing can be scheduled")
    }
}
