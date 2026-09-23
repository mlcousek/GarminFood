// MealUsualRankerTests.swift
//
// Pure ranking tests for the "Usual for <meal>" shelf (improve-log-food-
// shelves task 1.2, food-catalog spec's "A per-meal shelf surfaces the foods
// usually eaten at that meal" requirement). No file I/O, no network --
// `MealUsualRanker.rank` is a pure function, same as `QuickPick.rank`.

import XCTest
@testable import FoodLogCore
import GarminKit

final class MealUsualRankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(
        _ foodId: String,
        _ mealType: MealType?,
        daysAgo: Double = 0,
        servingId: String = "s1",
        units: Double = 1
    ) -> UsageEvent {
        UsageEvent(
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: units,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            mealType: mealType
        )
    }

    func testEmptyHistoryProducesAnEmptyShelf() {
        XCTAssertEqual(MealUsualRanker.rank(events: [], mealType: .breakfast, now: now), [])
    }

    // MARK: - Minimum history

    func testShelfStaysHiddenBelowThreeEventsForThatMeal() {
        let events = [event("oatmeal", .breakfast), event("oatmeal", .breakfast, daysAgo: 1)]

        XCTAssertEqual(MealUsualRanker.rank(events: events, mealType: .breakfast, now: now), [])
    }

    func testShelfAppearsAtExactlyThreeEventsForThatMeal() {
        let events = [
            event("oatmeal", .breakfast),
            event("oatmeal", .breakfast, daysAgo: 1),
            event("banana", .breakfast, daysAgo: 2),
        ]

        let ranked = MealUsualRanker.rank(events: events, mealType: .breakfast, now: now)

        XCTAssertEqual(ranked.map(\.foodId), ["oatmeal", "banana"])
    }

    func testOtherMealsEventsDoNotCountTowardTheMinimum() {
        let events = [
            event("oatmeal", .breakfast),
            event("oatmeal", .breakfast, daysAgo: 1),
            event("steak", .dinner),
            event("steak", .dinner, daysAgo: 1),
            event("steak", .dinner, daysAgo: 2),
        ]

        XCTAssertEqual(MealUsualRanker.rank(events: events, mealType: .breakfast, now: now), [])
    }

    func testEventsWithoutAMealTypeNeverCount() {
        // Pre-upgrade events decode with a nil meal type; they must not be
        // guessed onto any meal's shelf, nor count toward its minimum.
        let events = (0..<5).map { event("oatmeal", nil, daysAgo: Double($0)) }
            + [event("toast", .breakfast), event("toast", .breakfast, daysAgo: 1)]

        XCTAssertEqual(MealUsualRanker.rank(events: events, mealType: .breakfast, now: now), [])
    }

    // MARK: - Spec scenarios: breakfast vs dinner

    func testBreakfastStapleAppearsAtBreakfastButNotAtDinner() {
        let oatmealAtBreakfast = (0..<8).map { event("oatmeal", .breakfast, daysAgo: Double($0)) }
        let dinners = [
            event("steak", .dinner),
            event("salad", .dinner, daysAgo: 1),
            event("steak", .dinner, daysAgo: 2),
        ]
        let events = oatmealAtBreakfast + dinners

        let breakfast = MealUsualRanker.rank(events: events, mealType: .breakfast, now: now)
        let dinner = MealUsualRanker.rank(events: events, mealType: .dinner, now: now)

        XCTAssertEqual(breakfast.first?.foodId, "oatmeal")
        XCTAssertEqual(breakfast.first?.useCount, 8)
        XCTAssertFalse(dinner.contains { $0.foodId == "oatmeal" }, "oatmeal was never logged at dinner")
        XCTAssertEqual(dinner.map(\.foodId), ["steak", "salad"])
    }

    // MARK: - Ranking

    func testFrequencyOutranksASingleRecentUse() {
        let events = [
            event("usual", .lunch, daysAgo: 1),
            event("usual", .lunch, daysAgo: 3),
            event("usual", .lunch, daysAgo: 5),
            event("once", .lunch),
        ]

        let ranked = MealUsualRanker.rank(events: events, mealType: .lunch, now: now)

        XCTAssertEqual(ranked.map(\.foodId), ["usual", "once"])
    }

    func testOldHabitsDecayBelowCurrentOnes() {
        // Same count each; the old one is ~4 half-lives old.
        let events = [
            event("old-habit", .lunch, daysAgo: 60),
            event("old-habit", .lunch, daysAgo: 61),
            event("new-habit", .lunch, daysAgo: 1),
            event("new-habit", .lunch, daysAgo: 2),
        ]

        let ranked = MealUsualRanker.rank(events: events, mealType: .lunch, now: now)

        XCTAssertEqual(ranked.map(\.foodId), ["new-habit", "old-habit"])
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score * 10)
    }

    func testGroupsServingsOfOneFoodAndKeepsTheMostRecentServingAndQuantity() {
        let events = [
            event("yogurt", .snacks, daysAgo: 3, servingId: "100g", units: 1),
            event("yogurt", .snacks, daysAgo: 2, servingId: "cup", units: 1),
            event("yogurt", .snacks, daysAgo: 0, servingId: "100g", units: 1.5),
        ]

        let ranked = MealUsualRanker.rank(events: events, mealType: .snacks, now: now)

        XCTAssertEqual(ranked.count, 1, "one card per food, not per serving")
        XCTAssertEqual(ranked.first?.servingId, "100g")
        XCTAssertEqual(ranked.first?.numberOfUnits, 1.5)
        XCTAssertEqual(ranked.first?.useCount, 3)
    }

    func testLimitCapsTheShelf() {
        let events = (0..<20).map { event("food-\($0)", .dinner) }

        XCTAssertEqual(MealUsualRanker.rank(events: events, mealType: .dinner, now: now, limit: 10).count, 10)
        XCTAssertEqual(MealUsualRanker.rank(events: events, mealType: .dinner, now: now).count, 10, "top 10 by default")
    }

    func testTiedScoresBreakDeterministicallyByFoodId() {
        let events = [event("c", .lunch), event("a", .lunch), event("b", .lunch)]

        let ranked = MealUsualRanker.rank(events: events, mealType: .lunch, now: now)

        XCTAssertEqual(ranked.map(\.foodId), ["a", "b", "c"])
    }
}
