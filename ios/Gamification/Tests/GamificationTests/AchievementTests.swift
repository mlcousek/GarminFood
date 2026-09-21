import XCTest
@testable import Gamification
import FoodLogCore

// AchievementTests.swift
//
// expand-gamification-depth task 5.7: catalog sanity, a boundary case per
// category, meta-achievement two-pass correctness, permanence (an
// achievement whose condition later becomes false is never revoked), and
// AchievementStore's own persistence/idempotency.
final class AchievementTests: XCTestCase {
    private func context(
        level: Int = 1,
        longestStreak: Int = 0,
        totalLogsEver: Int = 0,
        distinctFoods: Int = 0,
        challengesCompleted: Int = 0,
        distinctChallengesCompleted: Int = 0,
        catalogCount: Int = 226,
        dailyChallengesCompleted: Int = 0,
        goalHitDaysEver: [String: Int] = [:],
        maxSingleDayCalories: Double = 0,
        totalCaloriesEver: Double = 0,
        perfectMonth: Bool = false,
        leapDay: Bool = false,
        newYear: Bool = false,
        midnight: Bool = false,
        yearsSinceFirstLog: Int = 0
    ) -> AchievementContext {
        AchievementContext(
            level: level,
            longestStreak: longestStreak,
            totalLogsEver: totalLogsEver,
            distinctFoodsInRetainedHistory: distinctFoods,
            challengeCompletionCount: challengesCompleted,
            distinctCompletedChallengeTemplateCount: distinctChallengesCompleted,
            totalChallengeCatalogCount: catalogCount,
            dailyChallengeCompletionCount: dailyChallengesCompleted,
            goalHitDaysEver: goalHitDaysEver,
            maxSingleDayCalories: maxSingleDayCalories,
            totalCaloriesEver: totalCaloriesEver,
            hasPerfectCalendarMonth: perfectMonth,
            hasLoggedOnLeapDay: leapDay,
            hasLoggedOnNewYearsDay: newYear,
            hasLoggedAtMidnight: midnight,
            yearsSinceFirstLog: yearsSinceFirstLog
        )
    }

    // MARK: - Catalog sanity

    func testCatalogHasAtLeast100Definitions() {
        XCTAssertGreaterThanOrEqual(AchievementCatalog.all.count, 100)
    }

