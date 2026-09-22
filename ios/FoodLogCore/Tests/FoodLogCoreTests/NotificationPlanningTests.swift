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

    // MARK: - Fasting reminder

    func testPlanFastingReminderIsNilWhenDisabled() {
        let now = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: now)

        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: false, minutesBefore: 15),
            activeSession: session,
            now: now
        )

        XCTAssertNil(planned)
    }

    func testPlanFastingReminderIsNilWithNoActiveSession() {
        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: true, minutesBefore: 15),
            activeSession: nil,
            now: Date()
        )

        XCTAssertNil(planned)
    }

    func testPlanFastingReminderFiresBeforeTheFastingPhaseEnds() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)
        let now = start.addingTimeInterval(10 * 3600) // 10h into a 16h fast

        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: true, minutesBefore: 15),
            activeSession: session,
            now: now
        )

        XCTAssertEqual(planned?.fireDate, start.addingTimeInterval(16 * 3600 - 15 * 60))
        XCTAssertEqual(planned?.title, "Fasting window ending soon")
    }

    func testPlanFastingReminderFiresBeforeTheEatingPhaseEndsOnceFastIsBroken() {
        let start = Date(timeIntervalSince1970: 0)
        let brokeFastAt = start.addingTimeInterval(16 * 3600)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start, fastingEndedAt: brokeFastAt)
        let now = brokeFastAt.addingTimeInterval(3600)

        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: true, minutesBefore: 15),
            activeSession: session,
            now: now
        )

        XCTAssertEqual(planned?.fireDate, brokeFastAt.addingTimeInterval(8 * 3600 - 15 * 60))
        XCTAssertEqual(planned?.title, "Eating window ending soon")
    }

    func testPlanFastingReminderIsNilOnceTheFireDateHasAlreadyPassed() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)
        // Only 5 minutes left before the 16h boundary, but the setting wants
        // 15 minutes of lead time -- the fire date is already in the past.
        let now = start.addingTimeInterval(16 * 3600 - 5 * 60)

        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: true, minutesBefore: 15),
            activeSession: session,
            now: now
        )

        XCTAssertNil(planned)
    }

    func testPlanFastingReminderIsNilOnceThePhaseIsAlreadyOverdue() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)
        let now = start.addingTimeInterval(20 * 3600) // past the 16h boundary, fast never explicitly broken

        let planned = NotificationPlanning.planFastingReminder(
            setting: FastingReminderSetting(isEnabled: true, minutesBefore: 15),
            activeSession: session,
            now: now
        )

        XCTAssertNil(planned)
    }
}
