// BadgeModelTests.swift
//
// add-gamification-signals 5.7: the Optional badge-model extensions
// (visibility, edition, rarity override, feature id), `.featureEvaluated`
// never met by the engine, and the completionist denominator unchanged by
// feature badges (spec: "Completionist denominator unchanged").

import XCTest
@testable import Gamification

final class BadgeModelTests: XCTestCase {
    private func context(longestStreak: Int) -> AchievementContext {
        AchievementContext(
            level: 1,
            longestStreak: longestStreak,
            totalLogsEver: 0,
            distinctFoodsInRetainedHistory: 0,
            challengeCompletionCount: 0,
            distinctCompletedChallengeTemplateCount: 0,
            totalChallengeCatalogCount: 0,
            dailyChallengeCompletionCount: 0,
            goalHitDaysEver: [:],
            maxSingleDayCalories: 0,
            totalCaloriesEver: 0,
            hasPerfectCalendarMonth: false,
            hasLoggedOnLeapDay: false,
            hasLoggedOnNewYearsDay: false,
            hasLoggedAtMidnight: false,
            yearsSinceFirstLog: 0
        )
    }

    private func featureBadge(_ id: String) -> AchievementDefinition {
        AchievementDefinition(
            id: id, title: id, subtitle: id, category: .variety, badgeSymbol: "star.fill",
            condition: .featureEvaluated, featureId: "bingo"
        )
    }

    func testDefaultsKeepExistingDefinitionsUnchanged() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .streak,
                                        badgeSymbol: "flame.fill", condition: .streakAtLeast(days: 60))
        XCTAssertNil(def.visibility)
        XCTAssertNil(def.edition)
        XCTAssertNil(def.featureId)
        XCTAssertFalse(def.isSecret)
        XCTAssertNil(def.limitedEditionEventId)
        XCTAssertTrue(def.isCoreCatalogBadge)
        XCTAssertEqual(def.rarity, AchievementRarity.derive(from: .streakAtLeast(days: 60)))
    }

    func testSecretLimitedAndRarityOverride() {
        let def = AchievementDefinition(
            id: "event.easter.egg", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "gift.fill",
            condition: .featureEvaluated, visibility: .secret, edition: .limited(eventId: "easter"),
            rarityOverride: .epic, featureId: "seasonal"
        )
        XCTAssertTrue(def.isSecret)
        XCTAssertEqual(def.limitedEditionEventId, "easter")
        XCTAssertEqual(def.rarity, .epic)
        XCTAssertFalse(def.isCoreCatalogBadge)
        XCTAssertEqual(featureBadge("x").rarity, .uncommon) // fallback without override
    }

    func testFeatureEvaluatedIsNeverMetByTheEngine() {
        let unlocked = AchievementEngine.evaluate(context: context(longestStreak: 1000),
                                                  catalog: [featureBadge("bingo.first")], alreadyUnlocked: [])
        XCTAssertTrue(unlocked.isEmpty)
    }

    func testCompletionistDenominatorExcludesFeatureBadges() {
        let core = (1...4).map {
            AchievementDefinition(id: "reg-\($0)", title: "t", subtitle: "t", category: .streak,
                                  badgeSymbol: "flame.fill", condition: .streakAtLeast(days: $0))
        }
        let meta = AchievementDefinition(id: "meta-50", title: "t", subtitle: "t", category: .meta,
                                         badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.5),
                                         isMeta: true)
        let features = (1...20).map { featureBadge("bingo.b\($0)") }

        // 2 of 4 core = 50% -- twenty locked feature badges must not dilute it.
        let unlocked = AchievementEngine.evaluate(context: context(longestStreak: 2),
                                                  catalog: core + features + [meta], alreadyUnlocked: [])
        XCTAssertTrue(unlocked.contains { $0.id == "meta-50" })

        // Unlocked feature badges do not count toward it either.
        let notYet = AchievementEngine.evaluate(context: context(longestStreak: 1),
                                                catalog: core + features + [meta],
                                                alreadyUnlocked: Set(features.map(\.id)))
        XCTAssertFalse(notYet.contains { $0.id == "meta-50" })
    }
}
