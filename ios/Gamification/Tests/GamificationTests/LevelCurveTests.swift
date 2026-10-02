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

    // expand-gamification-depth design.md D1: the curve must support a real
    // multi-year arc, not become practically unreachable within the first
    // year. These pin down the reachability numbers the retuned
    // `growthFactor` was chosen against, at a realistic sustained ~75
    // XP/day (flat per-log plus occasional streak/goal bonuses).
    private static let realisticDailyXP = 75

    func testOneYearOfRealisticUseReachesWellPastTheEarlyLevels() {
        let oneYearXP = Self.realisticDailyXP * 365
        let progress = LevelCurve.level(forTotalXP: oneYearXP)
        XCTAssertGreaterThanOrEqual(progress.level, 25, "a year of steady use should clear the early-game levels comfortably")
    }

    func testThreeYearsOfRealisticUseHasNotHitTheCeiling() {
        let threeYearXP = Self.realisticDailyXP * 365 * 3
        let progress = LevelCurve.level(forTotalXP: threeYearXP)
        XCTAssertGreaterThan(progress.level, 50, "three years of steady use should still be producing real level-ups")
        XCTAssertLessThan(progress.level, LevelCurve.maxLevel, "the curve should still have runway left after three years, not a maxed-out wall")
    }

    // MARK: - add-training-gamification-and-150-levels D1: the 150-level curve

    /// The documented formula, XP(n -> n+1) = round(100 x 1.03087^(n-1)),
    /// as a table (design D1; printed by tools/level-curve-model.mjs).
    func testThresholdTable() {
        XCTAssertEqual(LevelCurve.growthFactor, 1.03087)
        XCTAssertEqual(LevelCurve.maxLevel, 150)
        let table: [(level: Int, threshold: Int)] = [
            (1, 0), (2, 100), (5, 419), (10, 1_020), (25, 3_481), (50, 11_131),
            (75, 27_491), (100, 62_474), (125, 137_285), (150, 297_264),
        ]
        for row in table {
            XCTAssertEqual(LevelCurve.threshold(forLevel: row.level), row.threshold, "level \(row.level)")
        }
        XCTAssertEqual(LevelCurve.xpRequired(afterLevel: 1), 100)
        XCTAssertEqual(LevelCurve.xpRequired(afterLevel: 2), 103)
        XCTAssertEqual(LevelCurve.xpRequired(afterLevel: 149), 8_999)
    }

    func testLevel150IsTheLastLevel() {
        let top = LevelCurve.threshold(forLevel: 150)
        XCTAssertEqual(LevelCurve.level(forTotalXP: top - 1).level, 149)
        let atTop = LevelCurve.level(forTotalXP: top)
        XCTAssertEqual(atTop.level, 150)
        XCTAssertEqual(atTop.xpNeededForNextLevel, 0, "no level 151")
        XCTAssertEqual(atTop.fractionToNextLevel, 1)
        XCTAssertEqual(LevelCurve.level(forTotalXP: top * 10).level, 150)
        XCTAssertEqual(LevelCurve.threshold(forLevel: 151), top, "thresholds stop at the last level")
        // A stored peak above 150 (an impossible old value) is clamped.
        XCTAssertEqual(LevelCurve.level(forTotalXP: 0, peakLevel: 200).level, 150)
    }

    /// Design D4: the factor is below every earlier one and the base is the
    /// same, so every band and every threshold is at or below the same
    /// level's on each curve that shipped before.
    func testEveryThresholdIsAtOrBelowEveryEarlierCurve() {
        XCTAssertEqual(LevelCurve.pastGrowthFactors, [1.045, 1.0505, 1.05358])
        for past in LevelCurve.pastGrowthFactors {
            XCTAssertLessThan(LevelCurve.growthFactor, past)
            var oldThreshold = 0
            for level in 1..<LevelCurve.maxLevel {
                let oldBand = LevelCurve.xpRequired(afterLevel: level, growthFactor: past)
                XCTAssertLessThanOrEqual(LevelCurve.xpRequired(afterLevel: level), oldBand, "band after level \(level) vs \(past)")
                oldThreshold += oldBand
                XCTAssertLessThanOrEqual(LevelCurve.threshold(forLevel: level + 1), oldThreshold, "level \(level + 1) vs \(past)")
            }
        }
    }

    /// The same promise from the player's side: no XP total maps to a lower
    /// level than it did on any earlier curve.
    func testNoXPTotalMapsToALowerLevelThanBefore() {
        var total = 0
        while total <= 600_000 {
            let now = LevelCurve.level(forTotalXP: total).level
            for past in LevelCurve.pastGrowthFactors {
                let before = LevelCurve.level(forTotalXP: total, growthFactor: past).level
                XCTAssertGreaterThanOrEqual(now, before, "\(total) XP: level \(before) on \(past), \(now) now")
            }
            total += 137
        }
        // The ledgers named in the design.
        XCTAssertEqual(LevelCurve.level(forTotalXP: 3_000).level, 22)
        XCTAssertEqual(LevelCurve.level(forTotalXP: 4_210).level, 28)
        XCTAssertEqual(LevelCurve.level(forTotalXP: 12_000).level, 51)
    }
}
