// AchievementRarityTests.swift
//
// Covers `AchievementRarity.derive(from:)`'s per-condition-family bucketing
// (see that function's header for why it's derived rather than a stored
// field), `AchievementDefinition.rarity`'s wiring, and a whole-catalog
// sanity check that the five grades actually spread across the real
// catalog rather than clustering at one end.

import XCTest
@testable import Gamification

final class AchievementRarityTests: XCTestCase {

    // MARK: - Ordering

    func testRarityOrdersFromCommonToLegendary() {
        XCTAssertLessThan(AchievementRarity.common, .uncommon)
        XCTAssertLessThan(AchievementRarity.uncommon, .rare)
        XCTAssertLessThan(AchievementRarity.rare, .epic)
        XCTAssertLessThan(AchievementRarity.epic, .legendary)
    }

    func testDisplayNamesAreNonEmptyAndDistinct() {
        let names = AchievementRarity.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    // MARK: - Streak family (worked example)

    func testStreakRarityEscalatesWithDays() {
        XCTAssertEqual(AchievementRarity.derive(from: .streakAtLeast(days: 7)), .common)
        XCTAssertEqual(AchievementRarity.derive(from: .streakAtLeast(days: 14)), .uncommon)
        XCTAssertEqual(AchievementRarity.derive(from: .streakAtLeast(days: 60)), .rare)
        XCTAssertEqual(AchievementRarity.derive(from: .streakAtLeast(days: 180)), .epic)
        XCTAssertEqual(AchievementRarity.derive(from: .streakAtLeast(days: 1000)), .legendary)
    }

    // MARK: - Level family (worked example, and LevelTier's reuse of it)

    func testLevelRarityEscalatesWithLevel() {
        XCTAssertEqual(AchievementRarity.derive(from: .levelAtLeast(level: 5)), .common)
        XCTAssertEqual(AchievementRarity.derive(from: .levelAtLeast(level: 10)), .uncommon)
        XCTAssertEqual(AchievementRarity.derive(from: .levelAtLeast(level: 75)), .epic)
        XCTAssertEqual(AchievementRarity.derive(from: .levelAtLeast(level: 200)), .legendary)
    }

    // MARK: - Special-cased conditions

    func testAllChallengesCompletedIsAlwaysLegendary() {
        XCTAssertEqual(AchievementRarity.derive(from: .allChallengesCompleted), .legendary)
    }

    func testCalendarOneOffsAreRare() {
        XCTAssertEqual(AchievementRarity.derive(from: .perfectCalendarMonth), .rare)
        XCTAssertEqual(AchievementRarity.derive(from: .loggedOnLeapDay), .rare)
        XCTAssertEqual(AchievementRarity.derive(from: .loggedOnNewYearsDay), .rare)
        XCTAssertEqual(AchievementRarity.derive(from: .loggedAtMidnight), .rare)
    }

    func testMetaFractionEscalatesAndNeverDropsBelowRare() {
        XCTAssertEqual(AchievementRarity.derive(from: .unlockedFractionOfOthers(fraction: 0.25)), .rare)
        XCTAssertEqual(AchievementRarity.derive(from: .unlockedFractionOfOthers(fraction: 0.5)), .epic)
        XCTAssertEqual(AchievementRarity.derive(from: .unlockedFractionOfOthers(fraction: 0.75)), .epic)
        XCTAssertEqual(AchievementRarity.derive(from: .unlockedFractionOfOthers(fraction: 1.0)), .legendary)
    }

    // MARK: - AchievementDefinition wiring

    func testDefinitionRarityMatchesItsConditionsDerivedRarity() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .streak, badgeSymbol: "flame.fill", condition: .streakAtLeast(days: 365))
        XCTAssertEqual(def.rarity, AchievementRarity.derive(from: .streakAtLeast(days: 365)))
        XCTAssertEqual(def.rarity, .epic)
    }

    // MARK: - Whole-catalog sanity

    func testCatalogRarityCoversAllFiveGrades() {
        let rarities = Set(AchievementCatalog.all.map(\.rarity))
        XCTAssertEqual(rarities, Set(AchievementRarity.allCases), "expected every rarity grade to appear at least once across a 120+ item catalog")
    }

    func testCatalogIsNotDominatedByASingleRarity() {
        let counts = Dictionary(grouping: AchievementCatalog.all, by: \.rarity).mapValues(\.count)
        let total = AchievementCatalog.all.count
        for (rarity, count) in counts {
            XCTAssertLessThan(Double(count) / Double(total), 0.6, "\(rarity) makes up too much of the catalog to feel like a real rarity grade")
        }
    }
}
