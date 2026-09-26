// SupplementsGamificationTests.swift
//
// add-supplements task 6.3: the supplement badges (with the spec's
// "Sunshine" and "Feature disabled" scenarios), the vitamin-alphabet
// collection, the creatine journey (scaled milestone grants, one moment),
// the per-day creatine history that outlives the 365-day digest, and the
// supplement challenges -- their progress and their place in the rotation
// only while supplements are active.

import XCTest
import FoodLogCore
@testable import Gamification

final class SupplementsGamificationTests: XCTestCase {
    /// `count` consecutive complete days from `start`, each with `ingredients`.
    private func run(from start: String, count: Int, _ ingredients: [IngredientID: Double]) -> [SupplementDaySignal] {
        var days: [SupplementDaySignal] = []
        var cursor = start
        for _ in 0..<count {
            days.append(ST.day(cursor, .complete, ingredients: ingredients))
            cursor = SupplementDate.adding(1, to: cursor) ?? cursor
        }
        return days
    }

    private func evaluate(_ days: [SupplementDaySignal], today: String, state: SupplementsState = SupplementsState(), refills: Int = 0) -> SupplementsEvaluator.Result {
        SupplementsEvaluator.evaluate(state: state, signals: ST.signals(today: today, days: days, refillsBeforeEmpty: refills))
    }

    // MARK: - Catalog

