import XCTest
@testable import Gamification

final class LevelCurveTests: XCTestCase {
    func testZeroXPIsLevelOneWithFullBandRemaining() {
        let progress = LevelCurve.level(forTotalXP: 0)
        XCTAssertEqual(progress.level, 1)
        XCTAssertEqual(progress.xpIntoCurrentLevel, 0)
        XCTAssertEqual(progress.xpNeededForNextLevel, LevelCurve.xpRequired(afterLevel: 1))
    }

    func testXPJustBelowTheFirstThresholdIsStillLevelOne() {
        let threshold = LevelCurve.xpRequired(afterLevel: 1)
        let progress = LevelCurve.level(forTotalXP: threshold - 1)
        XCTAssertEqual(progress.level, 1)
    }

    func testXPAtExactlyTheFirstThresholdIsLevelTwo() {
        let threshold = LevelCurve.xpRequired(afterLevel: 1)
        let progress = LevelCurve.level(forTotalXP: threshold)
        XCTAssertEqual(progress.level, 2)
        XCTAssertEqual(progress.xpIntoCurrentLevel, 0)
    }

    func testLevelIsDeterministicForTheSameXP() {
        let a = LevelCurve.level(forTotalXP: 4321)
        let b = LevelCurve.level(forTotalXP: 4321)
        XCTAssertEqual(a, b)
    }

    func testThresholdsGrowGeometrically() {
        // Each level's required XP is `growthFactor` times the previous
        // one's (design.md D3: "thresholds growing roughly geometrically").
        let level5 = Double(LevelCurve.xpRequired(afterLevel: 5))
        let level6 = Double(LevelCurve.xpRequired(afterLevel: 6))
        XCTAssertEqual(level6 / level5, LevelCurve.growthFactor, accuracy: 0.05)
    }

    func testCumulativeThresholdsAreStrictlyIncreasing() {
        var previous = LevelCurve.level(forTotalXP: 0).xpNeededForNextLevel
        var totalXP = previous
        for _ in 0..<10 {
            let progress = LevelCurve.level(forTotalXP: totalXP)
            XCTAssertGreaterThan(progress.xpNeededForNextLevel, 0)
            XCTAssertGreaterThanOrEqual(progress.xpNeededForNextLevel, previous, "level bands must not shrink")
            previous = progress.xpNeededForNextLevel
            totalXP += progress.xpNeededForNextLevel
        }
    }

    func testFractionToNextLevelIsHalfwayThroughABand() {
        let bandWidth = LevelCurve.xpRequired(afterLevel: 1)
        let progress = LevelCurve.level(forTotalXP: bandWidth / 2)
        XCTAssertEqual(progress.fractionToNextLevel, 0.5, accuracy: 0.02)
    }
}
