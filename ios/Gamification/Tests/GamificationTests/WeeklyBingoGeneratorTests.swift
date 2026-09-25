// WeeklyBingoGeneratorTests.swift
//
// add-weekly-bingo tasks 1.3 (design D2, D3, D9): the catalog's shape and
// the card generator -- determinism, composition, family uniqueness,
// requirement filtering, previous-week exclusion and its relaxation, hard
// tasks never sharing a line.

import XCTest
import FoodLogCore
@testable import Gamification

final class WeeklyBingoGeneratorTests: XCTestCase {
    private let all = BingoTaskCatalog.all

    private func tasks(_ ids: [String]) -> [BingoTask] {
        ids.compactMap { BingoTaskCatalog.task(id: $0) }
    }

    private func nonFree(_ card: [String]) -> [String] {
        card.filter { $0 != BingoTaskCatalog.freeId }
    }

    // MARK: - Catalog

    func testCatalogHas35TasksWithUniqueIds() {
        XCTAssertEqual(all.count, 35)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertFalse(all.contains { $0.id == BingoTaskCatalog.freeId })
        XCTAssertEqual(all.filter { $0.difficulty == .easy }.count, 10)
        XCTAssertEqual(all.filter { $0.difficulty == .medium }.count, 14)
        XCTAssertEqual(all.filter { $0.difficulty == .hard }.count, 11)
        for task in all {
            XCTAssertFalse(task.title.isEmpty, task.id)
            XCTAssertFalse(task.detail.isEmpty, task.id)
            XCTAssertFalse(task.family.isEmpty, task.id)
        }
    }

    func testRequirementsFollowTheRules() {
        XCTAssertTrue(BingoTaskCatalog.task(id: "m-water-goal")?.requirement.contains(.water) ?? false)
        XCTAssertTrue(BingoTaskCatalog.task(id: "h-water-4")?.requirement.contains(.water) ?? false)
        XCTAssertTrue(BingoTaskCatalog.task(id: "m-refuel")?.requirement.contains(.activities) ?? false)
        XCTAssertTrue(BingoTaskCatalog.task(id: "h-earned-it")?.requirement.contains(.activities) ?? false)
        XCTAssertTrue(BingoTaskCatalog.task(id: "h-fibre-30")?.requirement.contains(.macros) ?? false)
        XCTAssertTrue(BingoTaskCatalog.task(id: "h-sugar-low")?.requirement.contains(.macros) ?? false)
        XCTAssertEqual(BingoTaskCatalog.task(id: "e-fruit")?.requirement, [])
    }

    func testBadgesAreBingoFeatureBadges() {
        let badges = BingoTaskCatalog.badges
        XCTAssertEqual(badges.count, 7)
        XCTAssertEqual(Set(badges.map(\.id)).count, 7)
        for badge in badges {
            XCTAssertTrue(badge.id.hasPrefix("bingo."), badge.id)
            XCTAssertEqual(badge.featureId, WeeklyBingoFeature.id)
            XCTAssertEqual(badge.condition, .featureEvaluated)
        }
        XCTAssertTrue(BadgeRegistry.duplicateIds(features: GamificationFeatureRegistry.makeAll(
            directory: BingoFixtures.tempDirectory("bingo-badges"))).isEmpty)
    }

    // MARK: - Determinism

