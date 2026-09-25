// SecretAchievementsFeatureTests.swift
//
// add-secret-achievements tasks 2.2: the feature run on top of the pure
// rules -- one combined `.secret` moment for several unlocks, 50 XP per
// secret exactly once across runs (real `RewardLedger` + `XPStore` in temp
// files, project convention), the keeper after all 15, grant keys inside
// the "secrets." namespace FeatureHost enforces, and no unlock from the
// still-running current day.

import XCTest
import FoodLogCore
@testable import Gamification

final class SecretAchievementsFeatureTests: XCTestCase {
    private typealias F = SecretFixtures

    private let now = SecretFixtures.date(2026, 9, 24, hour: 18)

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    private func makeFeature() -> SecretAchievementsFeature {
        SecretAchievementsFeature(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("secrets-\(UUID().uuidString)", isDirectory: true))
    }

    /// 5 coffees on Tuesday + fish Mon/Tue/Wed: Barista Mode and Gone Fishing.
    private func baristaAndFishingSnapshot() -> SignalsSnapshot {
        let monday = F.date(2026, 9, 21)
        let tuesday = F.date(2026, 9, 22)
        let wednesday = F.date(2026, 9, 23)
        let fish: (Date) -> SignalEntry = { F.entry("trout", tags: [.fish], at: $0.addingTimeInterval(7 * 3600)) }
        return F.snapshot([
            F.day(monday, entries: [fish(monday)]),
            F.day(tuesday, entries: F.entries(5, "espresso", tags: [.coffee], on: tuesday) + [fish(tuesday)]),
            F.day(wednesday, entries: [fish(wednesday)]),
        ], today: now)
    }

    func testBadgesAreTheCatalog() {
        let badges = makeFeature().badges
        XCTAssertEqual(badges, SecretCatalog.all)
        XCTAssertEqual(badges.filter(\.isSecret).count, 15)
    }

    func testNothingFoundOnAnEmptySnapshot() async {
        let update = await makeFeature().update(F.context(F.snapshot([], today: now), now: now))
        XCTAssertTrue(update.grants.isEmpty)
        XCTAssertTrue(update.unlockBadgeIds.isEmpty)
        XCTAssertTrue(update.moments.isEmpty)
        XCTAssertEqual(update.summary?.fraction, 0)
        XCTAssertEqual(update.summary?.subtitle, "Found: 0 of 15")
    }

    func testTwoSecretsAtOnceGiveOneCombinedMoment() async {
        let update = await makeFeature().update(F.context(baristaAndFishingSnapshot(), now: now))

        XCTAssertEqual(Set(update.unlockBadgeIds), [SecretAchievementId.barista.badgeId, SecretAchievementId.goneFishing.badgeId])
        XCTAssertEqual(update.moments.count, 1)
        let moment = update.moments.first
        XCTAssertEqual(moment?.style, .secret)
        XCTAssertEqual(moment?.featureId, SecretAchievementsFeature.id)
        XCTAssertEqual(moment?.title, "Secrets revealed!")
        XCTAssertTrue(moment?.message.contains("Barista Mode") ?? false, moment?.message ?? "")
        XCTAssertTrue(moment?.message.contains("Gone Fishing") ?? false, moment?.message ?? "")
        XCTAssertEqual(moment?.xpAwarded, 2 * (XPAward.secretUnlocked + XPAward.achievementBonus))

        XCTAssertEqual(update.grants.count, 2)
        XCTAssertTrue(update.grants.allSatisfy { $0.kind == .xp(50) })
        XCTAssertEqual(Set(update.grants.map(\.key)), ["secrets.secret.barista", "secrets.secret.gone-fishing"])
        XCTAssertEqual(update.summary?.subtitle, "Found: 2 of 15")
    }

    func testSingleSecretMomentUsesItsOwnSymbol() {
        let moment = SecretAchievementsFeature.revealMoment(for: [.barista])
        XCTAssertEqual(moment?.title, "Secret revealed!")
        XCTAssertEqual(moment?.message, "Barista Mode")
        XCTAssertEqual(moment?.symbol, SecretCatalog.symbol(for: .barista))
        XCTAssertNil(SecretAchievementsFeature.revealMoment(for: []))
    }

    func testGrantKeysStayInsideTheFeatureNamespace() async {
        let update = await makeFeature().update(F.context(baristaAndFishingSnapshot(), now: now))
        for grant in update.grants {
            XCTAssertTrue(grant.key.hasPrefix(SecretAchievementsFeature.id + "."), grant.key)
        }
    }

