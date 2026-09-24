// SportAndBodyFeatureTests.swift
//
// add-sport-and-body-achievements tasks 3.3 / design D4-D5/D7: the feature
// end to end over literal snapshots -- a fuelled run unlocks "Fuelled Up"
// once; counts accumulate beyond the signals window via the store (a fresh
// feature instance on the same directory); the small moment fires once per
// activity and not alongside a badge unlock; the trail-race scenario; the
// activities-unavailable path; and `SportBodyStore` caps, decode and
// quarantine. Real stores in a unique temp directory per test (never
// mocked).

import XCTest
import FoodLogCore
@testable import Gamification

final class SportAndBodyFeatureTests: XCTestCase {
    private typealias F = SportFixtures
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SportAndBodyFeatureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    /// A 60-minute run at 07:30 on `day` of September, fuelled by 45 g of
    /// porridge at 06:00 when `fuelled`.
    private func runDay(_ day: Int, id: String? = nil, fuelled: Bool = true) -> DaySignals {
        let run = F.activity(id ?? "run-\(day)", "running", start: F.at(2026, 9, day, 7, 30), minutes: 60)
        let entries = fuelled ? [F.entry("Ovesná kaše", at: F.at(2026, 9, day, 6, 0), carbs: 45)] : []
        return F.day(F.key(2026, 9, day), entries: entries, activities: [run])
    }

    // MARK: - Fuelled Up

    func testFuelledRunUnlocksFuelledUpOnce() async {
        let feature = SportAndBodyFeature(directory: directory)
        let snapshot = F.snapshot([runDay(20)], today: F.key(2026, 9, 20))
        let now = F.at(2026, 9, 20, 10)

        let first = await feature.update(F.context(snapshot, now: now))
        XCTAssertEqual(first.unlockBadgeIds, ["sport.fuel-1"])
        XCTAssertTrue(first.grants.isEmpty, "badges only -- XP is the host's achievementBonus")
        XCTAssertTrue(first.moments.isEmpty, "the badge moment celebrates the first fuelled run")

        let second = await feature.update(F.context(snapshot, now: now, unlocked: ["sport.fuel-1"]))
        XCTAssertTrue(second.unlockBadgeIds.isEmpty)
        XCTAssertTrue(second.moments.isEmpty, "the same activity never counts twice")
        let counts = await feature.lifetimeCounts()
        XCTAssertEqual(counts.fuelled, 1)
    }

    func testSmallMomentOncePerActivityWhenNoBadgeUnlocks() async throws {
        let feature = SportAndBodyFeature(directory: directory)
        let unlocked: Set<String> = ["sport.fuel-1"]
        let snapshot = F.snapshot([runDay(20)], today: F.key(2026, 9, 20))
        let now = F.at(2026, 9, 20, 10)

        let first = await feature.update(F.context(snapshot, now: now, unlocked: unlocked))
        let moment = try XCTUnwrap(first.moments.first)
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(moment.featureId, SportAndBodyFeature.id)
        XCTAssertEqual(moment.style, .celebration)
        XCTAssertEqual(moment.xpAwarded, 0)
        XCTAssertTrue(moment.message.contains("45"), moment.message)
        XCTAssertTrue(moment.message.contains("90"), moment.message)

        let again = await feature.update(F.context(snapshot, now: now, unlocked: unlocked))
        XCTAssertTrue(again.moments.isEmpty)
    }

    func testNoMomentForAnOldBacklogActivity() async {
        let feature = SportAndBodyFeature(directory: directory)
        let snapshot = F.snapshot([runDay(10)], today: F.key(2026, 9, 20))
        let update = await feature.update(F.context(snapshot, now: F.at(2026, 9, 20, 10), unlocked: ["sport.fuel-1"]))
        XCTAssertTrue(update.moments.isEmpty)
        let counts = await feature.lifetimeCounts()
        XCTAssertEqual(counts.fuelled, 1, "still counted, just not celebrated")
    }

    // MARK: - Counts beyond the window

