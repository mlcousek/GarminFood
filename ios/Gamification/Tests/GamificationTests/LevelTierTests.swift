import XCTest
@testable import Gamification

final class LevelTierTests: XCTestCase {
    func testEveryLevelFromOneTo200MapsToExactlyOneTier() {
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
        XCTAssertEqual(LevelTiers.tier(forLevel: 200).title, "Legend")
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
        XCTAssertEqual(LevelTiers.tier(forLevel: 200).rarity, .legendary)
    }

    func testEveryTierHasANonEmptyBadgeSymbol() {
        for tier in LevelTiers.all {
            XCTAssertFalse(tier.badgeSymbol.isEmpty)
        }
    }
}