    func testXPIsAwardedOnceAcrossTwoRuns() async throws {
        let xp = XPStore(fileURL: tempURL("secrets-xp"))
        let ledger = RewardLedger(fileURL: tempURL("secrets-ledger"))
        let secrets = makeFeature()
        let snapshot = baristaAndFishingSnapshot()

        let first = await secrets.update(F.context(snapshot, now: now))
        let firstResult = try await ledger.apply(first.grants, day: snapshot.today, now: now, xpStore: xp)
        XCTAssertEqual(firstResult.xpAwarded, 100)

        // The host recorded the unlocks; the second run sees them.
        let second = await secrets.update(F.context(snapshot, now: now, unlocked: Set(first.unlockBadgeIds)))
        XCTAssertTrue(second.unlockBadgeIds.isEmpty)
        XCTAssertTrue(second.moments.isEmpty, "no second reveal")
        let secondResult = try await ledger.apply(second.grants, day: snapshot.today, now: now, xpStore: xp)
        XCTAssertEqual(secondResult.xpAwarded, 0)

        let total = await xp.currentTotal()
        XCTAssertEqual(total, 100)
    }

    func testKeeperUnlocksWithTheFifteenthSecret() async {
        let others = Set(SecretAchievementId.allCases.filter { $0 != .barista }.map(\.badgeId))
        let tuesday = F.date(2026, 9, 22)
        let snapshot = F.snapshot([F.day(tuesday, entries: F.entries(5, "espresso", tags: [.coffee], on: tuesday))], today: now)

        let update = await makeFeature().update(F.context(snapshot, now: now, unlocked: others))
        XCTAssertEqual(update.unlockBadgeIds, [SecretAchievementId.barista.badgeId, SecretCatalog.keeperId])
        XCTAssertEqual(update.summary?.fraction, 1)
        XCTAssertEqual(update.grants.count, 15)
    }

    func testKeeperNotBeforeAllFifteen() async {
        let fourteen = Set(SecretAchievementId.allCases.filter { $0 != .barista }.map(\.badgeId))
        let update = await makeFeature().update(F.context(F.snapshot([], today: now), now: now, unlocked: fourteen))
        XCTAssertFalse(update.unlockBadgeIds.contains(SecretCatalog.keeperId))
        XCTAssertEqual(update.summary?.subtitle, "Found: 14 of 15")
    }

    func testKeeperIsRequestedOnceAllAreFoundEvenIfMissedEarlier() async {
        let all = Set(SecretAchievementId.allCases.map(\.badgeId))
        let missed = await makeFeature().update(F.context(F.snapshot([], today: now), now: now, unlocked: all))
        XCTAssertEqual(missed.unlockBadgeIds, [SecretCatalog.keeperId])
        XCTAssertTrue(missed.moments.isEmpty)

        let done = await makeFeature().update(F.context(F.snapshot([], today: now), now: now, unlocked: all.union([SecretCatalog.keeperId])))
        XCTAssertTrue(done.unlockBadgeIds.isEmpty)
    }

    func testCompletedDayRulesIgnoreTheCurrentDay() async {
        // Today's running total is 1221 kcal over 4 entries: not yet a
        // Palindrome Day.
        let snapshot = F.snapshot([F.day(now, entries: F.entries(4, "meal", on: now, calories: 305.25))], today: now)
        let update = await makeFeature().update(F.context(snapshot, now: now))
        XCTAssertFalse(update.unlockBadgeIds.contains(SecretAchievementId.palindrome.badgeId))
        XCTAssertTrue(update.moments.isEmpty)

        // The same day seen from tomorrow is completed.
        let tomorrow = F.date(now, plusDays: 1)
        let later = await makeFeature().update(F.context(F.snapshot([F.day(now, entries: F.entries(4, "meal", on: now, calories: 305.25))], today: tomorrow), now: tomorrow))
        XCTAssertTrue(later.unlockBadgeIds.contains(SecretAchievementId.palindrome.badgeId))
    }

    func testFoundCount() {
        XCTAssertEqual(SecretAchievementsFeature.foundCount(unlockedBadgeIds: []), 0)
        XCTAssertEqual(SecretAchievementsFeature.foundCount(unlockedBadgeIds: ["secret.barista", "secret.keeper", "achv-first-log"]), 1)
    }
}
