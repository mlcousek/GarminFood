import XCTest
@testable import Gamification

final class LevelTierTests: XCTestCase {
    func testEveryLevelMapsToExactlyOneTier() {
        for level in 1...LevelCurve.maxLevel {
            let matches = LevelTiers.all.filter { $0.levelRange.contains(level) }
            XCTAssertEqual(matches.count, 1, "level \(level) should map to exactly one tier, found \(matches.count)")
        }
    }

    func testTiersAreContiguousAndCoverTheFullRange() {
        let sorted = LevelTiers.all.sorted { $0.levelRange.lowerBound < $1.levelRange.lowerBound }
        XCTAssertEqual(sorted.first?.levelRange.lowerBound, 1)
        XCTAssertEqual(sorted.last?.levelRange.upperBound, LevelCurve.maxLevel)
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual(a.levelRange.upperBound + 1, b.levelRange.lowerBound, "gap or overlap between \(a.title) and \(b.title)")
        }
    }

    func testTierLookupReturnsTheCorrectBand() {
        XCTAssertEqual(LevelTiers.tier(forLevel: 1).title, "Newcomer")
        XCTAssertEqual(LevelTiers.tier(forLevel: 150).title, "Legend")
        XCTAssertEqual(LevelTiers.tier(forLevel: 149).title, "Ascendant")
        // Past the last level: the last tier (never reached; level is clamped).
        XCTAssertEqual(LevelTiers.tier(forLevel: 200).title, "Legend")
    }

    /// add-training-gamification-and-150-levels D5: the tiers up to level
    /// 90 keep their names and ranges, so the move to 150 levels never
    /// moves anyone's title down.
    func testTiersUpToLevel90AreUnchanged() {
        let expected: [(String, ClosedRange<Int>)] = [
            ("Newcomer", 1...5), ("Rookie", 6...10), ("Apprentice", 11...15), ("Regular", 16...20),
            ("Steady Hand", 21...27), ("Dedicated", 28...35), ("Committed", 36...44), ("Seasoned", 45...54),
            ("Veteran", 55...65), ("Expert", 66...77), ("Elite", 78...90),
        ]
        let tiers = LevelTiers.all.sorted { $0.levelRange.lowerBound < $1.levelRange.lowerBound }
        for (index, row) in expected.enumerated() {
            XCTAssertEqual(tiers[index].title, row.0)
            XCTAssertEqual(tiers[index].levelRange, row.1, row.0)
        }
        XCTAssertEqual(tiers.count, 20)
        XCTAssertEqual(tiers.last?.levelRange, 150...150)
    }

    func testEveryTierHasNonEmptyTitleAndFlavor() {
        for tier in LevelTiers.all {
            XCTAssertFalse(tier.title.isEmpty)
            XCTAssertFalse(tier.flavor.isEmpty)
        }
    }

    // MARK: - Rarity / badge art (BadgeMedallion display)

    func testTierRarityMatchesLevelAtLeastDerivedAtItsLowerBound() {
        for tier in LevelTiers.all {
            XCTAssertEqual(tier.rarity, AchievementRarity.derive(from: .levelAtLeast(level: tier.levelRange.lowerBound)))
        }
    }

    func testTierRarityNeverDecreasesAsTiersAscend() {
        let sorted = LevelTiers.all.sorted { $0.levelRange.lowerBound < $1.levelRange.lowerBound }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThanOrEqual(a.rarity, b.rarity, "\(b.title) should never be a LOWER rarity than the tier below it, \(a.title)")
        }
    }

    func testFirstAndLastTierSpanTheRarityRange() {
        XCTAssertEqual(LevelTiers.tier(forLevel: 1).rarity, .common)
        XCTAssertEqual(LevelTiers.tier(forLevel: 150).rarity, .legendary)
    }

    func testEveryTierHasANonEmptyBadgeSymbol() {
        for tier in LevelTiers.all {
            XCTAssertFalse(tier.badgeSymbol.isEmpty)
        }
    }
}
