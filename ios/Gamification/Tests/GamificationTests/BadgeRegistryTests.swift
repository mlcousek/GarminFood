// BadgeRegistryTests.swift
//
// add-gamification-signals 5.8: core + feature badges have no duplicate
// ids, the core catalog comes first unchanged, and core badges are never
// `.featureEvaluated`.

import XCTest
@testable import Gamification

final class BadgeRegistryTests: XCTestCase {
    private func features() -> [any GamificationFeature] {
        GamificationFeatureRegistry.makeAll(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("badges-\(UUID().uuidString)", isDirectory: true))
    }

    func testNoDuplicateIds() {
        XCTAssertEqual(BadgeRegistry.duplicateIds(features: features()), [])
        let all = BadgeRegistry.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testCoreCatalogFirstAndUnchanged() {
        let all = BadgeRegistry.badges(features: features())
        XCTAssertEqual(Array(all.prefix(AchievementCatalog.all.count)), AchievementCatalog.all)
        XCTAssertTrue(AchievementCatalog.all.allSatisfy(\.isCoreCatalogBadge))
    }

    func testMergeKeepsFirstDefinitionOfADuplicate() {
        let a = AchievementDefinition(id: "x", title: "first", subtitle: "", category: .variety,
                                      badgeSymbol: "star", condition: .featureEvaluated)
        let b = AchievementDefinition(id: "x", title: "second", subtitle: "", category: .variety,
                                      badgeSymbol: "star", condition: .featureEvaluated)
        let merged = BadgeRegistry.merge([], [a, b])
        XCTAssertEqual(merged.map(\.title), ["first"])
    }
}
