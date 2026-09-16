import XCTest
@testable import FoodLogCore

final class TodaySummaryTests: XCTestCase {
    private func summary(consumed: Double, goal: Double?) -> TodaySummary {
        TodaySummary(consumedCalories: consumed, goalCalories: goal, protein: nil, carbs: nil, fat: nil, fetchedAt: .now)
    }

    // MARK: - goalState boundaries (under 90% / 90-110% / over 110%)

    func testGoalStateIsNoGoalWhenGoalIsNilOrZero() {
        XCTAssertEqual(summary(consumed: 1000, goal: nil).goalState, .noGoal)
        XCTAssertEqual(summary(consumed: 1000, goal: 0).goalState, .noGoal)
    }

    func testGoalStateIsUnderBelow90Percent() {
        XCTAssertEqual(summary(consumed: 899, goal: 1000).goalState, .under)
    }

    func testGoalStateIsOnTargetAtLowerBoundary() {
        XCTAssertEqual(summary(consumed: 900, goal: 1000).goalState, .onTarget)
    }

    func testGoalStateIsOnTargetAtExactGoal() {
        XCTAssertEqual(summary(consumed: 1000, goal: 1000).goalState, .onTarget)
    }

    func testGoalStateIsOnTargetAtUpperBoundary() {
        XCTAssertEqual(summary(consumed: 1100, goal: 1000).goalState, .onTarget)
    }

    func testGoalStateIsOverJustPastUpperBoundary() {
        XCTAssertEqual(summary(consumed: 1101, goal: 1000).goalState, .over)
    }

    // MARK: - goalFraction

    func testGoalFractionIsNilWithoutAGoal() {
        XCTAssertNil(summary(consumed: 500, goal: nil).goalFraction)
    }

    func testGoalFractionIsProportional() {
        XCTAssertEqual(summary(consumed: 500, goal: 2000).goalFraction, 0.25)
    }

    func testGoalFractionIsClampedAtOneWhenOverGoal() {
        XCTAssertEqual(summary(consumed: 3000, goal: 1000).goalFraction, 1.0)
    }

    func testGoalFractionIsClampedAtZeroForNegativeConsumption() {
        // Not a real scenario, but the clamp should hold regardless.
        XCTAssertEqual(summary(consumed: -10, goal: 1000).goalFraction, 0.0)
    }

    // MARK: - remainingCalories

    func testRemainingCaloriesIsNilWithoutAGoal() {
        XCTAssertNil(summary(consumed: 500, goal: nil).remainingCalories)
    }

    func testRemainingCaloriesIsGoalMinusConsumed() {
        XCTAssertEqual(summary(consumed: 800, goal: 2000).remainingCalories, 1200)
    }

    func testRemainingCaloriesIsNegativeWhenOverGoal() {
        XCTAssertEqual(summary(consumed: 2500, goal: 2000).remainingCalories, -500)
    }
}
