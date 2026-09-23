// GarminHealthCacheTests.swift
//
// task 2.4 (sync-weight-hydration-with-garmin): the per-day cache of
// Garmin weigh-ins / water totals the cards render from first, and the
// refresh plan deciding what to re-read (design.md D2: the long history at
// most once a day). Real `GarminHealthCacheStore` instances on a unique
// temp file per test, per LogEntryCoordinatorTests' convention -- never
// mocked.

import XCTest
@testable import FoodLogCore
import GarminKit

final class GarminHealthCacheTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_790_150_000) // 2026-09-23 CEST

    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("garmin-health-cache-test-\(UUID().uuidString).json")
    }

    private func sample(_ pk: Int, day: String, kg: Double = 83.9) -> GarminWeighIn {
        GarminWeighIn(samplePk: pk, calendarDate: day, weightGrams: kg * 1000, timestampGMT: Double(pk))
    }

    // MARK: - Store

    func testWeighInsSurviveAFreshStoreInstance() async throws {
        let url = makeURL()
        let store = GarminHealthCacheStore(fileURL: url)
        try await store.storeWeighIns([sample(1, day: "2026-09-23")], coveringDays: ["2026-09-22", "2026-09-23"], fetchedAt: now, isFullRange: true)

        let reloaded = await GarminHealthCacheStore(fileURL: url).current()

        XCTAssertEqual(reloaded.allWeighIns.map(\.samplePk), [1])
        XCTAssertEqual(reloaded.weighInDays["2026-09-22"]?.weighIns, [], "a covered day with nothing is recorded as empty, not unknown")
        XCTAssertEqual(reloaded.weighInDayFetchTimes.keys.sorted(), ["2026-09-22", "2026-09-23"])
        XCTAssertNotNil(reloaded.lastFullWeightRangeFetchAt)
    }

    func testAReReadReplacesTheDaySoAWeighInDeletedInConnectDisappears() async throws {
        let store = GarminHealthCacheStore(fileURL: makeURL())
        try await store.storeWeighIns([sample(1, day: "2026-09-23"), sample(2, day: "2026-09-23")], coveringDays: ["2026-09-23"], fetchedAt: now, isFullRange: false)

        try await store.storeWeighIns([sample(2, day: "2026-09-23")], coveringDays: ["2026-09-23"], fetchedAt: now.addingTimeInterval(60), isFullRange: false)

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.allWeighIns.map(\.samplePk), [2])
        XCTAssertNil(snapshot.lastFullWeightRangeFetchAt, "a short read doesn't count as the daily full read")
    }

    func testAShortReadLeavesOlderCachedDaysAlone() async throws {
        let store = GarminHealthCacheStore(fileURL: makeURL())
        try await store.storeWeighIns([sample(1, day: "2026-09-10")], coveringDays: ["2026-09-10"], fetchedAt: now, isFullRange: true)

        try await store.storeWeighIns([], coveringDays: ["2026-09-22", "2026-09-23"], fetchedAt: now, isFullRange: false)

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.allWeighIns.map(\.samplePk), [1])
    }

    func testHydrationAndGoalAreCached() async throws {
        let url = makeURL()
        let store = GarminHealthCacheStore(fileURL: url)
        try await store.storeHydration(HydrationDaily(calendarDate: "2026-09-23", valueInML: 1500, goalInML: 2800), for: "2026-09-23", fetchedAt: now)
        try await store.storeWeightGoal(CachedWeightGoal(startingWeightGrams: 80_400, targetWeightGrams: 76_000, weightChangeRateGramsPerWeek: 250, weightChangeType: "LOSS", fetchedAt: now))

        let reloaded = await GarminHealthCacheStore(fileURL: url).current()

        XCTAssertEqual(reloaded.hydrationDays["2026-09-23"]?.daily.valueInML, 1500)
        XCTAssertEqual(reloaded.hydrationDays["2026-09-23"]?.daily.goalInML, 2800)
        XCTAssertEqual(reloaded.weightGoal?.targetWeightGrams, 76_000)
    }

    func testOnlyTheNewestHydrationDaysAreKept() async throws {
        let store = GarminHealthCacheStore(fileURL: makeURL())
        for day in 1...20 {
            let key = String(format: "2026-09-%02d", day)
            try await store.storeHydration(HydrationDaily(calendarDate: key, valueInML: 100), for: key, fetchedAt: now)
        }
        let snapshot = await store.current()
        XCTAssertEqual(snapshot.hydrationDays.count, GarminHealthCacheStore.hydrationDaysKept)
        XCTAssertNotNil(snapshot.hydrationDays["2026-09-20"])
        XCTAssertNil(snapshot.hydrationDays["2026-09-01"])
    }

    func testAnEmptyOrPartialCacheFileStillDecodes() async throws {
        let url = makeURL()
        try Data(#"{"hydrationDays":{}}"#.utf8).write(to: url)
        let snapshot = await GarminHealthCacheStore(fileURL: url).current()
        XCTAssertTrue(snapshot.weighInDays.isEmpty)
        XCTAssertNil(snapshot.weightGoal)
    }

    // MARK: - Refresh plan (D2)

    func testFirstRefreshReadsTheWholeNinetyDayHistory() {
        let window = GarminHealthRefreshPlan.weighInWindow(lastFullRangeFetchAt: nil, now: now, force: false, calendar: calendar)
        XCTAssertTrue(window.isFullRange)
        XCTAssertEqual(window.days.count, 90)
        XCTAssertEqual(window.endDate, "2026-09-23")
        XCTAssertEqual(window.startDate, "2026-06-26")
    }

    func testWithinADayOfTheLastFullReadOnlyTodayAndYesterdayAreReRead() {
        let window = GarminHealthRefreshPlan.weighInWindow(lastFullRangeFetchAt: now.addingTimeInterval(-3_600), now: now, force: false, calendar: calendar)
        XCTAssertFalse(window.isFullRange)
        XCTAssertEqual(window.days, ["2026-09-22", "2026-09-23"])
    }

    func testAfterADayTheFullHistoryIsReReadOnce() {
        let window = GarminHealthRefreshPlan.weighInWindow(lastFullRangeFetchAt: now.addingTimeInterval(-25 * 3_600), now: now, force: false, calendar: calendar)
        XCTAssertTrue(window.isFullRange)
    }

    func testPullToRefreshForcesTheFullHistory() {
        let window = GarminHealthRefreshPlan.weighInWindow(lastFullRangeFetchAt: now, now: now, force: true, calendar: calendar)
        XCTAssertTrue(window.isFullRange)
    }

    func testDayStringsAreInclusiveAndOldestFirst() {
        let start = now.addingTimeInterval(-2 * 86_400)
        XCTAssertEqual(GarminHealthRefreshPlan.dayStrings(from: start, through: now, calendar: calendar), ["2026-09-21", "2026-09-22", "2026-09-23"])
    }
}
