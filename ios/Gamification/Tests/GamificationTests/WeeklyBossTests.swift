// WeeklyBossTests.swift
//
// add-weekly-boss-and-streak-freezes tasks 2.6 (design D8): the pure
// `BossPicker` (lowest adherence, never last week's boss, 14-day coverage,
// data requirement, new-user ghost, deterministic tie-break, target
// formula), `BossFight` (hits, completed-day-only bosses), and
// `WeeklyBossFeature` end to end with a real `BossStore` and a real
// `RewardLedger`/`XPStore` on unique temp files: defeat rewarded once
// across two runs, escape, perfect, bestiary. Fixtures: `BossTestSupport`.

import XCTest
import FoodLogCore
@testable import Gamification

final class WeeklyBossTests: XCTestCase {
    private let calendar = BT.calendar
    private let w39 = BT.week("2026-W39")

    // MARK: - Picker

    func testAnalysisWindowIsTheFourPreviousWeeks() {
        let keys = BossPicker.analysisDayKeys(before: w39, calendar: calendar)
        XCTAssertEqual(keys.count, 28)
        XCTAssertEqual(keys.first, BT.key(8, 24))
        XCTAssertEqual(keys.last, BT.key(9, 20))
    }

    func testLowestAdherenceWins() {
        let snapshot = BT.snapshot(BT.weakBreakfastWindow(), today: BT.date(9, 21))
        let pick = BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(pick.kind, .breakfastGoblin)
        XCTAssertEqual(pick.goodDays, 12)
        XCTAssertEqual(pick.consideredDays, 28)
        XCTAssertEqual(pick.target, 5, "ceil(12/28 * 7) + 2")
    }

