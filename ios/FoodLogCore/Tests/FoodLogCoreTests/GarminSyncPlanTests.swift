// GarminSyncPlanTests.swift
//
// add-standalone-mode 5.3 (data-mode spec, "Standalone mode makes no Garmin
// calls"): Garmin mode keeps every Garmin step exactly as before, and
// standalone mode plans none -- including background delivery -- even when
// reached through the testing toggle.

import XCTest
@testable import FoodLogCore

final class GarminSyncPlanTests: XCTestCase {
    func testGarminModeKeepsEveryStep() {
        let plan = GarminSyncPlan.for(.garminConnected)
        for step in GarminSyncPlan.Step.allCases {
            XCTAssertTrue(plan.allows(step), "\(step) must still run on the owner's phone")
        }
    }

    func testStandaloneModePlansNoGarminWorkAtAll() {
        let plan = GarminSyncPlan.for(.standalone)
        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertFalse(plan.allows(.backgroundDelivery), "BackgroundRefresh is never scheduled")
        XCTAssertFalse(plan.allows(.authRefresh))
        XCTAssertFalse(plan.allows(.drainAndReconcile))
    }

    func testAnUnclassifiedInstallBehavesAsGarmin() {
        let mode = DataMode.effective(stored: nil, forceStandalone: false)
        XCTAssertEqual(GarminSyncPlan.for(mode), GarminSyncPlan.for(.garminConnected))
    }

    func testTheTestingToggleMeansNoGarminWork() {
        let mode = DataMode.effective(stored: .garminConnected, forceStandalone: true)
        XCTAssertTrue(GarminSyncPlan.for(mode).steps.isEmpty)
    }
}