    func testBadgesAreDeclaredWithRaritiesAndCategory() {
        let badges = SupplementsCatalog.badges
        XCTAssertEqual(badges.count, 10)
        XCTAssertEqual(Set(badges.map(\.id)).count, 10)
        XCTAssertTrue(badges.allSatisfy { $0.id.hasPrefix("supplements.") && $0.featureId == SupplementsFeature.id })
        XCTAssertTrue(badges.allSatisfy { $0.category == .supplements && !$0.isCoreCatalogBadge })
        let rarity = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0.rarity) })
        XCTAssertEqual(rarity[SupplementsCatalog.firstStackBadge], .common)
        XCTAssertEqual(rarity[SupplementsCatalog.fullStackMonthBadge], .epic)
        XCTAssertEqual(rarity[SupplementsCatalog.sunshineBadge], .rare)
        XCTAssertEqual(SupplementsFeature(directory: ST.tempDirectory()).badges.map(\.id), badges.map(\.id))
        XCTAssertEqual(BadgeRegistry.duplicateIds(features: GamificationFeatureRegistry.makeAll(directory: ST.tempDirectory())), [])
    }

    // MARK: - Badges

    func testSpecSunshineUnlocksOnceAfterSixtyWinterDays() async throws {
        let today = "2027-03-31"
        let fiftyNine = run(from: "2026-10-01", count: 59, [.vitaminD: 25])
        XCTAssertFalse(evaluate(fiftyNine, today: today).badgeIds.contains(SupplementsCatalog.sunshineBadge))

        let sixty = run(from: "2026-10-01", count: 60, [.vitaminD: 25])
        let result = evaluate(sixty, today: today)
        XCTAssertTrue(result.badgeIds.contains(SupplementsCatalog.sunshineBadge))

        // "Unlocked once": the host records it through AchievementStore,
        // which only reports a badge the first time.
        let directory = ST.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AchievementStore(fileURL: directory.appendingPathComponent("achievements.json"))
        let first = try await store.unlock(ids: result.badgeIds, now: TestClock.date(2027, 3, 31))
        let second = try await store.unlock(ids: evaluate(sixty, today: today).badgeIds, now: TestClock.date(2027, 3, 31))
        XCTAssertTrue(first.contains(SupplementsCatalog.sunshineBadge))
        XCTAssertFalse(second.contains(SupplementsCatalog.sunshineBadge))
    }

    func testSunshineCountsOneSeasonAndOnlyOctoberToMarch() {
        // 30 days at the end of one season + 30 at the start of the next.
        let split = run(from: "2026-03-02", count: 30, [.vitaminD: 25]) + run(from: "2026-10-01", count: 30, [.vitaminD: 25])
        XCTAssertFalse(evaluate(split, today: "2026-10-30").badgeIds.contains(SupplementsCatalog.sunshineBadge))
        // Summer days never count.
        let summer = run(from: "2026-05-01", count: 90, [.vitaminD: 25])
        XCTAssertFalse(evaluate(summer, today: "2026-07-30").badgeIds.contains(SupplementsCatalog.sunshineBadge))
        XCTAssertEqual(SupplementsEvaluator.season(of: "2027-02-10"), 2026)
        XCTAssertEqual(SupplementsEvaluator.season(of: "2026-10-01"), 2026)
        XCTAssertNil(SupplementsEvaluator.season(of: "2026-09-30"))
    }

    func testStreakBadgesFollowTheLongestStreak() {
        let week = ST.days(from: ST.key(1), Array(repeating: .complete, count: 7))
        let ids = evaluate(week, today: ST.key(7)).badgeIds
        XCTAssertTrue(ids.contains(SupplementsCatalog.firstStackBadge))
        XCTAssertTrue(ids.contains(SupplementsCatalog.stackWeekBadge))
        XCTAssertFalse(ids.contains(SupplementsCatalog.fullStackMonthBadge))

        // A 30-day streak seen once stays the longest even after it breaks
        // and leaves the digest.
        let month = evaluate(run(from: "2026-08-01", count: 30, [:]), today: "2026-08-30")
        XCTAssertTrue(month.badgeIds.contains(SupplementsCatalog.fullStackMonthBadge))
        let later = evaluate(ST.days(from: ST.key(20), [.complete, .missed, .complete]), today: ST.key(22), state: month.state)
        XCTAssertEqual(later.progress.longestStreak, 30)
        XCTAssertEqual(later.progress.streak.length, 1)
        XCTAssertTrue(later.badgeIds.contains(SupplementsCatalog.fullStackMonthBadge))

        XCTAssertEqual(evaluate([], today: ST.key(22)).badgeIds, [], "nothing taken, nothing earned")
    }

    func testCreatineOmegaAndNeverRanOut() {
        let creatine29 = evaluate(run(from: "2026-08-01", count: 29, [.creatine: 5]), today: "2026-08-29")
        XCTAssertFalse(creatine29.badgeIds.contains(SupplementsCatalog.creatine30Badge))
        let creatine30 = evaluate(run(from: "2026-08-01", count: 30, [.creatine: 5]), today: "2026-08-30")
        XCTAssertTrue(creatine30.badgeIds.contains(SupplementsCatalog.creatine30Badge))
        XCTAssertFalse(creatine30.badgeIds.contains(SupplementsCatalog.creatine100Badge))

        // Omega-3 on 30 days in a row; a gap restarts the run.
        let omega = run(from: "2026-08-01", count: 30, [.omega3EPA_DHA: 1000])
        XCTAssertTrue(evaluate(omega, today: "2026-08-30").badgeIds.contains(SupplementsCatalog.omegaMonthBadge))
        var gap = omega
        gap[15] = ST.day(gap[15].day, .complete)
        XCTAssertFalse(evaluate(gap, today: "2026-08-30").badgeIds.contains(SupplementsCatalog.omegaMonthBadge))

        XCTAssertFalse(evaluate([], today: ST.key(22), refills: 2).badgeIds.contains(SupplementsCatalog.neverRanOutBadge))
        XCTAssertTrue(evaluate([], today: ST.key(22), refills: 3).badgeIds.contains(SupplementsCatalog.neverRanOutBadge))
    }

    // MARK: - Creatine history beyond the digest

    func testCreatineDaysOutliveTheDigest() {
        // Year one: creatine on 80 days, then the digest moves on.
        let first = evaluate(run(from: "2025-10-01", count: 80, [.creatine: 5]), today: "2025-12-19")
        XCTAssertEqual(first.progress.creatineDays, 80)
        XCTAssertEqual(first.progress.creatineGrams, 400)

        // A year later the digest no longer holds those days; 20 new ones.
        let later = evaluate(run(from: "2026-12-01", count: 20, [.creatine: 5]), today: "2026-12-20", state: first.state)
        XCTAssertEqual(later.progress.creatineDays, 100)
        XCTAssertEqual(later.progress.creatineGrams, 500)
        XCTAssertTrue(later.badgeIds.contains(SupplementsCatalog.creatine100Badge))

        // A day inside the digest edited to no creatine drops out.
        var edited = run(from: "2026-12-01", count: 20, [.creatine: 5])
        edited[0] = ST.day(edited[0].day, .complete)
        let afterEdit = evaluate(edited, today: "2026-12-20", state: later.state)
        XCTAssertEqual(afterEdit.progress.creatineDays, 99)
    }

    // MARK: - Collection

    func testVitaminAlphabetGrowsAndKeepsTheEarliestDay() {
        let first = evaluate([
            ST.day(ST.key(10), .complete, ingredients: [.vitaminD: 25, .magnesium: 200, .creatine: 5]),
            ST.day(ST.key(11), .complete, ingredients: [.zinc: 10]),
        ], today: ST.key(11))
        XCTAssertEqual(first.newlyCollected, [.vitaminD, .magnesium, .zinc])
        XCTAssertEqual(first.progress.collectedCount, 3)
        XCTAssertEqual(first.progress.collection.count, SupplementsCatalog.alphabet.count)
        XCTAssertEqual(first.progress.collection.first { $0.ingredient == .zinc }?.firstDay, ST.key(11))
        XCTAssertFalse(first.badgeIds.contains(SupplementsCatalog.alphabet5Badge))

        // Later digest without those days: nothing is lost; a backfill of
        // an earlier zinc day moves its date back; nothing new = no news.
        let second = evaluate([ST.day(ST.key(5), .complete, ingredients: [.zinc: 10])], today: ST.key(20), state: first.state)
        XCTAssertEqual(second.newlyCollected, [])
        XCTAssertEqual(second.progress.collectedCount, 3)
        XCTAssertEqual(second.state.collected?["zinc"], ST.key(5))

        let five = evaluate([ST.day(ST.key(21), .complete, ingredients: [.iron: 14, .vitaminC: 80])], today: ST.key(21), state: second.state)
        XCTAssertTrue(five.badgeIds.contains(SupplementsCatalog.alphabet5Badge))
        XCTAssertFalse(five.badgeIds.contains(SupplementsCatalog.alphabet10Badge))

        let allTen: [IngredientID: Double] = Dictionary(uniqueKeysWithValues: SupplementsCatalog.alphabet.prefix(10).map { ($0, 1.0) })
        let ten = evaluate([ST.day(ST.key(22), .complete, ingredients: allTen)], today: ST.key(22))
        XCTAssertTrue(ten.badgeIds.contains(SupplementsCatalog.alphabet10Badge))
    }

    // MARK: - Journey through the feature

    func testCreatineJourneyGrantsAScaledMilestoneAndAnnouncesItOnce() async {
        let feature = SupplementsFeature(directory: ST.tempDirectory())
        let today = "2026-08-20"
        // 20 days x 5 g = 100 g, stack complete every day.
        let signals = ST.signals(today: today, days: run(from: "2026-08-01", count: 20, [.creatine: 5]))

        let first = await feature.update(ST.context(signals, today: today))
        let milestoneXP = SupplementsFeature.grantXP(XPAward.journeyMilestone)
        XCTAssertLessThan(milestoneXP, XPAward.journeyMilestone, "optional source: scaled")
        XCTAssertTrue(first.grants.contains(RewardGrant(key: "supplements.journey.creatine-100g", kind: .xp(milestoneXP))))
        XCTAssertFalse(first.grants.contains { $0.key == "supplements.journey.creatine-500g" })
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(first.moments.first?.xpAwarded, milestoneXP)
        XCTAssertTrue(first.unlockBadgeIds.contains(SupplementsCatalog.firstStackBadge))
        XCTAssertTrue(first.unlockBadgeIds.contains(SupplementsCatalog.stackWeekBadge))
        XCTAssertEqual(first.summary?.symbol, "pills.fill")

        let progress = await feature.progress()
        XCTAssertEqual(progress?.creatineGrams, 100)
        XCTAssertEqual(progress?.lastMilestone?.id, "creatine-100g")
        XCTAssertEqual(progress?.nextMilestone?.id, "creatine-500g")
        XCTAssertEqual(progress?.fractionToNext ?? -1, 0, accuracy: 1e-9)

        let second = await feature.update(ST.context(signals, today: today))
        XCTAssertTrue(second.moments.isEmpty, "a milestone is announced once")
        XCTAssertEqual(second.grants, first.grants, "grants are re-emitted with the same keys (the ledger pays once)")
    }

    // MARK: - Spec: "Feature disabled"

    func testSpecFeatureDisabledKeepsEarnedBadgesAndDropsChallenges() async {
        let unlocked: Set<String> = [SupplementsCatalog.stackWeekBadge]
        let catalog = BadgeRegistry.badges(features: GamificationFeatureRegistry.makeAll(directory: ST.tempDirectory()))
        let visibleOff = SupplementsCatalog.visibleBadges(catalog, isEnabled: false, unlockedIds: unlocked)
        XCTAssertTrue(visibleOff.contains { $0.id == SupplementsCatalog.stackWeekBadge }, "the earned Stack week badge is still shown")
        XCTAssertFalse(visibleOff.contains { $0.id == SupplementsCatalog.sunshineBadge }, "unearned supplement badges are hidden while off")
        XCTAssertEqual(visibleOff.count, catalog.count - SupplementsCatalog.badges.count + 1)
        XCTAssertEqual(SupplementsCatalog.visibleBadges(catalog, isEnabled: true, unlockedIds: []), catalog)

        // No supplement challenge in the rotation while off (or without a digest).
        let days = ST.days(from: ST.key(10), Array(repeating: .complete, count: 12)).map {
            ST.day($0.day, .complete, slotMinutes: ["evening": 21 * 60, "morning": 8 * 60])
        }
        let off = ChallengeRotationPolicy(recentDays: [], supplements: ST.signals(today: ST.key(21), days: days, isEnabled: false))
        let none = ChallengeRotationPolicy(recentDays: [])
        let on = ChallengeRotationPolicy(recentDays: [], supplements: ST.signals(today: ST.key(21), days: days))
        for template in ChallengeCatalog.all where ChallengeCatalog.supplementTemplateIds.contains(template.id) {
            XCTAssertEqual(off.weight(for: template), 0, template.id)
            XCTAssertEqual(none.weight(for: template), 0, template.id)
            XCTAssertEqual(on.weight(for: template), ChallengeRotationPolicy.supplementWeight, template.id)
        }
        for offset in 0..<300 {
            let now = TestClock.date(2026, 1, 1).addingTimeInterval(Double(offset) * 7_919)
            let picked = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: [], now: now, policy: off)
            XCTAssertFalse(ChallengeCatalog.supplementTemplateIds.contains(picked.id))
        }

        // And the feature itself does nothing while off.
        let update = await SupplementsFeature(directory: ST.tempDirectory())
            .update(ST.context(ST.signals(today: ST.key(21), days: days, isEnabled: false), today: ST.key(21)))
        XCTAssertEqual(update, .empty)
    }

    // MARK: - Challenges

    func testSupplementChallengesStayOutOfTheStaticRotation() {
        let templates = ChallengeCatalog.all.filter { ChallengeCatalog.supplementTemplateIds.contains($0.id) }
        XCTAssertEqual(templates.count, 4)
        for template in templates {
            XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template), 0, template.id)
            XCTAssertFalse(template.kind.isSignalBased)
        }
        XCTAssertTrue(ChallengeRotationPolicy.rotationTemplateIds().isDisjoint(with: ChallengeCatalog.supplementTemplateIds),
                      "not part of 'complete every challenge'")
    }

    func testSlotChallengeIsOfferedOnlyWithThatSlotsData() {
        let evening = ChallengeCatalog.all.first { $0.id == "supp-evening-22" }!
        let stack = ChallengeCatalog.all.first { $0.id == "supp-stack-5" }!
        let noSlots = ST.signals(today: ST.key(21), days: ST.days(from: ST.key(10), Array(repeating: .complete, count: 12)))
        let policy = ChallengeRotationPolicy(recentDays: [], supplements: noSlots)
        XCTAssertEqual(policy.weight(for: evening), 0, "no evening slot completed in the last 14 days")
        XCTAssertEqual(policy.weight(for: stack), ChallengeRotationPolicy.supplementWeight)
    }

    private func progress(_ id: String, days: [SupplementDaySignal]?, now: Date) -> ChallengeProgress {
        let template = ChallengeCatalog.all.first { $0.id == id }!
        let active = ActiveChallenge(templateId: id, startedAt: TestClock.date(2026, 9, 21), baselineStreakLength: 0)
        return ChallengeEngine.progress(
            for: template,
            active: active,
            events: [],
            goalStatuses: [],
            now: now,
            supplements: days.map { ST.signals(today: FreezeDayKey.key(for: now, calendar: TestClock.calendar), days: $0) },
            boundaryHour: 0,
            calendar: TestClock.calendar
        )
    }

    func testStackChallengeProgress() {
        let days = ST.days(from: ST.key(21), [.complete, .complete, .partial, .complete, .complete, .neutral, .complete])
        let result = progress("supp-stack-5", days: days, now: TestClock.date(2026, 9, 27))
        XCTAssertEqual(result.current, 5)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(progress("supp-stack-5", days: nil, now: TestClock.date(2026, 9, 27)).current, 0)
        // A day before the window never counts.
        let early = [ST.day(ST.key(20), .complete)] + Array(days.prefix(4))
        XCTAssertEqual(progress("supp-stack-5", days: early, now: TestClock.date(2026, 9, 24)).current, 3)
    }

    func testEveningSlotChallengeCountsOnlyBeforeTen() {
        let minutes = [21 * 60 + 30, 22 * 60 + 10, 20 * 60, 21 * 60 + 59]
        let days = minutes.enumerated().map { index, minute in
            ST.day(ST.key(21 + index), .complete, slotMinutes: ["evening": minute])
        }
        let result = progress("supp-evening-22", days: days, now: TestClock.date(2026, 9, 24, hour: 23))
        XCTAssertEqual(result.current, 3)
        XCTAssertTrue(result.isComplete)
    }
}