    func testCountsAccumulateBeyondTheWindowViaTheStore() async {
        // August: five fuelled runs; the window then moves on.
        let august = SportAndBodyFeature(directory: directory)
        let augustDays = (1...5).map { day -> DaySignals in
            let run = F.activity("aug-\(day)", "running", start: F.at(2026, 8, day, 7, 30), minutes: 60)
            let porridge = F.entry("Ovesná kaše", at: F.at(2026, 8, day, 6, 0), carbs: 45)
            return F.day(F.key(2026, 8, day), entries: [porridge], activities: [run])
        }
        _ = await august.update(F.context(F.snapshot(augustDays, today: F.key(2026, 8, 5)), now: F.at(2026, 8, 5, 10)))

        // September, a fresh process: five other runs in a window that no
        // longer contains August.
        let september = SportAndBodyFeature(directory: directory)
        let septemberDays = (20...24).map { runDay($0) }
        let update = await september.update(F.context(
            F.snapshot(septemberDays, today: F.key(2026, 9, 24)),
            now: F.at(2026, 9, 24, 10),
            unlocked: ["sport.fuel-1"]
        ))
        XCTAssertTrue(update.unlockBadgeIds.contains("sport.fuel-10"))
        let counts = await september.lifetimeCounts()
        XCTAssertEqual(counts.fuelled, 10)
        let month = await september.monthCounts(now: F.at(2026, 9, 24, 10), calendar: F.calendar)
        XCTAssertEqual(month, SportMonthCounts(fuelled: 5, recovered: 0))
        XCTAssertEqual(update.summary?.symbol, "figure.run")
    }

    // MARK: - Trail race

    func testTrailRaceScenario() async {
        // A day tagged "race" with a 4-hour trail run and 3 entries during it.
        let start = F.at(2026, 9, 19, 8)
        let race = F.activity("race", "trail_running", start: start, minutes: 240)
        let gels = [40.0, 100.0, 170.0].map { F.entry("Energetický gel", at: start.addingTimeInterval($0 * 60), carbs: 25) }
        let day = F.day(F.key(2026, 9, 19), entries: gels, activities: [race], noteTags: [.race])
        let feature = SportAndBodyFeature(directory: directory)

        let update = await feature.update(F.context(F.snapshot([day], today: F.key(2026, 9, 19)), now: F.at(2026, 9, 19, 13)))
        for id in ["sport.race-day-1", SportBodyCatalog.gelGuruId, SportBodyCatalog.longHaulId] {
            XCTAssertTrue(update.unlockBadgeIds.contains(id), id)
        }
        let recent = await feature.recentActivities()
        XCTAssertEqual(recent.map(\.id), ["race"])
        XCTAssertEqual(recent.first?.duringEntries.count, 3)
    }

    // MARK: - Activities unavailable

    func testActivitiesUnavailableStillUnlocksWeightAndFasting() async {
        // No day ever had its activities read (route broken / standalone).
        let days = [
            F.day(F.key(2026, 9, 18), fasting: .kept),
            F.day(F.key(2026, 9, 19), fasting: .kept),
            F.day(F.key(2026, 9, 20), weighInKg: 80.9, fasting: .kept),
        ]
        let snapshot = F.snapshot(days, today: F.key(2026, 9, 20), weightGoal: WeightGoalSignal(startKg: 82, targetKg: 76))
        let feature = SportAndBodyFeature(directory: directory)

        let update = await feature.update(F.context(snapshot, now: F.at(2026, 9, 20, 20)))
        XCTAssertEqual(Set(update.unlockBadgeIds), [SportBodyCatalog.firstKiloId, "body.fast-3"])
        XCTAssertFalse(update.unlockBadgeIds.contains { $0.hasPrefix("sport.") })
        XCTAssertTrue(update.moments.isEmpty)
        XCTAssertNotNil(update.summary, "nothing is shown as failed")
        let available = await feature.activitiesAvailable()
        XCTAssertFalse(available)
        let progress = await feature.bodyProgress()
        XCTAssertEqual(progress.fastingStreak, 3)
        XCTAssertEqual(progress.nextFastingTier?.id, "body.fast-7")
        XCTAssertEqual(progress.weight?.latestKg, 80.9)
    }

    func testEveryRequestedIdIsDeclared() async {
        let feature = SportAndBodyFeature(directory: directory)
        let declared = Set(feature.badges.map(\.id))
        let start = F.at(2026, 9, 19, 8)
        let race = F.activity("race", "trail_running", start: start, minutes: 240)
        let gels = [40.0, 100.0, 170.0].map { F.entry("Energetický gel", at: start.addingTimeInterval($0 * 60), carbs: 25) }
        let snapshot = F.snapshot([
            runDay(17),
            F.day(F.key(2026, 9, 19), entries: gels, activities: [race], weighInKg: 76, noteTags: [.race]),
        ], today: F.key(2026, 9, 20), weightGoal: WeightGoalSignal(startKg: 82, targetKg: 76))
        let update = await feature.update(F.context(snapshot, now: F.at(2026, 9, 20, 10)))
        XCTAssertFalse(update.unlockBadgeIds.isEmpty)
        XCTAssertTrue(Set(update.unlockBadgeIds).isSubset(of: declared), "\(update.unlockBadgeIds)")
    }

