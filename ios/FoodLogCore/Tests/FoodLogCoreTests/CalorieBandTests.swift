// CalorieBandTests.swift
//
// The today-dashboard spec's stepped ring colours (fix-testing-feedback-
// quick-wins task 2.3): one assertion at each side of every step boundary,
// plus the spec's own two scenarios computed through `MacroProgress`, so
// the table in the spec and the code can't drift apart silently.

import XCTest
@testable import FoodLogCore

final class CalorieBandTests: XCTestCase {
    func testEveryStepBoundary() {
        XCTAssertEqual(CalorieBand.band(forPercent: 0), .low)
        XCTAssertEqual(CalorieBand.band(forPercent: 49.9), .low)
        XCTAssertEqual(CalorieBand.band(forPercent: 50), .building)
        XCTAssertEqual(CalorieBand.band(forPercent: 79.9), .building)
        XCTAssertEqual(CalorieBand.band(forPercent: 80), .approaching)
        XCTAssertEqual(CalorieBand.band(forPercent: 94.9), .approaching)
        XCTAssertEqual(CalorieBand.band(forPercent: 95), .onTarget)
        XCTAssertEqual(CalorieBand.band(forPercent: 100), .onTarget)
        XCTAssertEqual(CalorieBand.band(forPercent: 105), .onTarget)
        XCTAssertEqual(CalorieBand.band(forPercent: 105.1), .slightlyOver)
        XCTAssertEqual(CalorieBand.band(forPercent: 115), .slightlyOver)
        XCTAssertEqual(CalorieBand.band(forPercent: 115.1), .over)
        XCTAssertEqual(CalorieBand.band(forPercent: 300), .over)
    }

    // Spec scenario "Hitting the goal band": 2250 of 2300 is 97.8%.
    func testHittingTheGoalBandIsGreen() {
        XCTAssertEqual(MacroProgress(consumed: 2250, goal: 2300).calorieBand, .onTarget)
    }

    // Spec scenario "Well over the goal": 2700 of 2300 is 117%.
    func testWellOverTheGoalIsRed() {
        XCTAssertEqual(MacroProgress(consumed: 2700, goal: 2300).calorieBand, .over)
    }

    func testExactBoundariesThroughMacroProgressIgnoreFloatingPointNoise() {
        // 2645 / 2300 * 100 is 114.99999999999999 in binary floating point.
        XCTAssertEqual(MacroProgress(consumed: 2645, goal: 2300).calorieBand, .slightlyOver)
        XCTAssertEqual(MacroProgress(consumed: 2415, goal: 2300).calorieBand, .onTarget, "exactly 105%")
        XCTAssertEqual(MacroProgress(consumed: 2185, goal: 2300).calorieBand, .onTarget, "exactly 95%")
        XCTAssertEqual(MacroProgress(consumed: 1150, goal: 2300).calorieBand, .building, "exactly 50%")
    }

    func testNoUsableTargetHasNoBand() {
        XCTAssertNil(MacroProgress(consumed: 500, goal: nil).calorieBand)
        XCTAssertNil(MacroProgress(consumed: 500, goal: 0).calorieBand)
    }

    func testNothingEatenYetIsLow() {
        XCTAssertEqual(MacroProgress(consumed: 0, goal: 2300).calorieBand, .low)
    }

    // Gamification's "calorie goal met" is exactly the ring's green band
    // (owner, 2026-09-23), so the two can never disagree about a day.
    func testCalorieGoalMetIsExactlyTheGreenBand() {
        XCTAssertTrue(CalorieBand.isGoalMet(consumed: 2185, goal: 2300), "exactly 95%")
        XCTAssertTrue(CalorieBand.isGoalMet(consumed: 2300, goal: 2300))
        XCTAssertTrue(CalorieBand.isGoalMet(consumed: 2415, goal: 2300), "exactly 105%")
        XCTAssertFalse(CalorieBand.isGoalMet(consumed: 2150, goal: 2300), "93.5% was 'met' under the old +/-15% rule")
        XCTAssertFalse(CalorieBand.isGoalMet(consumed: 2600, goal: 2300), "113% was 'met' under the old +/-15% rule")
    }

    func testCalorieGoalIsNotMetWithoutDataOrAUsableGoal() {
        XCTAssertFalse(CalorieBand.isGoalMet(consumed: nil, goal: 2300))
        XCTAssertFalse(CalorieBand.isGoalMet(consumed: 2300, goal: nil))
        XCTAssertFalse(CalorieBand.isGoalMet(consumed: 0, goal: 0))
    }

    func testCalorieGoalMetAgreesWithTheRingForEveryPercent() {
        for consumed in stride(from: 0.0, through: 3000.0, by: 1.0) {
            let progress = MacroProgress(consumed: consumed, goal: 2300)
            XCTAssertEqual(CalorieBand.isGoalMet(consumed: consumed, goal: 2300), progress.calorieBand == .onTarget, "\(consumed) kcal")
        }
    }
}