    func testCatalogIdsAreUnique() {
        let ids = AchievementCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testCatalogIncludesGenuineLongTailThresholds() {
        // design.md D5: at least one requirement that realistically takes a
        // year or more of sustained use -- a literal spec requirement, not
        // just a nice-to-have.
        let hasYearPlusStreak = AchievementCatalog.all.contains {
            if case .streakAtLeast(let days) = $0.condition { return days >= 365 }
            return false
        }
        let hasAnniversary = AchievementCatalog.all.contains {
            if case .anniversaryYears(let years) = $0.condition { return years >= 1 }
            return false
        }
        XCTAssertTrue(hasYearPlusStreak)
        XCTAssertTrue(hasAnniversary)
    }

    // MARK: - One boundary case per category

    func testStreakBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .streak, badgeSymbol: "flame.fill", condition: .streakAtLeast(days: 7))
        XCTAssertTrue(AchievementEngine.evaluate(context: context(longestStreak: 7), catalog: [def], alreadyUnlocked: []).map(\.id) == ["t"])
        XCTAssertTrue(AchievementEngine.evaluate(context: context(longestStreak: 6), catalog: [def], alreadyUnlocked: []).isEmpty)
    }

    func testLevelBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .level, badgeSymbol: "star.fill", condition: .levelAtLeast(level: 10))
        XCTAssertFalse(AchievementEngine.evaluate(context: context(level: 9), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
        XCTAssertTrue(AchievementEngine.evaluate(context: context(level: 10), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testVolumeBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .volume, badgeSymbol: "fork.knife", condition: .totalLogsAtLeast(count: 100))
        XCTAssertFalse(AchievementEngine.evaluate(context: context(totalLogsEver: 99), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
        XCTAssertTrue(AchievementEngine.evaluate(context: context(totalLogsEver: 100), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testVarietyBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .variety, badgeSymbol: "leaf.fill", condition: .distinctFoodsAtLeast(count: 25))
        XCTAssertTrue(AchievementEngine.evaluate(context: context(distinctFoods: 25), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testAllChallengesCompletedRequiresEveryDistinctTemplate() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .challenges, badgeSymbol: "target", condition: .allChallengesCompleted)
        let partial = context(distinctChallengesCompleted: 225, catalogCount: 226)
        let full = context(distinctChallengesCompleted: 226, catalogCount: 226)
        XCTAssertFalse(AchievementEngine.evaluate(context: partial, catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
        XCTAssertTrue(AchievementEngine.evaluate(context: full, catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testDailyChallengesBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .dailyChallenges, badgeSymbol: "checkmark.circle.fill", condition: .dailyChallengesCompletedAtLeast(count: 50))
        XCTAssertTrue(AchievementEngine.evaluate(context: context(dailyChallengesCompleted: 50), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testGoalHittingBoundaryReadsTheRightMacro() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .goalHitting, badgeSymbol: "checkmark.seal.fill", condition: .goalHitDaysAtLeast(macro: .protein, count: 100))
        let wrongMacro = context(goalHitDaysEver: ["carbs": 200])
        let rightMacro = context(goalHitDaysEver: ["protein": 100])
        XCTAssertFalse(AchievementEngine.evaluate(context: wrongMacro, catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
        XCTAssertTrue(AchievementEngine.evaluate(context: rightMacro, catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testExtremeSingleDayBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .extreme, badgeSymbol: "bolt.fill", condition: .singleDayCaloriesAtLeast(calories: 5000))
        XCTAssertFalse(AchievementEngine.evaluate(context: context(maxSingleDayCalories: 4999), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
        XCTAssertTrue(AchievementEngine.evaluate(context: context(maxSingleDayCalories: 5000), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testFunnyComparisonBoundary() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .funnyFacts, badgeSymbol: "party.popper.fill", condition: .totalCaloriesAtLeast(calories: 150_000))
        XCTAssertTrue(AchievementEngine.evaluate(context: context(totalCaloriesEver: 150_000), catalog: [def], alreadyUnlocked: []).contains { $0.id == "t" })
    }

    func testCalendarConditions() {
        let perfectMonth = AchievementDefinition(id: "pm", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "calendar", condition: .perfectCalendarMonth)
        let leap = AchievementDefinition(id: "ld", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "calendar", condition: .loggedOnLeapDay)
        let newYear = AchievementDefinition(id: "ny", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "calendar", condition: .loggedOnNewYearsDay)
        let midnight = AchievementDefinition(id: "mn", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "moon.stars.fill", condition: .loggedAtMidnight)
        let anniversary = AchievementDefinition(id: "an", title: "t", subtitle: "t", category: .calendar, badgeSymbol: "gift.fill", condition: .anniversaryYears(years: 1))

        let full = context(perfectMonth: true, leapDay: true, newYear: true, midnight: true, yearsSinceFirstLog: 1)
        let unlocked = AchievementEngine.evaluate(context: full, catalog: [perfectMonth, leap, newYear, midnight, anniversary], alreadyUnlocked: [])
        XCTAssertEqual(Set(unlocked.map(\.id)), ["pm", "ld", "ny", "mn", "an"])
    }

    // MARK: - Meta achievements

    func testMetaAchievementSeesThisPassOwnUnlocksInItsDenominator() {
        let regular = (1...4).map { AchievementDefinition(id: "reg-\($0)", title: "t", subtitle: "t", category: .streak, badgeSymbol: "flame.fill", condition: .streakAtLeast(days: $0)) }
        let meta = AchievementDefinition(id: "meta-50", title: "t", subtitle: "t", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.5), isMeta: true)

        // A streak of 2 satisfies regular achievements 1 and 2 (2 of 4 =
        // 50%) in THIS SAME evaluation pass -- the meta achievement must
        // see that, not just what was already unlocked before this call.
        let unlocked = AchievementEngine.evaluate(context: context(longestStreak: 2), catalog: regular + [meta], alreadyUnlocked: [])
        XCTAssertTrue(unlocked.contains { $0.id == "meta-50" })
    }

    func testMetaAchievementExcludesOtherMetaAchievementsFromItsDenominator() {
        let regular = [AchievementDefinition(id: "reg-1", title: "t", subtitle: "t", category: .streak, badgeSymbol: "flame.fill", condition: .streakAtLeast(days: 1))]
        let meta25 = AchievementDefinition(id: "meta-25", title: "t", subtitle: "t", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 0.25), isMeta: true)
        let meta100 = AchievementDefinition(id: "meta-100", title: "t", subtitle: "t", category: .meta, badgeSymbol: "crown.fill", condition: .unlockedFractionOfOthers(fraction: 1.0), isMeta: true)

        // Only ONE non-meta achievement exists; unlocking it is 100% of
        // the non-meta denominator, regardless of how many meta
        // achievements are also in the catalog.
        let unlocked = AchievementEngine.evaluate(context: context(longestStreak: 1), catalog: regular + [meta25, meta100], alreadyUnlocked: [])
        XCTAssertEqual(Set(unlocked.map(\.id)), ["reg-1", "meta-25", "meta-100"])
    }

    // MARK: - Permanence

    func testAlreadyUnlockedAchievementsAreNeverReEvaluated() {
        let def = AchievementDefinition(id: "t", title: "t", subtitle: "t", category: .streak, badgeSymbol: "flame.fill", condition: .streakAtLeast(days: 7))
        // Condition is met, but "t" is already in `alreadyUnlocked` -- must
        // not appear in the newly-unlocked list again.
        let unlocked = AchievementEngine.evaluate(context: context(longestStreak: 100), catalog: [def], alreadyUnlocked: ["t"])
        XCTAssertTrue(unlocked.isEmpty)
    }

    // MARK: - Store

    private func makeStore() -> AchievementStore {
        AchievementStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-achievements-\(UUID().uuidString).json"))
    }

    func testUnlockRecordsEachIdOnlyOnce() async throws {
        let store = makeStore()
        let firstBatch = try await store.unlock(ids: ["a", "b"], now: TestClock.date(2026, 1, 1))
        let secondBatch = try await store.unlock(ids: ["a", "c"], now: TestClock.date(2026, 1, 2))

        XCTAssertEqual(Set(firstBatch), ["a", "b"])
        XCTAssertEqual(secondBatch, ["c"], "already-unlocked ids must not be re-recorded or have their date overwritten")

        let dateForA = await store.unlockDate(for: "a")
        XCTAssertEqual(dateForA, TestClock.date(2026, 1, 1), "the unlock date must never change once recorded")
    }
}