    func testSameWeekGivesSameCard() {
        let first = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: all, previousCard: nil)
        let second = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: all.reversed(), previousCard: nil)
        XCTAssertEqual(first, second, "input order must not matter")
    }

    func testDifferentWeeksGiveDifferentCards() {
        let w39 = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: all, previousCard: nil)
        let w40 = BingoCardGenerator.generate(week: WeekKey(yearForWeek: 2026, week: 40), eligible: all, previousCard: nil)
        XCTAssertNotEqual(w39, w40)
    }

    // MARK: - Composition

    func testCompositionAcrossAYearOfChainedCards() {
        var previous: [String]?
        for weekNumber in 1...52 {
            let week = WeekKey(yearForWeek: 2026, week: weekNumber)
            let card = BingoCardGenerator.generate(week: week, eligible: all, previousCard: previous)
            XCTAssertEqual(card.count, 9, week.rawValue)
            XCTAssertEqual(card[4], BingoTaskCatalog.freeId, week.rawValue)
            let picked = tasks(nonFree(card))
            XCTAssertEqual(picked.count, 8, week.rawValue)
            XCTAssertEqual(picked.filter { $0.difficulty == .easy }.count, 3, week.rawValue)
            XCTAssertEqual(picked.filter { $0.difficulty == .medium }.count, 3, week.rawValue)
            XCTAssertEqual(picked.filter { $0.difficulty == .hard }.count, 2, week.rawValue)
            XCTAssertEqual(Set(picked.map(\.family)).count, 8, "duplicate family in \(week.rawValue)")
            if let previous {
                XCTAssertTrue(Set(previous).intersection(nonFree(card)).isEmpty, "repeat from last week in \(week.rawValue)")
            }
            let hardPositions = Set(card.indices.filter { BingoTaskCatalog.task(id: card[$0])?.difficulty == .hard })
            for line in BingoLine.all {
                XCTAssertLessThan(line.indices.filter { hardPositions.contains($0) }.count, 2, "\(week.rawValue) \(line.id)")
            }
            previous = card
        }
    }

    func testRepairSeparatesHardTasksSharingALine() {
        let picks = tasks(["h-fish-2", "h-rainbow", "e-fruit", "e-tea", "e-egg", "m-legume", "m-cuisine", "m-whole-grain"])
        // Both hard tasks on the top row.
        let layout = [0, 1, 2, 3, 5, 6, 7, 8]
        XCTAssertTrue(BingoCardGenerator.hardTasksShareLine(picks: picks, layout: layout))
        let repaired = BingoCardGenerator.repairedLayout(layout, picks: picks)
        XCTAssertFalse(BingoCardGenerator.hardTasksShareLine(picks: picks, layout: repaired))
        XCTAssertEqual(Set(repaired), Set(layout))
    }

    // MARK: - Requirement filtering

    func testNoWaterOrActivityDataExcludesThoseTasks() {
        let recent = [BingoFixtures.day(0, [BingoFixtures.entry("apple", [.fruit], on: 0)])]
        let eligible = BingoCardGenerator.eligibleTasks(recentDays: recent)
        let ids = Set(eligible.map(\.id))
        for excluded in ["m-water-goal", "h-water-4", "m-refuel", "h-earned-it"] {
            XCTAssertFalse(ids.contains(excluded), excluded)
        }
        XCTAssertTrue(ids.contains("e-fruit"))
        for weekNumber in 30...45 {
            let card = BingoCardGenerator.generate(week: WeekKey(yearForWeek: 2026, week: weekNumber), eligible: eligible, previousCard: nil)
            XCTAssertTrue(Set(card).isDisjoint(with: ["m-water-goal", "h-water-4", "m-refuel", "h-earned-it"]))
        }
    }

    func testWaterDataMakesWaterTasksEligible() {
        let recent = [BingoFixtures.day(0, [BingoFixtures.entry("apple", on: 0)], waterML: 500, waterGoalML: 2000)]
        let ids = Set(BingoCardGenerator.eligibleTasks(recentDays: recent).map(\.id))
        XCTAssertTrue(ids.contains("m-water-goal"))
        XCTAssertTrue(ids.contains("h-water-4"))
    }

    func testNoDataAtAllStillLeavesEntryOnlyTasks() {
        let eligible = BingoCardGenerator.eligibleTasks(recentDays: [])
        XCTAssertTrue(eligible.allSatisfy { $0.requirement.isEmpty })
        let card = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: eligible, previousCard: nil)
        XCTAssertEqual(tasks(nonFree(card)).count, 8)
    }

    // MARK: - Previous-week exclusion and relaxation

    func testExclusionIsDroppedWhenTooFewTasksRemain() {
        let pool = ["e-fruit", "e-tea", "e-egg", "m-fish", "m-legume", "m-cuisine", "h-rainbow", "h-ten-foods"]
        let card = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: tasks(pool), previousCard: pool)
        XCTAssertEqual(Set(nonFree(card)), Set(pool))
    }

    func testFamilyRuleIsRelaxedLast() {
        // Only two families for eight squares.
        let pool = ["e-fruit", "m-three-fruits", "h-five-a-day", "e-tea", "m-no-soda",
                    "m-colours-4", "h-rainbow", "e-early-log", "m-early-dinner"]
        let card = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: tasks(pool), previousCard: nil)
        XCTAssertEqual(tasks(nonFree(card)).count, 8)
        XCTAssertEqual(card[4], BingoTaskCatalog.freeId)
    }

    func testShortDifficultyIsFilledFromEasierOne() {
        // No hard tasks at all: 8 squares still filled (medium, then easy).
        let pool = all.filter { $0.difficulty != .hard }
        let card = BingoCardGenerator.generate(week: BingoFixtures.week, eligible: pool, previousCard: nil)
        let picked = tasks(nonFree(card))
        XCTAssertEqual(picked.count, 8)
        XCTAssertEqual(picked.filter { $0.difficulty == .medium }.count, 5)
        XCTAssertEqual(Set(picked.map(\.family)).count, 8)
    }
}
