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

    // MARK: - Fasting reminders (redesign-fasting-schedule 2.5)

    private let on15 = FastingReminderSetting(isEnabled: true, minutesBefore: 15)
    private let off15 = FastingReminderSetting(isEnabled: false, minutesBefore: 15)

    func testNoFastingRemindersWhileFastingIsOff() {
        let planned = NotificationPlanning.planFastingReminders(schedule: nil, endsSoon: on15, startsSoon: on15)
        XCTAssertTrue(planned.isEmpty)
    }

    func testNoFastingRemindersWhenBothAreDisabled() {
        let planned = NotificationPlanning.planFastingReminders(schedule: .standard, endsSoon: off15, startsSoon: off15)
        XCTAssertTrue(planned.isEmpty)
    }

    func testFastEndsSoonFiresBeforeTheScheduledEnd() {
        let planned = NotificationPlanning.planFastingReminders(schedule: .standard, endsSoon: on15, startsSoon: off15)

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.hour, 11)
        XCTAssertEqual(planned.first?.minute, 45)
        XCTAssertEqual(planned.first?.title, "Fasting window ending soon")
        XCTAssertEqual(planned.first?.body.contains("12:00"), true)
    }

    func testFastStartsSoonFiresBeforeTheScheduledStart() {
        let planned = NotificationPlanning.planFastingReminders(schedule: .standard, endsSoon: off15, startsSoon: on15)

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.hour, 19)
        XCTAssertEqual(planned.first?.minute, 45)
        XCTAssertEqual(planned.first?.title, "Fasting starts in 15 min")
        XCTAssertEqual(planned.first?.body.contains("20:00"), true)
    }

    func testBothRemindersHaveDistinctIdentifiers() {
        let planned = NotificationPlanning.planFastingReminders(schedule: .standard, endsSoon: on15, startsSoon: on15)
        XCTAssertEqual(Set(planned.map(\.id)).count, 2)
    }

    func testAStartJustAfterMidnightWrapsTheReminderToTheEveningBefore() {
        let schedule = FastingSchedule(startMinute: 10, endMinute: 8 * 60)!

        let planned = NotificationPlanning.planFastingReminders(schedule: schedule, endsSoon: off15, startsSoon: on15)

        XCTAssertEqual(planned.first?.hour, 23)
        XCTAssertEqual(planned.first?.minute, 55)
    }

    func testALeadTimeLongerThanThePhaseIsLeftOut() {
        // A 30-minute fast can't warn 45 minutes before it ends.
        let shortFast = FastingSchedule(startMinute: 12 * 60, endMinute: 12 * 60 + 30)!

        let planned = NotificationPlanning.planFastingReminders(
            schedule: shortFast,
            endsSoon: FastingReminderSetting(isEnabled: true, minutesBefore: 45),
            startsSoon: off15
        )

        XCTAssertTrue(planned.isEmpty)
    }

    func testChangingTheLeadTimeOrTheWindowChangesTheIdentifier() {
        let base = NotificationPlanning.planFastingReminders(schedule: .standard, endsSoon: on15, startsSoon: off15)
        let longerLead = NotificationPlanning.planFastingReminders(
            schedule: .standard,
            endsSoon: FastingReminderSetting(isEnabled: true, minutesBefore: 30),
            startsSoon: off15
        )
        let laterWindow = NotificationPlanning.planFastingReminders(
            schedule: FastingSchedule(startMinute: 21 * 60, endMinute: 13 * 60)!,
            endsSoon: on15,
            startsSoon: off15
        )

        XCTAssertNotEqual(base.first?.id, longerLead.first?.id)
        XCTAssertNotEqual(base.first?.id, laterWindow.first?.id)
    }

    func testDefaultPreferencesHaveBothFastingRemindersOff() {
        XCTAssertFalse(NotificationPreferences.disabledDefault.fastingReminder.isEnabled)
        XCTAssertFalse(NotificationPreferences.disabledDefault.fastingStartReminder.isEnabled)
    }
}

