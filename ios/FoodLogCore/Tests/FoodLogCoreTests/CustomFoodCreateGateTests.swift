// CustomFoodCreateGateTests.swift
//
// fix-review-findings-2026-09 finding 2: after Garmin accepted a custom
// food (any 2xx), the create screen must never offer another create -- a
// retry would make a duplicate food in Garmin. Only a thrown error (no 2xx
// seen) may be retried. GarminKit's CustomFoodCreationTests pin the other
// half: a 201 with an unexpected body arrives here as
// `.createdDetailsPending`, not as an error.

import XCTest
@testable import FoodLogCore
import GarminKit

final class CustomFoodCreateGateTests: XCTestCase {
    private func result(_ json: String) throws -> FoodSearchResult {
        try JSONDecoder().decode(FoodSearchResult.self, from: Data(json.utf8))
    }

    func testCreatedDetailsPendingNeverOffersASecondCreate() {
        var gate = CustomFoodCreateGate()
        XCTAssertTrue(gate.begin())

        let food = gate.finish(.createdDetailsPending(statusCode: 201))

        XCTAssertNil(food)
        XCTAssertEqual(gate.phase, .createdDetailsPending)
        XCTAssertFalse(gate.canCreate, "Garmin already has the food: a retry would duplicate it")
        XCTAssertFalse(gate.begin())
    }

    func testA2xxWhoseFoodCantBeReadIsAlsoCreatedDetailsPending() throws {
        // Decodes as a FoodSearchResult but carries no loggable serving, so
        // `Food(searchResult:)` is nil -- still a create Garmin accepted.
        var gate = CustomFoodCreateGate()
        _ = gate.begin()

        let food = gate.finish(.created(try result(#"{"foodMetaData":{"foodId":"synthetic-1"},"nutritionContents":[]}"#)))

        XCTAssertNil(food)
        XCTAssertEqual(gate.phase, .createdDetailsPending)
        XCTAssertFalse(gate.canCreate)
    }

    func testAReadableCreateHandsBackTheFoodAndLocksTheButton() throws {
        var gate = CustomFoodCreateGate()
        _ = gate.begin()

        let food = gate.finish(.created(try result(
            #"{"foodMetaData":{"foodId":"synthetic-2","foodName":"Synthetic yoghurt"},"nutritionContents":[{"servingId":"sv-1","servingUnit":"g","numberOfUnits":100,"calories":60}]}"#
        )))

        XCTAssertEqual(food?.id, "synthetic-2")
        XCTAssertFalse(gate.canCreate)
    }

    func testAThrownCreateMayBeRetried() {
        var gate = CustomFoodCreateGate()
        _ = gate.begin()
        XCTAssertFalse(gate.canCreate, "no second create while one is in flight")

        gate.fail()

        XCTAssertEqual(gate.phase, .failed)
        XCTAssertTrue(gate.canCreate, "no 2xx was seen, so nothing was created")
        XCTAssertTrue(gate.begin())
    }
}
