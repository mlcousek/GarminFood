// RecentRankerTests.swift
//
// Pure ordering tests for the "Recent" shelf (improve-log-food-shelves task
// 1.3, food-catalog spec's "A Recent shelf lists the last foods logged"
// requirement). No file I/O, no network -- `RecentRanker.rank` is a pure
// function over `[UsageEvent]`.

import XCTest
@testable import FoodLogCore

final class RecentRankerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(_ foodId: String, minutesAgo: Double, servingId: String = "s1", units: Double = 1) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: servingId, numberOfUnits: units, timestamp: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testEmptyHistoryProducesAnEmptyShelf() {
        XCTAssertEqual(RecentRanker.rank(events: []), [])
    }

    func testJustLoggedFoodIsFirst() {
        // Spec scenario: log a banana, reopen Log Food, banana leads Recent
        // -- even though oatmeal was logged far more often.
        let events = (1...6).map { event("oatmeal", minutesAgo: Double($0) * 60) } + [event("banana", minutesAgo: 0)]

        let recent = RecentRanker.rank(events: events)

        XCTAssertEqual(recent.map(\.foodId), ["banana", "oatmeal"])
    }

    func testOrdersNewestFirstRegardlessOfArrayOrder() {
        let events = [event("b", minutesAgo: 10), event("a", minutesAgo: 1), event("c", minutesAgo: 30)]

        XCTAssertEqual(RecentRanker.rank(events: events).map(\.foodId), ["a", "b", "c"])
    }

    func testIsDistinctByFoodAndKeepsTheLatestServingAndQuantity() {
        let events = [
            event("rohlik", minutesAgo: 90, servingId: "piece", units: 1),
            event("tvaroh", minutesAgo: 60),
            event("rohlik", minutesAgo: 5, servingId: "100g", units: 2),
        ]

        let recent = RecentRanker.rank(events: events)

        XCTAssertEqual(recent.map(\.foodId), ["rohlik", "tvaroh"])
        XCTAssertEqual(recent.first?.servingId, "100g")
        XCTAssertEqual(recent.first?.numberOfUnits, 2)
        XCTAssertEqual(recent.first?.loggedAt, now.addingTimeInterval(-5 * 60))
    }

    func testCapsAtTenDistinctFoodsByDefault() {
        let events = (0..<15).map { event("food-\($0)", minutesAgo: Double($0)) }

        let recent = RecentRanker.rank(events: events)

        XCTAssertEqual(recent.count, 10)
        XCTAssertEqual(recent.first?.foodId, "food-0")
        XCTAssertEqual(recent.last?.foodId, "food-9")
    }

    func testEqualTimestampsFavorTheLaterRecordedEvent() {
        // A meal preset logs every ingredient with one shared timestamp;
        // the store appends in order, so later in the array = later.
        let events = [event("first", minutesAgo: 0), event("second", minutesAgo: 0)]

        XCTAssertEqual(RecentRanker.rank(events: events).map(\.foodId), ["second", "first"])
    }

    func testNonPositiveLimitIsEmpty() {
        XCTAssertEqual(RecentRanker.rank(events: [event("a", minutesAgo: 0)], limit: 0), [])
    }
}
