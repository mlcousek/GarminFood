// StreakFreezeTests.swift
//
// add-weekly-boss-and-streak-freezes tasks 1.7: the `.frozen` walk
// semantics in `StreakEngine`/`StreakHistory`, the pure
// `StreakFreezePlanner` (design D6) and `FreezeBalance` replay (D4), the
// `StreakFreezeStore` file contract, and the spec scenario "streak 21,
// Thursday frozen" end to end through `WeeklyBossFeature.applyStreakFreezes`
// with a real store on a temp directory. September 2026, UTC: Mon 21 Sep ...
// Sun 27 Sep is one ISO week.

import XCTest
import FoodLogCore
@testable import Gamification

final class StreakFreezeTests: XCTestCase {
    private let calendar = BT.calendar

    private func m(_ day: Int, _ month: Int = 9) -> Date { BT.midnight(month, day) }

    /// Logged 2..21 Sep (20 days), missed Tue 22 (grace), logged Wed 23
    /// (21), missed Thu 24 -- design D6's example.
    private func designExampleLoggedDays() -> Set<Date> {
        BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21)).union([m(23)])
    }

    // MARK: - Walk semantics (design D5)

    func testNoFrozenDaysIsIdenticalToTheOriginalWalk() {
        let patterns: [Set<Date>] = [
            [],
            BT.midnights(from: BT.date(9, 1), through: BT.date(9, 10)),
            designExampleLoggedDays(),
            [m(1), m(3), m(4), m(9), m(10), m(12)],
        ]
        for logged in patterns {
            for todayDay in [10, 13, 24, 25] {
                let today = m(todayDay)
                XCTAssertEqual(
                    StreakEngine.status(loggedDays: logged, today: today, calendar: calendar),
                    StreakEngine.status(loggedDays: logged, frozenDays: [], today: today, calendar: calendar)
                )
                XCTAssertEqual(
                    StreakHistory.summary(loggedDays: logged, today: today, calendar: calendar),
                    StreakHistory.summary(loggedDays: logged, frozenDays: [], today: today, calendar: calendar)
                )
                let plan = StreakFreezePlanner.plan(loggedDays: logged, frozenDays: [], grants: [], consumptions: [], today: today, calendar: calendar)
                XCTAssertTrue(plan.newConsumptions.isEmpty, "no grant ever earned -> nothing consumed")
                XCTAssertTrue(plan.frozenDays.isEmpty)
            }
        }
    }

    func testFrozenDayKeepsLengthWithoutAddingToIt() {
        let logged = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 5)).union([m(7)])
        let status = StreakEngine.status(loggedDays: logged, frozenDays: [m(6)], today: m(7), calendar: calendar)
        XCTAssertEqual(status.length, 6, "5 logged + frozen (no change) + 1 logged")
        let summary = StreakHistory.summary(loggedDays: logged, frozenDays: [m(6)], today: m(7), calendar: calendar)
        XCTAssertEqual(summary.days.first { $0.date == m(6) }?.mark, .frozen)
    }

    func testFrozenDayIsNotPartOfTheGraceWindow() {
        // 1-5 logged, 6 frozen, 7 missed, 8 logged: 7 is the window's ONLY
        // miss (the frozen day doesn't count), so it is forgiven.
        let logged = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 5)).union([m(8)])
        let withFreeze = StreakEngine.status(loggedDays: logged, frozenDays: [m(6)], today: m(8), calendar: calendar)
        XCTAssertEqual(withFreeze.length, 6)
        let summary = StreakHistory.summary(loggedDays: logged, frozenDays: [m(6)], today: m(8), calendar: calendar)
        XCTAssertEqual(summary.days.first { $0.date == m(7) }?.mark, .grace)

        // Without it, 6 is the grace and 7 the reset.
        let without = StreakEngine.status(loggedDays: logged, today: m(8), calendar: calendar)
        XCTAssertEqual(without.length, 1)
    }

    func testFrozenDayNeverResets() {
        // 1-5 logged, 6 missed (grace), 7 frozen, 8 logged.
        let logged = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 5)).union([m(8)])
        let status = StreakEngine.status(loggedDays: logged, frozenDays: [m(7)], today: m(8), calendar: calendar)
        XCTAssertEqual(status.length, 6)
        let summary = StreakHistory.summary(loggedDays: logged, frozenDays: [m(7)], today: m(8), calendar: calendar)
        XCTAssertEqual(summary.longestLength, 6, "a freeze-bridged run counts toward the longest streak")
    }

    func testBackfilledFrozenDayWalksAsLogged() {
        let logged = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 7))
        let status = StreakEngine.status(loggedDays: logged, frozenDays: [m(6)], today: m(7), calendar: calendar)
        XCTAssertEqual(status.length, 7)
        let summary = StreakHistory.summary(loggedDays: logged, frozenDays: [m(6)], today: m(7), calendar: calendar)
        XCTAssertEqual(summary.days.first { $0.date == m(6) }?.mark, .logged)
    }

    // MARK: - Planner (design D6)

    func testSpecScenarioThursdayIsFrozenAndTheStreakStays21() {
        let logged = designExampleLoggedDays()
        let today = m(25)
        XCTAssertEqual(StreakEngine.status(loggedDays: logged, today: today, calendar: calendar).length, 0,
                       "without a freeze Thursday is the second miss in 7 days")

        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 20)], consumptions: [], today: today, calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions.map(\.frozenDay), [BT.key(9, 24)])
        XCTAssertEqual(plan.newConsumptions.first?.protectedLength, 21)
        XCTAssertEqual(plan.newConsumptions.first?.consumedOn, BT.key(9, 25))
        let status = StreakEngine.status(loggedDays: logged, frozenDays: plan.frozenDays, today: today, calendar: calendar)
        XCTAssertEqual(status.length, 21)
        XCTAssertTrue(status.isAtRiskToday, "still at risk until Friday is logged")
        XCTAssertEqual(StreakEngine.status(loggedDays: logged.union([today]), frozenDays: plan.frozenDays, today: today, calendar: calendar).length, 22)
        XCTAssertEqual(FreezeBalance.compute(grants: [BT.grant(9, 20)], consumptions: plan.newConsumptions).available, 0)
    }

    func testGraceDayDoesNotUseAFreeze() {
        let logged = BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21))
            .union(BT.midnights(from: BT.date(9, 23), through: BT.date(9, 24)))
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 10)], consumptions: [], today: m(25), calendar: calendar
        )
        XCTAssertTrue(plan.newConsumptions.isEmpty)
        XCTAssertEqual(StreakEngine.status(loggedDays: logged, today: m(25), calendar: calendar).length, 22)
    }

    func testTwoDayStreakIsNotProtected() {
        // 20-21 logged (2 days), 22 grace, 23 would reset.
        let logged: Set<Date> = [m(20), m(21)]
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 10)], consumptions: [], today: m(24), calendar: calendar
        )
        XCTAssertTrue(plan.newConsumptions.isEmpty)
    }

    func testThreeDayStreakIsProtected() {
        let logged: Set<Date> = [m(19), m(20), m(21)]
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 10)], consumptions: [], today: m(24), calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions.map(\.frozenDay), [BT.key(9, 23)])
        XCTAssertEqual(StreakEngine.status(loggedDays: logged, frozenDays: plan.frozenDays, today: m(24), calendar: calendar).length, 3)
    }

    func testMissOlderThanSevenDaysIsNotFrozen() {
        // 1-10 logged, 11 grace, 12 reset, 13-25 logged; today 25.
        let logged = BT.midnights(from: BT.date(9, 1), through: BT.date(9, 10))
            .union(BT.midnights(from: BT.date(9, 13), through: BT.date(9, 25)))
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 1)], consumptions: [], today: m(25), calendar: calendar
        )
        XCTAssertTrue(plan.newConsumptions.isEmpty)
    }

    func testFreezeEarnedAfterTheMissIsNotUsedForIt() {
        // Thu 24 is the streak-breaking miss; the only freeze came Sat 26.
        let logged = BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21))
            .union([m(23), m(25), m(26)])
        for grantDay in [24, 26] {
            let plan = StreakFreezePlanner.plan(
                loggedDays: logged, frozenDays: [], grants: [BT.grant(9, grantDay)], consumptions: [], today: m(27), calendar: calendar
            )
            XCTAssertTrue(plan.newConsumptions.isEmpty, "grant on \(grantDay) Sep")
        }
    }

    func testTwoMissesUseTwoFreezes() {
        // 2-21 logged, 22 grace, 23 and 24 would each reset.
        let logged = BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21))
        let grants = [BT.grant(9, 10), BT.grant(9, 12)]
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: grants, consumptions: [], today: m(25), calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions.map(\.frozenDay), [BT.key(9, 23), BT.key(9, 24)])
        XCTAssertEqual(StreakEngine.status(loggedDays: logged, frozenDays: plan.frozenDays, today: m(25), calendar: calendar).length, 20)
        XCTAssertEqual(FreezeBalance.compute(grants: grants, consumptions: plan.newConsumptions).available, 0)
    }

    func testOneFreezeForTwoMissesCoversOnlyTheFirst() {
        let logged = BT.midnights(from: BT.date(9, 2), through: BT.date(9, 21))
        let plan = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: [], grants: [BT.grant(9, 10)], consumptions: [], today: m(25), calendar: calendar
        )
        XCTAssertEqual(plan.newConsumptions.map(\.frozenDay), [BT.key(9, 23)])
    }

    func testPlannerIsIdempotent() {
        let logged = designExampleLoggedDays()
        let grants = [BT.grant(9, 20)]
        let first = StreakFreezePlanner.plan(loggedDays: logged, frozenDays: [], grants: grants, consumptions: [], today: m(25), calendar: calendar)
        let second = StreakFreezePlanner.plan(
            loggedDays: logged, frozenDays: first.frozenDays, grants: grants, consumptions: first.newConsumptions, today: m(25), calendar: calendar
        )
        XCTAssertTrue(second.newConsumptions.isEmpty)
        XCTAssertEqual(second.frozenDays, first.frozenDays)
        XCTAssertEqual(StreakFreezePlanner.frozenDays(from: first.newConsumptions, calendar: calendar), [m(24)])
    }

    // MARK: - Balance (design D4)

    func testBalanceIsCappedAtTwoAndCountsOverflow() {
        let grants = [BT.grant(9, 1), BT.grant(9, 5), BT.grant(9, 9)]
        let full = FreezeBalance.compute(grants: grants, consumptions: [])
        XCTAssertEqual(full.available, 2)
        XCTAssertEqual(full.wasted, 1)
        XCTAssertEqual(full.earned, 3)
        XCTAssertEqual(full.lastWastedDay, BT.key(9, 9))

        let used = [StreakFreezeStore.Consumption(frozenDay: BT.key(9, 10), consumedOn: BT.key(9, 11), protectedLength: 5)]
        let refilled = FreezeBalance.compute(grants: grants + [BT.grant(9, 12)], consumptions: used)
        XCTAssertEqual(refilled.available, 2, "2 -> 1 after the freeze, back to 2")
        XCTAssertEqual(refilled.wasted, 1)
        XCTAssertEqual(refilled.used, 1)
    }

    func testBalanceNeverNegativeAndIgnoresDaylessGrants() {
        let used = [StreakFreezeStore.Consumption(frozenDay: BT.key(9, 10), consumedOn: nil, protectedLength: nil)]
        let dayless = RewardLedger.FreezeGrant(key: "boss.freeze.x", day: "")
        let result = FreezeBalance.compute(grants: [dayless], consumptions: used)
        XCTAssertEqual(result.available, 0)
        XCTAssertEqual(result.earned, 0)
    }

    func testAvailabilityForAMissCountsOnlyEarlierGrants() {
        let grants = [BT.grant(9, 20), BT.grant(9, 26)]
        XCTAssertEqual(FreezeBalance.available(forMissOn: BT.key(9, 24), grants: grants, consumptions: []), 1)
        XCTAssertEqual(FreezeBalance.available(forMissOn: BT.key(9, 20), grants: grants, consumptions: []), 0, "same-day grant")
        let spentLater = [StreakFreezeStore.Consumption(frozenDay: BT.key(9, 25), consumedOn: BT.key(9, 26), protectedLength: 9)]
        XCTAssertEqual(FreezeBalance.available(forMissOn: BT.key(9, 24), grants: grants, consumptions: spentLater), 0,
                       "the one earlier freeze is already spent on a later day")
    }

    // MARK: - Store

    func testStoreRecordsPersistsAndIgnoresDuplicates() async throws {
        let directory = BT.tempDirectory("freeze-store")
        let store = StreakFreezeStore(directory: directory)
        let consumption = StreakFreezeStore.Consumption(frozenDay: BT.key(9, 24), consumedOn: BT.key(9, 25), protectedLength: 21)
        try await store.record([consumption])
        try await store.record([consumption])
        let reloaded = await StreakFreezeStore(directory: directory).load()
        XCTAssertTrue(reloaded.isReadable)
        XCTAssertEqual(reloaded.consumptions, [consumption])
    }

    func testStoreRecordReturnsOnlyTheConsumptionsItAdded() async throws {
        // Two overlapping planner runs can plan the same freeze; only the
        // run that actually recorded it may announce it.
        let store = StreakFreezeStore(directory: BT.tempDirectory("freeze-store"))
        let thursday = StreakFreezeStore.Consumption(frozenDay: BT.key(9, 24), consumedOn: BT.key(9, 25), protectedLength: 21)
        let friday = StreakFreezeStore.Consumption(frozenDay: BT.key(9, 25), consumedOn: BT.key(9, 26), protectedLength: 21)
        let first = try await store.record([thursday])
        XCTAssertEqual(first, [thursday])
        let second = try await store.record([thursday])
        XCTAssertTrue(second.isEmpty, "already recorded by an earlier run")
        let third = try await store.record([thursday, friday])
        XCTAssertEqual(third, [friday])
    }

    func testStoreSaveBeforeLoadKeepsExistingEntries() async throws {
        let directory = BT.tempDirectory("freeze-store")
        let first = StreakFreezeStore.Consumption(frozenDay: BT.key(9, 10), consumedOn: BT.key(9, 11), protectedLength: 4)
        try await StreakFreezeStore(directory: directory).record([first])
        // A fresh instance that never loaded explicitly must load before writing.
        let second = StreakFreezeStore.Consumption(frozenDay: BT.key(9, 24), consumedOn: BT.key(9, 25), protectedLength: 21)
        try await StreakFreezeStore(directory: directory).record([second])
        let all = await StreakFreezeStore(directory: directory).consumptions()
        XCTAssertEqual(all, [first, second])
    }

    func testUndecodableStoreFileIsQuarantinedNotFatal() async throws {
        let directory = BT.tempDirectory("freeze-store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("streak-freezes.json"))
        let store = StreakFreezeStore(directory: directory)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isReadable)
        XCTAssertTrue(loaded.consumptions.isEmpty)
        try await store.record([StreakFreezeStore.Consumption(frozenDay: BT.key(9, 1), consumedOn: nil, protectedLength: nil)])
        let reloaded = await StreakFreezeStore(directory: directory).consumptions()
        XCTAssertEqual(reloaded.count, 1)
    }

    // MARK: - End to end through the boss feature

    func testFeatureAppliesFreezeOnceAndAnnouncesIt() async {
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        let logged = designExampleLoggedDays()
        let grants = [BT.grant(9, 20, "boss.freeze")]

        let first = await feature.applyStreakFreezes(loggedDays: logged, grants: grants, today: m(25), calendar: calendar)
        XCTAssertEqual(first.frozenDays, [m(24)])
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(first.moments.first?.style, .freeze)
        XCTAssertEqual(first.balance.available, 0)
        XCTAssertEqual(StreakEngine.status(loggedDays: logged, frozenDays: first.frozenDays, today: m(25), calendar: calendar).length, 21)

        let second = await feature.applyStreakFreezes(loggedDays: logged, grants: grants, today: m(25), calendar: calendar)
        XCTAssertEqual(second.frozenDays, [m(24)])
        XCTAssertTrue(second.moments.isEmpty, "a freeze is announced once")
    }

    func testFeatureWithoutGrantsNeverFreezes() async {
        let feature = WeeklyBossFeature(directory: BT.tempDirectory())
        let run = await feature.applyStreakFreezes(loggedDays: designExampleLoggedDays(), grants: [], today: m(25), calendar: calendar)
        XCTAssertTrue(run.frozenDays.isEmpty)
        XCTAssertTrue(run.moments.isEmpty)
        XCTAssertEqual(run.balance, .zero)
    }
}
