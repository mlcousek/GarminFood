import XCTest
@testable import Gamification
import FoodLogCore

// NewChallengeKindTests.swift
//
// expand-gamification-depth task 2.5: the five ChallengeKind cases added by
// this change (mealSlotAbsent, allGoalsHitDays, allFourMealSlotsDays,
// sameFoodConsecutiveDays, consecutiveWeekendsBothDays), each with a
// happy-path and a non-trivial edge case -- constructed against ad hoc
// templates rather than catalog lookups, so these tests don't depend on the
// exact generated ids in ChallengeTemplates.swift.
final class NewChallengeKindTests: XCTestCase {
    private func event(_ foodId: String, day: Int, hour: Int = 12) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s1", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, day, hour: hour))
    }

    private func goalStatus(day: Int, calories: Bool = false, protein: Bool = false, carbs: Bool = false, fat: Bool = false) -> DailyGoalStatus {
        DailyGoalStatus(date: String(format: "2026-01-%02d", day), metCalorieGoal: calories, metProteinGoal: protein, metCarbGoal: carbs, metFatGoal: fat)
    }

    private func template(kind: ChallengeKind, windowDays: Int) -> ChallengeTemplate {
        ChallengeTemplate(id: "test", title: "Test", subtitle: "Test", category: .varietySeeking, windowDays: windowDays, xpReward: 10, kind: kind)
    }

    private func progress(kind: ChallengeKind, windowDays: Int, events: [UsageEvent] = [], goals: [DailyGoalStatus] = [], startDay: Int = 1, now: Date) -> ChallengeProgress {
        let active = ActiveChallenge(templateId: "test", startedAt: TestClock.date(2026, 1, startDay), baselineStreakLength: 0)
        return ChallengeEngine.progress(for: template(kind: kind, windowDays: windowDays), active: active, events: events, goalStatuses: goals, now: now, calendar: TestClock.calendar)
    }

    // MARK: - mealSlotAbsent

    func testMealSlotAbsentCountsDaysWithAnEntryButNothingInTheBucket() {
        // Day 1: breakfast only, snack absent. Day 2: lunch + dinner, snack
        // absent. Day 3: snack present -- does not count.
        let events = [
            event("a", day: 1, hour: 7),
            event("b", day: 2, hour: 12), event("c", day: 2, hour: 19),
            event("d", day: 3, hour: 16)
        ]
        let result = progress(kind: .mealSlotAbsent(bucket: .snack, minDays: 2), windowDays: 5, events: events, now: TestClock.date(2026, 1, 3, hour: 22))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    func testMealSlotAbsentDoesNotCountAFullyEmptyDay() {
        // Only day 1 has any entry at all; days 2-3 are simply empty, not
        // "snack-free days" -- an empty day must never trivially count.
        let events = [event("a", day: 1, hour: 7)]
        let result = progress(kind: .mealSlotAbsent(bucket: .snack, minDays: 3), windowDays: 5, events: events, now: TestClock.date(2026, 1, 3, hour: 22))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - allGoalsHitDays

    func testAllGoalsHitDaysRequiresEveryMacroTheSameDay() {
        let goals = [
            goalStatus(day: 1, calories: true, protein: true, carbs: true, fat: true),
            goalStatus(day: 2, calories: true, protein: true, carbs: true, fat: false), // fat missed
            goalStatus(day: 3, calories: true, protein: true, carbs: true, fat: true)
        ]
        let result = progress(kind: .allGoalsHitDays(minCount: 2), windowDays: 5, goals: goals, now: TestClock.date(2026, 1, 3, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    func testAllGoalsHitDaysIsIncompleteWhenOnlyOneDayIsFullyMet() {
        let goals = [
            goalStatus(day: 1, calories: true, protein: true, carbs: true, fat: true),
            goalStatus(day: 2, calories: true, protein: false, carbs: true, fat: true)
        ]
        let result = progress(kind: .allGoalsHitDays(minCount: 2), windowDays: 5, goals: goals, now: TestClock.date(2026, 1, 3, hour: 20))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - allFourMealSlotsDays

    func testAllFourMealSlotsDaysRequiresAllFourBucketsNotJustSome() {
        let fullDay = [event("a", day: 1, hour: 7), event("b", day: 1, hour: 12), event("c", day: 1, hour: 16), event("d", day: 1, hour: 19)]
        let threeBucketDay = [event("e", day: 2, hour: 7), event("f", day: 2, hour: 12), event("g", day: 2, hour: 19)]
        let result = progress(kind: .allFourMealSlotsDays(minDays: 2), windowDays: 5, events: fullDay + threeBucketDay, now: TestClock.date(2026, 1, 2, hour: 22))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    func testAllFourMealSlotsDaysCompletesWhenEveryBucketIsCoveredOnEnoughDays() {
        let day1 = [event("a", day: 1, hour: 7), event("b", day: 1, hour: 12), event("c", day: 1, hour: 16), event("d", day: 1, hour: 19)]
        let day2 = [event("e", day: 2, hour: 7), event("f", day: 2, hour: 12), event("g", day: 2, hour: 16), event("h", day: 2, hour: 19)]
        let result = progress(kind: .allFourMealSlotsDays(minDays: 2), windowDays: 5, events: day1 + day2, now: TestClock.date(2026, 1, 2, hour: 22))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    // MARK: - sameFoodConsecutiveDays

    func testSameFoodConsecutiveDaysTracksASingleFoodAcrossConsecutiveDays() {
        let events = [event("oatmeal", day: 1), event("oatmeal", day: 2), event("oatmeal", day: 3), event("other", day: 3)]
        let result = progress(kind: .sameFoodConsecutiveDays(minDays: 3), windowDays: 5, events: events, now: TestClock.date(2026, 1, 3, hour: 20))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    func testSameFoodConsecutiveDaysDoesNotChainDifferentFoodsAcrossDays() {
        // Day 1 has {a, b}, day 2 has {b, c}, day 3 has {c, d} -- pairwise
        // overlapping, but no SINGLE food spans all three days.
        let events = [
            event("a", day: 1), event("b", day: 1),
            event("b", day: 2), event("c", day: 2),
            event("c", day: 3), event("d", day: 3)
        ]
        let result = progress(kind: .sameFoodConsecutiveDays(minDays: 3), windowDays: 5, events: events, now: TestClock.date(2026, 1, 3, hour: 20))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    // MARK: - consecutiveWeekendsBothDays

    func testConsecutiveWeekendsBothDaysRequiresBackToBackCompleteWeekends() {
        // 2026-01-03/04 and 2026-01-10/11 are consecutive Sat/Sun weekends.
        let events = [
            event("a", day: 3), event("b", day: 4), // weekend 1
            event("c", day: 10), event("d", day: 11) // weekend 2
        ]
        let result = progress(kind: .consecutiveWeekendsBothDays(weekends: 2), windowDays: 16, events: events, now: TestClock.date(2026, 1, 11, hour: 22))
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    func testConsecutiveWeekendsBothDaysResetsWhenAWeekendIsIncomplete() {
        let events = [
            event("a", day: 3), event("b", day: 4), // weekend 1: complete
            event("c", day: 10), // weekend 2: Sunday missing
            event("d", day: 17), event("e", day: 18) // weekend 3: complete, but not consecutive with weekend 1
        ]
        let result = progress(kind: .consecutiveWeekendsBothDays(weekends: 2), windowDays: 23, events: events, now: TestClock.date(2026, 1, 18, hour: 22))
        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }
}
