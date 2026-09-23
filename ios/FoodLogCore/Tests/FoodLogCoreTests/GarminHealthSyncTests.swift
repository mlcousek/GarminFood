// GarminHealthSyncTests.swift
//
// task 3.1's testable core (sync-weight-hydration-with-garmin): one Garmin
// refresh reads weigh-ins, today's water and the weight plan, caches every
// success, keeps the last good values on a failure, and separates an auth
// failure (loud) from everything else (quiet). A real
// `GarminHealthCacheStore` on a unique temp file per test, per
// LogEntryCoordinatorTests' convention; only the Garmin READER is faked,
// since the real one is the network.

import XCTest
@testable import FoodLogCore
import GarminKit

/// Records what it was asked and answers from canned values (or throws).
private actor FakeHealthReader: GarminHealthReading {
    var weighIns: [GarminWeighIn] = []
    var hydration = HydrationDaily(calendarDate: "2026-09-23", valueInML: 1500, goalInML: 2800)
    var plan = GarminWeightPlan(startingWeightGrams: 80_400, targetWeightGrams: 76_000, weightChangeRateGramsPerWeek: 250, weightChangeType: "LOSS")
    var weighInError: Error?
    var hydrationError: Error?
    var planError: Error?

    private(set) var weighInRanges: [(start: String, end: String)] = []
    private(set) var planReads = 0

    func configure(weighIns: [GarminWeighIn]? = nil, weighInError: Error? = nil, hydrationError: Error? = nil, planError: Error? = nil) {
        if let weighIns { self.weighIns = weighIns }
        self.weighInError = weighInError
        self.hydrationError = hydrationError
        self.planError = planError
    }

    func weighInSamples(startDate: String, endDate: String) async throws -> [GarminWeighIn] {
        weighInRanges.append((start: startDate, end: endDate))
        if let weighInError { throw weighInError }
        return weighIns
    }

    func hydrationDaily(date: String) async throws -> HydrationDaily {
        if let hydrationError { throw hydrationError }
        return hydration
    }

    func weightPlan(date: String) async throws -> GarminWeightPlan {
        planReads += 1
        if let planError { throw planError }
        return plan
    }
}

final class GarminHealthSyncTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// 2026-09-23 ~09:00 CEST.
    private let now = Date(timeIntervalSince1970: 1_790_150_000)

    private func makeCache() -> GarminHealthCacheStore {
        GarminHealthCacheStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garmin-health-sync-test-\(UUID().uuidString).json"))
    }

    private func sample(_ pk: Int, day: String = "2026-09-23", kg: Double = 83.9) -> GarminWeighIn {
        GarminWeighIn(samplePk: pk, calendarDate: day, weightGrams: kg * 1000, timestampGMT: 1_790_149_291_732)
    }

    func testASuccessfulRefreshCachesWeighInsWaterAndGoal() async throws {
        let cache = makeCache()
        let reader = FakeHealthReader()
        await reader.configure(weighIns: [sample(1)])

        let outcome = await GarminHealthSync(cache: cache, reader: reader).refresh(now: now, calendar: calendar)

        XCTAssertEqual(outcome, GarminHealthRefreshOutcome())
        let snapshot = await cache.current()
        XCTAssertEqual(snapshot.allWeighIns.map(\.samplePk), [1])
        XCTAssertEqual(snapshot.hydrationDays["2026-09-23"]?.daily.valueInML, 1500)
        XCTAssertEqual(snapshot.hydrationDays["2026-09-23"]?.fetchedAt, now)
        XCTAssertEqual(snapshot.weightGoal?.targetWeightGrams, 76_000)
        XCTAssertEqual(snapshot.weightGoal?.weightChangeType, "LOSS")
        let ranges = await reader.weighInRanges
        XCTAssertEqual(ranges.first?.end, "2026-09-23")
        XCTAssertEqual(ranges.first?.start, "2026-06-26", "first refresh reads the full 90-day history")
    }

    func testAFailedWeighInReadKeepsTheLastGoodValuesAndIsReportedQuietly() async throws {
        let cache = makeCache()
        let reader = FakeHealthReader()
        await reader.configure(weighIns: [sample(1)])
        let sync = GarminHealthSync(cache: cache, reader: reader)
        _ = await sync.refresh(now: now, calendar: calendar)

        await reader.configure(weighInError: GarminClientError.httpError(statusCode: 500, body: nil))
        let outcome = await sync.refresh(now: now.addingTimeInterval(60), force: true, calendar: calendar)

        XCTAssertTrue(outcome.weighInsFailed)
        XCTAssertTrue(outcome.weightFailed)
        XCTAssertFalse(outcome.hydrationFailed)
        XCTAssertNil(outcome.authError, "a server error is not an auth problem")
        let snapshot = await cache.current()
        XCTAssertEqual(snapshot.allWeighIns.map(\.samplePk), [1], "the last good weigh-ins are still there to render")
        XCTAssertEqual(snapshot.weighInDays["2026-09-23"]?.fetchedAt, now, "a failed read doesn't pretend Garmin was read")
    }

    func testAnExpiredSignInIsSurfacedAsAnAuthError() async {
        let reader = FakeHealthReader()
        await reader.configure(
            weighInError: GarminAuthError.longLivedTokenExpired,
            hydrationError: GarminAuthError.longLivedTokenExpired,
            planError: GarminAuthError.longLivedTokenExpired
        )

        let outcome = await GarminHealthSync(cache: makeCache(), reader: reader).refresh(now: now, calendar: calendar)

        XCTAssertEqual(outcome.authError, .longLivedTokenExpired)
        XCTAssertTrue(outcome.weighInsFailed && outcome.hydrationFailed && outcome.goalFailed)
    }

    func testTheWeightPlanIsNotReReadWhileFreshUnlessForced() async {
        let reader = FakeHealthReader()
        let sync = GarminHealthSync(cache: makeCache(), reader: reader)

        _ = await sync.refresh(now: now, calendar: calendar)
        _ = await sync.refresh(now: now.addingTimeInterval(600), calendar: calendar)
        let afterSecond = await reader.planReads
        XCTAssertEqual(afterSecond, 1, "a fresh plan is served from the cache")

        _ = await sync.refresh(now: now.addingTimeInterval(700), force: true, calendar: calendar)
        let afterForced = await reader.planReads
        XCTAssertEqual(afterForced, 2, "pull-to-refresh re-reads it")
    }

    func testASecondRefreshTheSameDayReadsOnlyTodayAndYesterday() async {
        let reader = FakeHealthReader()
        let sync = GarminHealthSync(cache: makeCache(), reader: reader)

        _ = await sync.refresh(now: now, calendar: calendar)
        _ = await sync.refresh(now: now.addingTimeInterval(3_600), calendar: calendar)

        let ranges = await reader.weighInRanges
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges.last?.start, "2026-09-22")
        XCTAssertEqual(ranges.last?.end, "2026-09-23")
    }

    func testAWeighInDeletedInConnectDisappearsOnTheNextRead() async {
        let cache = makeCache()
        let reader = FakeHealthReader()
        await reader.configure(weighIns: [sample(1), sample(2)])
        let sync = GarminHealthSync(cache: cache, reader: reader)
        _ = await sync.refresh(now: now, calendar: calendar)

        await reader.configure(weighIns: [sample(2)])
        _ = await sync.refresh(now: now.addingTimeInterval(60), calendar: calendar)

        let snapshot = await cache.current()
        XCTAssertEqual(snapshot.allWeighIns.map(\.samplePk), [2])
    }
}