    // MARK: - Catalog

    func testCatalogIdsAreUniqueNamespacedAndFeatureOwned() {
        let ids = SportBodyCatalog.badges.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 23)
        for badge in SportBodyCatalog.badges {
            XCTAssertTrue(badge.id.hasPrefix("sport.") || badge.id.hasPrefix("body."), badge.id)
            XCTAssertEqual(badge.featureId, SportAndBodyFeature.id)
            XCTAssertEqual(badge.condition, .featureEvaluated)
            XCTAssertNotNil(badge.rarityOverride, badge.id)
        }
        let tierIds = (SportBodyCatalog.fuelTiers + SportBodyCatalog.recoveryTiers + SportBodyCatalog.earnedTiers
            + SportBodyCatalog.raceDayTiers + SportBodyCatalog.fastingTiers).map(\.id)
        let singles = [SportBodyCatalog.doubleDayId, SportBodyCatalog.gelGuruId, SportBodyCatalog.longHaulId, SportBodyCatalog.carbLoaderId]
            + SportBodyCatalog.weightMilestoneIds
        XCTAssertEqual(Set(tierIds + singles), Set(ids))
        XCTAssertEqual(SportBodyCatalog.badge(id: SportBodyCatalog.steadyId)?.rarity, .legendary)
    }

    // MARK: - Store

    func testStoreCapsEachList() async throws {
        let store = SportBodyStore(directory: directory)
        for index in 0...SportBodyStore.cap {
            await store.addEarnedDay(String(format: "d%05d", index))
        }
        let days = await store.earnedDays()
        XCTAssertEqual(days.count, SportBodyStore.cap)
        XCTAssertEqual(days.first, "d00001", "the oldest is dropped")
        try await store.save()
        let reopened = await SportBodyStore(directory: directory).earnedDays()
        XCTAssertEqual(reopened.count, SportBodyStore.cap)
    }

    func testStoreRoundTripsAndDedupes() async throws {
        let store = SportBodyStore(directory: directory)
        let isNew = await store.addFuelled(activityId: "a1", day: "2026-09-20")
        let isDuplicate = await store.addFuelled(activityId: "a1", day: "2026-09-20")
        XCTAssertTrue(isNew)
        XCTAssertFalse(isDuplicate)
        await store.addRecovered(activityId: "a2", day: "2026-08-31")
        await store.addRaceDay("2026-09-19")
        try await store.save()

        let reopened = SportBodyStore(directory: directory)
        let fuelled = await reopened.fuelledActivityIds()
        let races = await reopened.raceDays()
        let september = await reopened.counts(monthPrefix: "2026-09")
        XCTAssertEqual(fuelled, ["a1"])
        XCTAssertEqual(races, ["2026-09-19"])
        XCTAssertEqual(september.fuelled, 1)
        XCTAssertEqual(september.recovered, 0)
    }

    func testStoreSaveBeforeAnyReadKeepsExistingData() async throws {
        let first = SportBodyStore(directory: directory)
        await first.addRaceDay("2026-09-01")
        try await first.save()

        // A fresh instance saving without an explicit read first.
        let second = SportBodyStore(directory: directory)
        try await second.save()
        await second.addRaceDay("2026-09-19")
        try await second.save()
        let races = await SportBodyStore(directory: directory).raceDays()
        XCTAssertEqual(races, ["2026-09-01", "2026-09-19"])
    }

    func testStoreDecodesMissingFieldsAndQuarantinesGarbage() async throws {
        let url = directory.appendingPathComponent("sport.json")
        try Data("{}".utf8).write(to: url)
        let empty = await SportBodyStore(directory: directory).fuelledActivityIds()
        XCTAssertTrue(empty.isEmpty)

        try Data("not json".utf8).write(to: url)
        let store = SportBodyStore(directory: directory)
        let afterGarbage = await store.raceDays()
        XCTAssertTrue(afterGarbage.isEmpty)
        await store.addRaceDay("2026-09-19")
        try await store.save()
        let reopened = await SportBodyStore(directory: directory).raceDays()
        XCTAssertEqual(reopened, ["2026-09-19"])
    }
}
