// SupplementStreakTests.swift
//
// add-supplements task 6.2: the supplement streak (neutral days neither
// count nor break it), the streak-freeze pool shared with the food streak
// (only streaks of 3+ days, the earlier break first, at most one freeze per
// missed day per streak, a consumed freeze stays consumed after a
// backfill), the pause bookkeeping that freezes the streak in place while
// the feature is off -- and that the food streak's freezes are unchanged
// when supplements are off. September 2026, UTC (`ST`/`BT`).

import XCTest
import FoodLogCore
@testable import Gamification

final class SupplementStreakTests: XCTestCase {
    private let calendar = TestClock.calendar

    private func m(_ day: Int) -> Date { BT.midnight(9, day) }

    private func input(_ days: [SupplementDaySignal], frozen: Set<String> = []) -> StreakFreezePlanner.SupplementStreakInput {
        StreakFreezePlanner.SupplementStreakInput(days: days, frozenDays: frozen)
    }

    /// 10..19 complete (10 days), 20 missed, 21 complete, 22 (today) not yet.
    private func tenDayStreakWithAMiss() -> [SupplementDaySignal] {
        ST.days(from: ST.key(10), Array(repeating: .complete, count: 10) + [.missed, .complete, .partial])
    }

    /// Food logged every day 1..22.
    private var foodEveryDay: Set<Date> { BT.midnights(from: BT.date(9, 1), through: BT.date(9, 22)) }

    // MARK: - The walk (spec: "A supplement streak counts consecutive stack-complete days")

    func testSpecNeutralDayInBetween() {
        // Mon 21 complete, Tue 22 nothing planned, Wed 23 complete.
        let days = ST.days(from: ST.key(21), [.complete, .neutral, .complete])
        let status = SupplementStreak.status(ST.signals(today: ST.key(23), days: days))
        XCTAssertEqual(status.length, 2)
        XCTAssertTrue(status.isCompleteToday)
        XCTAssertFalse(status.isAtRiskToday)
    }

    func testSpecMissedDayBreaksTheStreakByFridayMorning() {
        // ... Thu 24 planned but not all taken, no freeze; Friday morning
        // nothing ticked yet.
        let days = ST.days(from: ST.key(21), [.complete, .neutral, .complete, .partial, .missed])
        let status = SupplementStreak.status(ST.signals(today: ST.key(25), days: days))
        XCTAssertEqual(status.length, 0)
        XCTAssertEqual(SupplementStreak.walk(days: days, frozenDays: [], today: ST.key(25)).outcomes[ST.key(24)], .missed)
    }

    func testTodayInProgressIsAtRiskNotAMiss() {
        let days = ST.days(from: ST.key(21), [.complete, .complete, .partial])
        let status = SupplementStreak.status(ST.signals(today: ST.key(23), days: days))
        XCTAssertEqual(status.length, 2)
        XCTAssertTrue(status.isAtRiskToday)
        XCTAssertFalse(status.isCompleteToday)
    }

    func testFrozenDayKeepsTheLengthAndLongestIsTracked() {
        let days = tenDayStreakWithAMiss()
        let walk = SupplementStreak.walk(days: days, frozenDays: [ST.key(20)], today: ST.key(22))
        XCTAssertEqual(walk.outcomes[ST.key(20)], .frozen)
        XCTAssertEqual(walk.currentLength, 11)
        XCTAssertEqual(walk.lengthBefore[ST.key(20)], 10)
        let unfrozen = SupplementStreak.walk(days: days, frozenDays: [], today: ST.key(22))
        XCTAssertEqual(unfrozen.currentLength, 1)
        XCTAssertEqual(unfrozen.longestLength, 10)
    }

    // MARK: - Shared freeze pool (spec: "Streak freezes are shared ...")

    func testSpecSupplementStreakProtected() {
        // 1 freeze, a 10-day supplement streak, the stack missed on 20 Sep
        // while the food streak continues.
        let days = tenDayStreakWithAMiss()
        let grants = [BT.grant(9, 12)]
        let plan = StreakFreezePlanner.planShared(
            loggedDays: foodEveryDay, frozenDays: [], supplements: input(days),
            grants: grants, consumptions: [], today: m(22), calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions, [
            StreakFreezeStore.Consumption(frozenDay: ST.key(20), consumedOn: ST.key(22), protectedLength: 10, streak: "supplements"),
        ])
        XCTAssertEqual(plan.supplementFrozenDays, [ST.key(20)], "the missed day shows as frozen")
        XCTAssertTrue(plan.frozenDays.isEmpty, "the food streak needed nothing")
        let streak = SupplementStreak.status(ST.signals(today: ST.key(22), days: days, frozenDays: plan.supplementFrozenDays))
        XCTAssertEqual(streak.length, 11, "the supplement streak continues")
        XCTAssertEqual(FreezeBalance.compute(grants: grants, consumptions: plan.newConsumptions).available, 0, "the pool is empty")
    }

