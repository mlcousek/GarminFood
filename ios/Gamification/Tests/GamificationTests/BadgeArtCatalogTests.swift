// BadgeArtCatalogTests.swift
//
// redesign-badge-art 2.2: every badge the app can show (the core catalog,
// every feature's badges, the level tiers and the secret placeholder)
// resolves to a frame family and a motif, the id namespaces win over the
// category, and an unknown symbol falls back (nil) instead of guessing.
// That the named motifs and frames exist as SVG files is checked by
// tools/docs/check-badge-art.mjs, which can see the files.

import XCTest
@testable import Gamification

final class BadgeArtCatalogTests: XCTestCase {
    func testEveryBadgeHasAMotif() {
        let missing = BadgeRegistry.all
            .filter { BadgeArtCatalog.motif(forSymbol: $0.badgeSymbol) == nil }
            .map { "\($0.id): \($0.badgeSymbol)" }
        XCTAssertEqual(missing, [], "badges whose symbol has no motif")
    }

    func testEveryLevelTierHasAMotif() {
        let missing = LevelTiers.all.map(\.badgeSymbol).filter { BadgeArtCatalog.motif(forSymbol: $0) == nil }
        XCTAssertEqual(missing, [])
    }

    func testTheSecretPlaceholderHasAMotif() {
        XCTAssertEqual(BadgeArtCatalog.motif(forSymbol: "questionmark"), "question")
    }

    func testAnUnknownSymbolFallsBack() {
        XCTAssertNil(BadgeArtCatalog.motif(forSymbol: "no.such.symbol"))
    }

    func testIDNamespaceWinsOverCategory() {
        XCTAssertEqual(BadgeArtCatalog.family(id: "bingo.first-line", category: .challenges), .bingo)
        XCTAssertEqual(BadgeArtCatalog.family(id: "freeze.saved", category: .streak), .boss)
        XCTAssertEqual(BadgeArtCatalog.family(id: "body.fast-3", category: .streak), .sportBody)
        XCTAssertEqual(BadgeArtCatalog.family(id: "secret.keeper", category: .meta), .secrets)
        XCTAssertEqual(BadgeArtCatalog.family(id: "training.checkin-7", category: .streak), .sportBody)
    }

    func testCoreBadgesFollowTheirCategory() {
        XCTAssertEqual(BadgeArtCatalog.family(id: "achv-streak-1", category: .streak), .streak)
        XCTAssertEqual(BadgeArtCatalog.family(id: "achv-level-5", category: .level), .levels)
        for category in AchievementCategory.allCases {
            XCTAssertNotNil(BadgeArtCatalog.familyByCategory[category], "\(category) has no family")
        }
    }

    func testEveryFamilyIsUsed() {
        let used = Set(BadgeRegistry.all.map { BadgeArtCatalog.family(for: $0) })
        XCTAssertEqual(used, Set(BadgeFamily.allCases))
    }

    func testAssetNames() {
        XCTAssertEqual(BadgeArtCatalog.frameAssetName(family: .sportBody, rarity: .legendary), "badge-frame-sportBody-legendary")
        XCTAssertEqual(BadgeArtCatalog.motifAssetName("flame"), "badge-motif-flame")
    }
}
