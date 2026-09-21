import XCTest
@testable import Gamification
import FoodLogCore

// DailyChallengeTests.swift
//
// expand-gamification-depth task 3.6: catalog sanity, every
// DailyChallengeKind's evaluation, deterministic same-day selection, the
// 30-day no-repeat rule (including its fewer-than-2-eligible fallback),
// and DailyChallengeStore's idempotent same-day XP-award bookkeeping.
final class DailyChallengeTests: XCTestCase {
    private func event(_ foodId: String, hour: Int) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s1", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, 15, hour: hour))
    }

    private func goalStatus(calories: Bool = false, protein: Bool = false, carbs: Bool = false, fat: Bool = false) -> DailyGoalStatus {
        DailyGoalStatus(date: "2026-01-15", metCalorieGoal: calories, metProteinGoal: protein, metCarbGoal: carbs, metFatGoal: fat)
    }

    // MARK: - Catalog sanity

    func testCatalogHasAtLeast120Templates() {
        XCTAssertGreaterThanOrEqual(DailyChallengeCatalog.all.count, 120)
    }

    func testCatalogIdsAreUnique() {
        let ids = DailyChallengeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - DailyChallengeEngine, one case per kind

    func testLogAtLeast() {
        let events = [event("a", hour: 8), event("b", hour: 13)]
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .logAtLeast(count: 2), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .logAtLeast(count: 3), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testLogDistinctFoods() {
        let events = [event("a", hour: 8), event("a", hour: 13), event("b", hour: 19)]
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .logDistinctFoods(count: 2), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .logDistinctFoods(count: 3), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testLogInMealSlot() {
        let events = [event("a", hour: 8)]
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .logInMealSlot(bucket: .breakfast), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .logInMealSlot(bucket: .dinner), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testAvoidMealSlotRequiresAtLeastOneEntryButNoneInTheBucket() {
        let events = [event("a", hour: 8)]
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .avoidMealSlot(bucket: .snack), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .avoidMealSlot(bucket: .breakfast), dayEvents: events, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        // A fully empty day never trivially counts.
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .avoidMealSlot(bucket: .snack), dayEvents: [], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testHitCalorieGoal() {
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .hitCalorieGoal, dayEvents: [], priorEvents: [], goalStatus: goalStatus(calories: true), calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .hitCalorieGoal, dayEvents: [], priorEvents: [], goalStatus: goalStatus(calories: false), calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .hitCalorieGoal, dayEvents: [], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testHitMacroGoal() {
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .hitMacroGoal(macro: .protein), dayEvents: [], priorEvents: [], goalStatus: goalStatus(protein: true), calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .hitMacroGoal(macro: .protein), dayEvents: [], priorEvents: [], goalStatus: goalStatus(carbs: true), calendar: TestClock.calendar))
    }

    func testHitAllGoalsRequiresEveryMacro() {
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .hitAllGoals, dayEvents: [], priorEvents: [], goalStatus: goalStatus(calories: true, protein: true, carbs: true, fat: true), calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .hitAllGoals, dayEvents: [], priorEvents: [], goalStatus: goalStatus(calories: true, protein: true, carbs: true, fat: false), calendar: TestClock.calendar))
    }

    func testTryNewFoodComparesAgainstPriorHistoryOnly() {
        let dayEvents = [event("brand-new", hour: 12)]
        let prior = [event("already-seen", hour: 12)]
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .tryNewFood, dayEvents: dayEvents, priorEvents: prior, goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .tryNewFood, dayEvents: [event("already-seen", hour: 12)], priorEvents: prior, goalStatus: nil, calendar: TestClock.calendar))
    }

    func testLogAllFourSlotsRequiresEveryBucket() {
        let three = [event("a", hour: 8), event("b", hour: 13), event("c", hour: 19)]
        let four = three + [event("d", hour: 16)]
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .logAllFourSlots, dayEvents: three, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .logAllFourSlots, dayEvents: four, priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testEarlyLogUsesTheRealHourNotTheBucket() {
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .earlyLog(beforeHour: 8), dayEvents: [event("a", hour: 6)], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .earlyLog(beforeHour: 8), dayEvents: [event("a", hour: 9)], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    func testLateLogUsesTheRealHourNotTheBucket() {
        XCTAssertTrue(DailyChallengeEngine.isComplete(kind: .lateLog(afterHour: 20), dayEvents: [event("a", hour: 21)], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
        XCTAssertFalse(DailyChallengeEngine.isComplete(kind: .lateLog(afterHour: 20), dayEvents: [event("a", hour: 19)], priorEvents: [], goalStatus: nil, calendar: TestClock.calendar))
    }

    // MARK: - Selection

    func testSelectionIsDeterministicForTheSameSeed() {
        let a = DailyChallengeSelection.pick(from: DailyChallengeCatalog.all, lastShown: [:], seed: "2026-01-15", today: TestClock.date(2026, 1, 15), noRepeatDays: 30, calendar: TestClock.calendar, count: 2)
        let b = DailyChallengeSelection.pick(from: DailyChallengeCatalog.all, lastShown: [:], seed: "2026-01-15", today: TestClock.date(2026, 1, 15), noRepeatDays: 30, calendar: TestClock.calendar, count: 2)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, 2)
        XCTAssertNotEqual(a[0].id, a[1].id)
    }

    func testSelectionExcludesTemplatesShownWithinTheNoRepeatWindow() {
        let recentlyShown = DailyChallengeTemplate(id: "recent", title: "Recent", subtitle: "Recent", kind: .logAtLeast(count: 1))
        let neverShown = DailyChallengeTemplate(id: "fresh", title: "Fresh", subtitle: "Fresh", kind: .logAtLeast(count: 1))
        let lastShown = [recentlyShown.id: TestClock.date(2026, 1, 10)] // 5 days before "today"

        let picked = DailyChallengeSelection.pick(from: [recentlyShown, neverShown], lastShown: lastShown, seed: "2026-01-15", today: TestClock.date(2026, 1, 15), noRepeatDays: 30, calendar: TestClock.calendar, count: 1)
        XCTAssertEqual(picked.map(\.id), ["fresh"])
    }

    func testSelectionFallsBackToLeastRecentlyShownWhenTooFewAreEligible() {
        // A tiny two-template catalog where BOTH were shown recently: the
        // 30-day rule alone would leave zero eligible, so the fallback must
        // still return `count` templates rather than leaving the day short.
        let older = DailyChallengeTemplate(id: "older", title: "Older", subtitle: "Older", kind: .logAtLeast(count: 1))
        let newer = DailyChallengeTemplate(id: "newer", title: "Newer", subtitle: "Newer", kind: .logAtLeast(count: 1))
        let lastShown = [older.id: TestClock.date(2026, 1, 1), newer.id: TestClock.date(2026, 1, 10)]

        let picked = DailyChallengeSelection.pick(from: [older, newer], lastShown: lastShown, seed: "2026-01-15", today: TestClock.date(2026, 1, 15), noRepeatDays: 30, calendar: TestClock.calendar, count: 2)
        XCTAssertEqual(picked.count, 2, "must never leave a day short even when nothing satisfies the no-repeat rule")
        XCTAssertEqual(Set(picked.map(\.id)), ["older", "newer"])
    }

    // MARK: - Store

    private func makeStore() -> DailyChallengeStore {
        DailyChallengeStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-daily-\(UUID().uuidString).json"))
    }

    func testTemplatesForDayReturnsTheSameTwoOnASecondCallTheSameDay() async throws {
        let store = makeStore()
        let first = try await store.templatesForDay("2026-01-15", catalog: DailyChallengeCatalog.all, calendar: TestClock.calendar)
        let second = try await store.templatesForDay("2026-01-15", catalog: DailyChallengeCatalog.all, calendar: TestClock.calendar)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, 2)
    }

    func testMarkCompletedIsTrueOnlyTheFirstTime() async throws {
        let store = makeStore()
        let templates = try await store.templatesForDay("2026-01-15", catalog: DailyChallengeCatalog.all, calendar: TestClock.calendar)
        let id = try XCTUnwrap(templates.first?.id)

        let first = try await store.markCompleted(templateId: id, day: "2026-01-15")
        let second = try await store.markCompleted(templateId: id, day: "2026-01-15")
        XCTAssertTrue(first)
        XCTAssertFalse(second, "the same (day, template) pair must never award XP twice")

        let completed = await store.completedTemplateIds(day: "2026-01-15")
        XCTAssertEqual(completed, [id])
    }

    func testMarkCompletedIgnoresATemplateNotAssignedThatDay() async throws {
        let store = makeStore()
        _ = try await store.templatesForDay("2026-01-15", catalog: DailyChallengeCatalog.all, calendar: TestClock.calendar)
        let result = try await store.markCompleted(templateId: "not-assigned-today", day: "2026-01-15")
        XCTAssertFalse(result)
    }
}