    func testSpecShortSupplementStreakIsNotProtected() {
        // A 2-day supplement streak, then a miss, with a freeze held.
        let days = ST.days(from: ST.key(19), [.complete, .complete, .missed, .partial])
        let grants = [BT.grant(9, 10)]
        let plan = StreakFreezePlanner.planShared(
            loggedDays: foodEveryDay, frozenDays: [], supplements: input(days),
            grants: grants, consumptions: [], today: m(22), calendar: calendar
        )
        XCTAssertTrue(plan.newConsumptions.isEmpty, "the freeze is not consumed")
        XCTAssertEqual(SupplementStreak.status(ST.signals(today: ST.key(22), days: days)).length, 0, "the streak breaks")
        XCTAssertEqual(FreezeBalance.compute(grants: grants, consumptions: plan.newConsumptions).available, 1)
    }

    func testTheEarlierBreakGetsTheOnlyFreeze() {
        // Food: 1..16 logged, 17 grace, 18 logged, 19 the resetting miss
        // (streak 17 before it), 20..22 logged. Supplements miss on 20.
        let food = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 16))
            .union([m(18)])
            .union(BT.midnights(from: BT.date(9, 20), through: BT.date(9, 22)))
        let plan = StreakFreezePlanner.planShared(
            loggedDays: food, frozenDays: [], supplements: input(tenDayStreakWithAMiss()),
            grants: [BT.grant(9, 5)], consumptions: [], today: m(22), calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions.map(\.frozenDay), [BT.key(9, 19)])
        XCTAssertEqual(plan.newConsumptions.first?.streakKind, .food)
        XCTAssertEqual(plan.frozenDays, [m(19)])
        XCTAssertTrue(plan.supplementFrozenDays.isEmpty, "no freeze left for the later supplement miss")
    }

    func testSameDayBreakGoesToFoodFirstAndEachStreakGetsOneFreezeAtMost() {
        // Food: 1..16, 17 grace, 18..19, 20 the resetting miss, 21..22.
        let food = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 16))
            .union(BT.midnights(from: BT.date(9, 18), through: BT.date(9, 19)))
            .union(BT.midnights(from: BT.date(9, 21), through: BT.date(9, 22)))
        let supplements = input(tenDayStreakWithAMiss())

        let one = StreakFreezePlanner.planShared(
            loggedDays: food, frozenDays: [], supplements: supplements,
            grants: [BT.grant(9, 5)], consumptions: [], today: m(22), calendar: calendar
        )
        XCTAssertEqual(one.newConsumptions.map(\.streakKind), [.food], "a tie goes to the food streak")

        let grants = [BT.grant(9, 5), BT.grant(9, 6)]
        let two = StreakFreezePlanner.planShared(
            loggedDays: food, frozenDays: [], supplements: supplements,
            grants: grants, consumptions: [], today: m(22), calendar: calendar
        )
        XCTAssertEqual(two.newConsumptions.map(\.frozenDay), [ST.key(20), ST.key(20)])
        XCTAssertEqual(Set(two.newConsumptions.compactMap(\.streakKind)), [.food, .supplements])
        XCTAssertEqual(FreezeBalance.compute(grants: grants, consumptions: two.newConsumptions).available, 0)

        // Idempotent: a second run over its own output freezes nothing more.
        let again = StreakFreezePlanner.planShared(
            loggedDays: food, frozenDays: two.frozenDays,
            supplements: input(supplements.days, frozen: two.supplementFrozenDays),
            grants: grants + [BT.grant(9, 7)], consumptions: two.newConsumptions, today: m(22), calendar: calendar
        )
        XCTAssertTrue(again.newConsumptions.isEmpty)
    }

    func testAConsumedFreezeStaysConsumedAfterABackfill() {
        let grants = [BT.grant(9, 12)]
        let days = tenDayStreakWithAMiss()
        let plan = StreakFreezePlanner.planShared(
            loggedDays: foodEveryDay, frozenDays: [], supplements: input(days),
            grants: grants, consumptions: [], today: m(22), calendar: calendar
        )
        // 20 Sep is backfilled as complete afterwards (D14).
        var backfilled = days
        backfilled[10] = ST.day(ST.key(20), .complete)
        let rerun = StreakFreezePlanner.planShared(
            loggedDays: foodEveryDay, frozenDays: [], supplements: input(backfilled, frozen: plan.supplementFrozenDays),
            grants: grants, consumptions: plan.newConsumptions, today: m(22), calendar: calendar
        )
        XCTAssertTrue(rerun.newConsumptions.isEmpty)
        XCTAssertEqual(FreezeBalance.compute(grants: grants, consumptions: plan.newConsumptions).available, 0, "no refund")
        let walk = SupplementStreak.walk(days: backfilled, frozenDays: plan.supplementFrozenDays, today: ST.key(22))
        XCTAssertEqual(walk.outcomes[ST.key(20)], .complete)
        XCTAssertEqual(walk.currentLength, 12)
    }

    // MARK: - Food results unchanged when supplements are off

    func testFoodOnlyPlanIsUnchangedBySharedPlanner() {
        let patterns: [Set<Date>] = [
            [],
            BT.midnights(from: BT.date(9, 1), through: BT.date(9, 10)),
            BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21)).union([m(23)]),
            [m(19), m(20), m(21)],
        ]
        let grantSets: [[RewardLedger.FreezeGrant]] = [[], [BT.grant(9, 10)], [BT.grant(9, 10), BT.grant(9, 20)]]
        // A supplement digest with nothing to protect (all complete or neutral).
        let harmless = input(ST.days(from: ST.key(15), [.complete, .neutral, .complete, .complete, .neutral, .complete]))
        for logged in patterns {
            for grants in grantSets {
                for todayDay in [13, 24, 25] {
                    let food = StreakFreezePlanner.plan(loggedDays: logged, frozenDays: [], grants: grants, consumptions: [], today: m(todayDay), calendar: calendar)
                    for supplements in [nil, harmless] {
                        let shared = StreakFreezePlanner.planShared(
                            loggedDays: logged, frozenDays: [], supplements: supplements,
                            grants: grants, consumptions: [], today: m(todayDay), calendar: calendar
                        )
                        XCTAssertEqual(shared.newConsumptions, food.newConsumptions)
                        XCTAssertEqual(shared.frozenDays, food.frozenDays)
                    }
                }
            }
        }
    }

    func testDisabledSupplementsDoNotTouchTheFoodFreezes() async {
        // The design example (food streak 21, Thursday 24 frozen) with a
        // disabled supplement digest full of misses.
        let logged = BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21)).union([m(23)])
        let grants = [BT.grant(9, 20, "boss.freeze")]
        let misses = ST.days(from: ST.key(10), Array(repeating: .complete, count: 12) + Array(repeating: .missed, count: 4))
        let disabled = ST.signals(today: ST.key(25), days: misses, isEnabled: false)

        let plain = await WeeklyBossFeature(directory: BT.tempDirectory()).applyStreakFreezes(
            loggedDays: logged, grants: grants, today: m(25), calendar: calendar
        )
        let withDisabled = await WeeklyBossFeature(directory: BT.tempDirectory()).applyStreakFreezes(
            loggedDays: logged, grants: grants, today: m(25), calendar: calendar, supplements: disabled
        )
        XCTAssertEqual(withDisabled.frozenDays, plain.frozenDays)
        XCTAssertEqual(withDisabled.frozenDays, [m(24)])
        XCTAssertEqual(withDisabled.balance, plain.balance)
        XCTAssertTrue(withDisabled.supplementFrozenDays.isEmpty)
    }

    // MARK: - End to end through the boss feature (real store)

    func testBossFeatureFreezesTheSupplementStreakOnceAndAnnouncesIt() async throws {
        let directory = BT.tempDirectory()
        let feature = WeeklyBossFeature(directory: directory)
        let signals = ST.signals(today: ST.key(22), days: tenDayStreakWithAMiss())
        let grants = [BT.grant(9, 12, "boss.freeze")]

        let first = await feature.applyStreakFreezes(loggedDays: foodEveryDay, grants: grants, today: m(22), calendar: calendar, supplements: signals)
        XCTAssertEqual(first.supplementFrozenDays, [ST.key(20)])
        XCTAssertTrue(first.frozenDays.isEmpty)
        XCTAssertEqual(first.balance.available, 0)
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(first.moments.first?.style, .freeze)
        XCTAssertEqual(first.moments.first?.title, "Supplement streak frozen")

        let second = await feature.applyStreakFreezes(loggedDays: foodEveryDay, grants: grants, today: m(22), calendar: calendar, supplements: signals)
        XCTAssertEqual(second.supplementFrozenDays, [ST.key(20)])
        XCTAssertTrue(second.moments.isEmpty, "a freeze is announced once")

        let stored = await StreakFreezeStore(directory: directory).consumptions()
        XCTAssertEqual(stored.map(\.streak), ["supplements"])
    }

    func testStoreKeepsOneFreezePerDayPerStreak() async throws {
        let store = StreakFreezeStore(directory: BT.tempDirectory("freeze-store"))
        let food = StreakFreezeStore.Consumption(frozenDay: ST.key(20), consumedOn: ST.key(22), protectedLength: 30)
        let supplement = StreakFreezeStore.Consumption(frozenDay: ST.key(20), consumedOn: ST.key(22), protectedLength: 10, streak: "supplements")
        let added = try await store.record([food, supplement, supplement])
        XCTAssertEqual(added, [food, supplement])
        let foodDays = await store.frozenDayKeys()
        let all = await store.consumptions()
        XCTAssertEqual(foodDays, [ST.key(20)])
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Pauses (D10: the streak is frozen in place while off)

    func testPauseBookkeeping() {
        var state = SupplementsState()
        XCTAssertTrue(SupplementPause.record(isActive: false, today: ST.key(22), state: &state))
        XCTAssertEqual(state.inactiveSince, ST.key(22))
        XCTAssertFalse(SupplementPause.record(isActive: false, today: ST.key(23), state: &state), "already paused")
        XCTAssertTrue(SupplementPause.record(isActive: true, today: ST.key(25), state: &state))
        XCTAssertNil(state.inactiveSince)
        XCTAssertEqual(state.pausedRanges, [SupplementPausedRange(from: ST.key(22), through: ST.key(24))])
        XCTAssertFalse(SupplementPause.record(isActive: true, today: ST.key(26), state: &state))

        // Off and on again the same day: no range.
        var sameDay = SupplementsState()
        _ = SupplementPause.record(isActive: false, today: ST.key(22), state: &sameDay)
        _ = SupplementPause.record(isActive: true, today: ST.key(22), state: &sameDay)
        XCTAssertEqual(sameDay.pausedRanges, [])
    }

    func testPausedDaysNeitherCountNorBreak() {
        let state = SupplementsState(pausedRanges: [SupplementPausedRange(from: ST.key(22), through: ST.key(24))])
        // 18..21 complete, 22..24 missed while off (24 even complete), 25 complete.
        var days = ST.days(from: ST.key(18), [.complete, .complete, .complete, .complete, .missed, .partial, .complete, .complete])
        XCTAssertEqual(SupplementStreak.status(ST.signals(today: ST.key(25), days: days)).length, 2)

        let paused = SupplementPause.apply(state, to: ST.signals(today: ST.key(25), days: days))
        XCTAssertEqual(paused.day(ST.key(22))?.status, .neutral)
        XCTAssertEqual(paused.day(ST.key(23))?.status, .neutral)
        XCTAssertEqual(paused.day(ST.key(24))?.status, .complete, "a complete day stays complete")
        XCTAssertEqual(SupplementStreak.status(paused).length, 6)

        days[4] = ST.day(ST.key(22), .missed)
        XCTAssertEqual(SupplementPause.apply(SupplementsState(), to: ST.signals(today: ST.key(25), days: days)).days, days, "no pause: unchanged")
    }

    func testFeaturePrepareRecordsAPauseAcrossRuns() async {
        let directory = ST.tempDirectory()
        let days = ST.days(from: ST.key(18), [.complete, .complete, .complete, .complete, .missed, .missed, .missed, .complete])
        // Switched off on 22 (a run sees it), on again on 25.
        let off = await SupplementsFeature(directory: directory).prepare(
            ST.signals(today: ST.key(22), days: Array(days.prefix(5)), isEnabled: false)
        )
        XCTAssertNotNil(off)
        let on = await SupplementsFeature(directory: directory).prepare(ST.signals(today: ST.key(25), days: days))
        XCTAssertEqual(on?.day(ST.key(23))?.status, .neutral)
        XCTAssertEqual(on.map { SupplementStreak.status($0).length }, 5)
    }
}
