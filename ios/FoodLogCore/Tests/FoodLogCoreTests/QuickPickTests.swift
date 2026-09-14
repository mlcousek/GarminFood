// QuickPickTests.swift
//
// Pure ranking logic tests (task 13.2, food-catalog spec's "A quick-pick
// shelf is ranked from local usage, not from a fresh search" requirement).
// No file I/O, no network -- `QuickPick.rank` is a pure function.

import XCTest
@testable import FoodLogCore

final class QuickPickTests: XCTestCase {
    func testEmptyHistoryProducesEmptyQuickPick() {
        XCTAssertEqual(QuickPick.rank(events: []), [])
    }

    func testFrequentlyLoggedFoodRanksAboveASingleOldEvent() {
        let now = Date()
        let frequentEvents = (0..<5).map { offset in
            UsageEvent(foodId: "frequent", servingId: "s1", numberOfUnits: 1, timestamp: now.addingTimeInterval(-Double(offset) * 86_400))
        }
        let rareEvent = UsageEvent(foodId: "rare", servingId: "s1", numberOfUnits: 1, timestamp: now.addingTimeInterval(-30 * 86_400))

        let ranked = QuickPick.rank(events: frequentEvents + [rareEvent], now: now)

        XCTAssertEqual(ranked.first?.foodId, "frequent")
        XCTAssertEqual(ranked.first?.useCount, 5)
    }

    func testRecencyAloneCanOutrankASingleOlderUse() {
        let now = Date()
        let recentOnce = UsageEvent(foodId: "recent", servingId: "s1", numberOfUnits: 1, timestamp: now)
        let oldOnce = UsageEvent(foodId: "old", servingId: "s1", numberOfUnits: 1, timestamp: now.addingTimeInterval(-60 * 86_400))

        let ranked = QuickPick.rank(events: [oldOnce, recentOnce], now: now, halfLifeDays: 7)

        XCTAssertEqual(ranked.first?.foodId, "recent")
    }

    func testMostRecentQuantityIsUsedAsTheEntrysDefaultQuantity() {
        let now = Date()
        let events = [
            UsageEvent(foodId: "f1", servingId: "s1", numberOfUnits: 1, timestamp: now.addingTimeInterval(-2 * 86_400)),
            UsageEvent(foodId: "f1", servingId: "s1", numberOfUnits: 2.5, timestamp: now),
        ]

        let ranked = QuickPick.rank(events: events, now: now)

        XCTAssertEqual(ranked.first?.numberOfUnits, 2.5)
        XCTAssertEqual(ranked.first?.useCount, 2)
    }

    func testDifferentServingsOfTheSameFoodAreRankedSeparately() {
        let now = Date()
        let events = [
            UsageEvent(foodId: "f1", servingId: "100g", numberOfUnits: 1, timestamp: now),
            UsageEvent(foodId: "f1", servingId: "1-medium", numberOfUnits: 1, timestamp: now),
        ]

        let ranked = QuickPick.rank(events: events, now: now)

        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(Set(ranked.map(\.servingId)), ["100g", "1-medium"])
    }

    func testLimitCapsTheReturnedCount() {
        let now = Date()
        let events = (0..<20).map { index in
            UsageEvent(foodId: "food-\(index)", servingId: "s1", numberOfUnits: 1, timestamp: now)
        }

        let ranked = QuickPick.rank(events: events, now: now, limit: 3)

        XCTAssertEqual(ranked.count, 3)
    }

    func testTiedScoresBreakDeterministicallyByIdentifiers() {
        let now = Date()
        let events = [
            UsageEvent(foodId: "b", servingId: "s1", numberOfUnits: 1, timestamp: now),
            UsageEvent(foodId: "a", servingId: "s1", numberOfUnits: 1, timestamp: now),
        ]

        let ranked1 = QuickPick.rank(events: events, now: now)
        let ranked2 = QuickPick.rank(events: events, now: now)

        XCTAssertEqual(ranked1.map(\.foodId), ["a", "b"])
        XCTAssertEqual(ranked1.map(\.foodId), ranked2.map(\.foodId), "ranking of tied scores must be deterministic across calls")
    }
}