    func testLastWeeksBossIsExcluded() {
        // Breakfast weakest (12/28), fruit next (20/28).
        let days = BT.history(from: BT.date(8, 24), through: BT.date(9, 20), breakfastOn: { $0 % 7 < 3 }, fruitOn: { $0 % 7 < 5 })
        let snapshot = BT.snapshot(days, today: BT.date(9, 21))
        XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar).kind, .breakfastGoblin)
        let pick = BossPicker.pick(week: w39, previous: .breakfastGoblin, snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(pick.kind, .scurvyPirate)
        XCTAssertEqual(pick.target, 7, "ceil(20/28 * 7) + 2 = 7")
    }

    func testCoverageBelowFourteenDaysIsIneligible() {
        func window(waterDays: Int) -> SignalsSnapshot {
            let dates = BT.dates(from: BT.date(8, 24), through: BT.date(9, 20))
            let days = dates.enumerated().map { index, date in
                BT.day(date, breakfast: index % 7 < 3,
                       waterML: index < waterDays ? 500 : nil,
                       waterGoalML: index < waterDays ? 2000 : nil)
            }
            return BT.snapshot(days, today: BT.date(9, 21))
        }
        XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: window(waterDays: 10), calendar: calendar).kind, .breakfastGoblin,
                       "water on 10 of 28 days: the dragon is not eligible")
        let pick = BossPicker.pick(week: w39, previous: nil, snapshot: window(waterDays: 14), calendar: calendar)
        XCTAssertEqual(pick.kind, .desertDragon)
        XCTAssertEqual(pick.target, 3, "adherence 0 -> clamp to 3")
    }

    func testDataRequirementFilter() {
        let snapshot = BT.snapshot(BT.weakBreakfastWindow(), today: BT.date(9, 21))
        let keys = BossPicker.analysisDayKeys(before: w39, calendar: calendar)
        for kind in [BossKind.desertDragon, .fibrePhantom, .proteinPoltergeist, .calorieKraken] {
            let value = BossPicker.adherence(kind, dayKeys: keys, snapshot: snapshot, calendar: calendar)
            XCTAssertFalse(BossPicker.isEligible(kind, adherence: value, dayKeys: keys, snapshot: snapshot), kind.rawValue)
        }
        let ghost = BossPicker.adherence(.forgetfulGhost, dayKeys: keys, snapshot: snapshot, calendar: calendar)
        XCTAssertTrue(BossPicker.isEligible(.forgetfulGhost, adherence: ghost, dayKeys: keys, snapshot: snapshot))
        XCTAssertEqual(ghost.considered, 28)
    }

    func testNewUserGetsTheForgetfulGhost() {
        let days = BT.history(from: BT.date(9, 15), through: BT.date(9, 20), breakfastOn: { _ in false })
        let snapshot = BT.snapshot(days, today: BT.date(9, 21))
        let pick = BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(pick.kind, .forgetfulGhost)
        XCTAssertEqual(pick.goodDays, 6)
        XCTAssertEqual(pick.consideredDays, 28)
        XCTAssertEqual(pick.target, 4, "ceil(6/28 * 7) + 2 = 2 + 2")
        // Never twice in a row, even for a new user.
        XCTAssertNotEqual(BossPicker.pick(week: w39, previous: .forgetfulGhost, snapshot: snapshot, calendar: calendar).kind, .forgetfulGhost)
    }

    func testTieBreakIsDeterministicPerWeek() {
        // Every habit perfect: all eligible archetypes tie at 100 %.
        let days = BT.history(from: BT.date(8, 24), through: BT.date(9, 20), breakfastOn: { _ in true })
        let snapshot = BT.snapshot(days, today: BT.date(9, 21))
        let tied: Set<BossKind> = [.breakfastGoblin, .beigeBeast, .midnightMuncher, .sodaLich, .scurvyPirate, .forgetfulGhost]
        let first = BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar)
        XCTAssertTrue(tied.contains(first.kind), first.kind.rawValue)
        for _ in 0..<5 {
            XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar), first)
        }
        XCTAssertEqual(first.target, 7)
    }

    func testTargetFormula() {
        XCTAssertEqual(BossPicker.target(adherence: 0), 3)
        XCTAssertEqual(BossPicker.target(adherence: 0.42), 5)
        XCTAssertEqual(BossPicker.target(adherence: 0.9), 7)
        XCTAssertEqual(BossPicker.target(adherence: 1), 7)
        XCTAssertEqual(BossPicker.target(good: 11, considered: 26), 5, "design example: 42 % -> 5")
        XCTAssertEqual(BossPicker.target(good: 4, considered: 7), 6, "exactly 4 of 7 -> 4 + 2")
        XCTAssertEqual(BossPicker.target(good: 0, considered: 0), 3)
    }

    // MARK: - Fight

    func testHitsCountQualifyingDaysUpToToday() {
        // W39: breakfast Mon, Tue, Wed; today Wed.
        var days = BT.weakBreakfastWindow()
        days += [BT.day(BT.date(9, 21), breakfast: true), BT.day(BT.date(9, 22), breakfast: true), BT.day(BT.date(9, 23), breakfast: true)]
        let snapshot = BT.snapshot(days, today: BT.date(9, 23))
        let hits = BossFight.hitDays(.breakfastGoblin, week: w39, snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(hits, [BT.key(9, 21), BT.key(9, 22), BT.key(9, 23)])
        XCTAssertEqual(BossFight.daysLeft(in: w39, todayKey: BT.key(9, 23), calendar: calendar), 5)
    }

    func testLateNightBossIgnoresTodayUntilItIsComplete() {
        // Mon, Tue clean; today Wed at 19:00 with an evening entry, nothing after 21:00 yet.
        var days = BT.weakBreakfastWindow()
        days += [
            BT.day(BT.date(9, 21), breakfast: false),
            BT.day(BT.date(9, 22), breakfast: false),
            BT.day(BT.date(9, 23), breakfast: false, eveningEntry: true),
        ]
        let snapshot = BT.snapshot(days, today: BT.date(9, 23))
        XCTAssertEqual(BossFight.hitDays(.midnightMuncher, week: w39, snapshot: snapshot, calendar: calendar), [BT.key(9, 21), BT.key(9, 22)])
        XCTAssertEqual(BossFight.hitDays(.sodaLich, week: w39, snapshot: snapshot, calendar: calendar), [BT.key(9, 21), BT.key(9, 22)])

        // A late snack spoils a completed day.
        var spoiled = BT.weakBreakfastWindow()
        spoiled += [BT.day(BT.date(9, 21), breakfast: false, lateSnack: true), BT.day(BT.date(9, 22), breakfast: false)]
        let later = BT.snapshot(spoiled, today: BT.date(9, 23))
        XCTAssertEqual(BossFight.hitDays(.midnightMuncher, week: w39, snapshot: later, calendar: calendar), [BT.key(9, 22)])
    }

    func testDefeatXPRange() {
        XCTAssertEqual(BossFight.defeatXP(target: 3), 150)
        XCTAssertEqual(BossFight.defeatXP(target: 5), 200)
        XCTAssertEqual(BossFight.defeatXP(target: 7), 250)
    }

    // MARK: - Feature end to end

    func testDefeatIsRewardedOnceAcrossTwoRuns() async throws {
        let directory = BT.tempDirectory()
        let feature = WeeklyBossFeature(directory: directory)
        let ledger = RewardLedger(fileURL: directory.appendingPathComponent("ledger.json"))
        let xp = XPStore(fileURL: directory.appendingPathComponent("xp.json"))

        // Monday: the boss is introduced.
        var days = BT.weakBreakfastWindow()
        days.append(BT.day(BT.date(9, 21), breakfast: true))
        let monday = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 21)), now: BT.date(9, 21)))
        XCTAssertEqual(monday.moments.map(\.style), [.boss], "intro moment")
        XCTAssertTrue(monday.grants.isEmpty)
        XCTAssertEqual(monday.summary?.fraction ?? -1, 0.2, accuracy: 0.0001)
        let intro = await feature.currentBoss()
        XCTAssertEqual(intro?.archetype.kind, .breakfastGoblin)
        XCTAssertEqual(intro?.target, 5)
        XCTAssertEqual(intro?.remainingHP, 4)

        // Friday: 5th hit.
        for day in 22...25 { days.append(BT.day(BT.date(9, day), breakfast: true)) }
        let context = BT.context(BT.snapshot(days, today: BT.date(9, 25)), now: BT.date(9, 25))
        let friday = await feature.update(context)
        XCTAssertEqual(friday.moments.map(\.style), [.boss], "defeat moment only (no second intro)")
        XCTAssertEqual(friday.moments.first?.xpAwarded, 200)
        XCTAssertTrue(friday.unlockBadgeIds.contains(BossCatalog.firstDefeatBadge))
        XCTAssertTrue(friday.grants.allSatisfy { $0.key.hasPrefix(WeeklyBossFeature.id + ".") }, "host namespace rule")
        XCTAssertEqual(Set(friday.grants), [
            RewardGrant(key: "boss.defeat.2026-W39", kind: .xp(200)),
            RewardGrant(key: "boss.freeze.2026-W39", kind: .streakFreeze),
        ])
        let applied = try await ledger.apply(friday.grants, day: BT.key(9, 25), now: BT.date(9, 25), xpStore: xp)
        XCTAssertEqual(applied.xpAwarded, 200)

        // Saturday: re-emitted, applied nothing, no new moment.
        let again = await feature.update(context)
        XCTAssertTrue(again.moments.isEmpty)
        let reapplied = try await ledger.apply(again.grants, day: BT.key(9, 26), now: BT.date(9, 26), xpStore: xp)
        XCTAssertEqual(reapplied.xpAwarded, 0)
        let freezes = await ledger.freezeGrants()
        XCTAssertEqual(freezes.map(\.key), ["boss.freeze.2026-W39"])
        XCTAssertEqual(freezes.first?.day, BT.key(9, 25))
        let current = await feature.currentBoss()
        XCTAssertEqual(current?.outcome, .defeated)
    }

    func testEscapedBossHasNoPenaltyAndNextWeekDiffers() async {
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        // W38 (14-20 Sep), analysed over 17 Aug - 13 Sep: breakfast weakest.
        var days = BT.history(from: BT.date(8, 17), through: BT.date(9, 13), breakfastOn: { $0 % 7 < 3 })
        days += BT.history(from: BT.date(9, 14), through: BT.date(9, 20), breakfastOn: { $0 < 3 })
        let w38Run = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 16)), now: BT.date(9, 16)))
        XCTAssertEqual(w38Run.moments.count, 1)

        // Monday of W39: W38 had 3 of 5 hits -> escaped; breakfast is still
        // the weakest habit, but never twice in a row.
        let monday = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 21)), now: BT.date(9, 21)))
        XCTAssertTrue(monday.grants.isEmpty, "no reward, no penalty")
        let history = await feature.history()
        XCTAssertEqual(history.map(\.week.rawValue), ["2026-W38"])
        XCTAssertEqual(history.first?.outcome, .escaped)
        XCTAssertEqual(history.first?.hits, 3)
        let current = await feature.currentBoss()
        XCTAssertNotNil(current)
        XCTAssertNotEqual(current?.archetype.kind, .breakfastGoblin)
    }

    func testLateDefeatIsSettledOnTheNextRun() async {
        // The 5th hit is on Sunday; the app next runs on Monday.
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        var days = BT.weakBreakfastWindow()
        days.append(BT.day(BT.date(9, 21), breakfast: true))
        _ = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 21)), now: BT.date(9, 21)))
        for day in 22...27 { days.append(BT.day(BT.date(9, day), breakfast: day >= 24)) }
        let nextMonday = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 28)), now: BT.date(9, 28)))
        XCTAssertTrue(nextMonday.grants.contains(RewardGrant(key: "boss.defeat.2026-W39", kind: .xp(200))))
        XCTAssertTrue(nextMonday.moments.contains { $0.style == .boss && $0.xpAwarded == 200 })
    }

    func testPerfectDefeatUnlocksFlawlessVictory() async {
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        // Breakfast on 20 of 28 days (still the weakest) -> target 7.
        var days = BT.history(from: BT.date(8, 24), through: BT.date(9, 20), breakfastOn: { $0 % 7 < 5 })
        days += BT.history(from: BT.date(9, 21), through: BT.date(9, 27), breakfastOn: { _ in true })
        let update = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 27)), now: BT.date(9, 27)))
        XCTAssertTrue(update.grants.contains(RewardGrant(key: "boss.defeat.2026-W39", kind: .xp(250))))
        XCTAssertTrue(update.unlockBadgeIds.contains(BossCatalog.perfectBadge))
    }

    func testBadgeRules() {
        let all = BossState(defeatCount: 25, defeatedIds: BossKind.allCases.map(\.rawValue), perfectDefeat: true)
        let consumptions = [StreakFreezeStore.Consumption(frozenDay: BT.key(9, 1), consumedOn: nil, protectedLength: 120)]
        XCTAssertEqual(Set(WeeklyBossFeature.badgeIds(state: all, consumptions: consumptions)), Set(BossCatalog.badges.map(\.id)))

        let one = BossState(defeatCount: 1, defeatedIds: ["breakfast-goblin"])
        XCTAssertEqual(WeeklyBossFeature.badgeIds(state: one, consumptions: []), [BossCatalog.firstDefeatBadge])
        let shortSave = [StreakFreezeStore.Consumption(frozenDay: BT.key(9, 1), consumedOn: nil, protectedLength: 99)]
        XCTAssertEqual(WeeklyBossFeature.badgeIds(state: BossState(), consumptions: shortSave), [BossCatalog.firstFreezeBadge])
    }

    func testBestiaryLightsDefeatedArchetypes() async {
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        var days = BT.weakBreakfastWindow()
        days += BT.history(from: BT.date(9, 21), through: BT.date(9, 25), breakfastOn: { _ in true })
        _ = await feature.update(BT.context(BT.snapshot(days, today: BT.date(9, 25)), now: BT.date(9, 25)))
        let bestiary = await feature.bestiary()
        XCTAssertEqual(bestiary.count, 10)
        XCTAssertEqual(bestiary.filter(\.isDefeated).map(\.archetype.kind), [.breakfastGoblin])
    }

    // MARK: - Store and catalog

    func testStoreKeeps26WeeksAndSurvivesGarbage() async throws {
        var state = BossState()
        var weeks: [String: BossWeekRecord] = [:]
        for week in 1...30 {
            weeks[WeekKey(yearForWeek: 2026, week: week).rawValue] = BossWeekRecord(bossId: "breakfast-goblin", target: 5)
        }
        state.weeks = weeks
        state.prune()
        XCTAssertEqual(state.weeks?.count, 26)
        XCTAssertNil(state.weeks?["2026-W04"])
        XCTAssertNotNil(state.weeks?["2026-W05"])

        let directory = BT.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: directory.appendingPathComponent(BossStore.fileName))
        let store = BossStore(directory: directory)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isReadable)
        XCTAssertEqual(loaded.state, BossState())
        try await BossStore(directory: directory).save(state)
        let reloaded = await BossStore(directory: directory).load()
        XCTAssertEqual(reloaded.state.weeks?.count, 26)
    }

    func testRecordToleratesMissingAndUnknownFields() throws {
        let json = #"{"weeks":{"2026-W39":{"bossId":"desert-dragon","outcome":"somethingNew"}}}"#
        let state = try JSONDecoder().decode(BossState.self, from: Data(json.utf8))
        let record = try XCTUnwrap(state.weeks?["2026-W39"])
        XCTAssertEqual(record.kind, .desertDragon)
        XCTAssertEqual(record.resolvedOutcome, .active)
        XCTAssertEqual(record.resolvedTarget, 3)
        XCTAssertEqual(record.hitCount, 0)
    }

    func testCatalogHasTenArchetypesAndUniqueBadges() {
        XCTAssertEqual(BossCatalog.all.count, 10)
        XCTAssertEqual(Set(BossCatalog.all.map(\.id)).count, 10)
        let ids = BossCatalog.badges.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("boss.") || $0.hasPrefix("freeze.") })
        XCTAssertTrue(BossCatalog.badges.allSatisfy { $0.featureId == WeeklyBossFeature.id && $0.condition == .featureEvaluated })
        XCTAssertTrue(BossCatalog.archetype(.midnightMuncher).judgesCompletedDaysOnly)
        XCTAssertTrue(BossCatalog.archetype(.sodaLich).judgesCompletedDaysOnly)
    }

    func testCzechNamesResolve() throws {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "cs", ofType: "lproj"))
        let czech = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(czech.localizedString(forKey: "Breakfast Goblin", value: "<missing>", table: nil), "Snídaňový skřet")
        XCTAssertEqual(czech.localizedString(forKey: "Desert Dragon", value: "<missing>", table: nil), "Pouštní drak")
        XCTAssertEqual(czech.localizedString(forKey: "Streak frozen", value: "<missing>", table: nil), "Série zamrazena")
    }
}
