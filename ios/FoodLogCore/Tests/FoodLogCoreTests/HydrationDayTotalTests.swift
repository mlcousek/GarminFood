// HydrationDayTotalTests.swift
//
// design.md D4 (sync-weight-hydration-with-garmin): the water total is
// Garmin's `valueInML` plus whatever the app logged that Garmin can't
// include yet -- and never counts a delivered drink twice. Mirrors the
// hydration-tracking spec's scenarios ("Water logged in Garmin Connect
// counts", "Pending local drink counts once", "Remove a delivered drink").

import XCTest
@testable import FoodLogCore
import GarminKit

final class HydrationDayTotalTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// 2026-09-23 around 09:00 CEST.
    private let today = Date(timeIntervalSince1970: 1_790_150_000)

    private func drink(_ ml: Double, state: OutboxEntryState, at date: Date? = nil, deliveredAt: Date? = nil) -> HydrationOutboxEntry {
        HydrationOutboxEntry(valueInML: ml, loggedAt: date ?? today, state: state, deliveredAt: deliveredAt)
    }

    private func total(garmin: Double?, fetchedAt: Date?, _ entries: [HydrationOutboxEntry]) -> Double {
        HydrationDayTotal.total(
            garminDaily: garmin.map { HydrationDaily(calendarDate: "2026-09-23", valueInML: $0, goalInML: 2800) },
            garminFetchedAt: fetchedAt,
            outboxEntries: entries,
            on: today,
            calendar: calendar
        )
    }

    func testWaterLoggedInConnectCounts() {
        XCTAssertEqual(total(garmin: 1500, fetchedAt: today, []), 1500)
    }

    func testAPendingDrinkCountsOnceBeforeAndAfterDelivery() {
        let fetchedBefore = today.addingTimeInterval(-60)
        XCTAssertEqual(total(garmin: 1500, fetchedAt: fetchedBefore, [drink(250, state: .pending)]), 1750, "pending: Garmin's 1500 + 250")

        // Delivered, but Garmin not re-read since: still 1500 + 250.
        let deliveredAt = today.addingTimeInterval(10)
        XCTAssertEqual(total(garmin: 1500, fetchedAt: fetchedBefore, [drink(250, state: .sent, deliveredAt: deliveredAt)]), 1750)

        // Garmin re-read after the delivery reports 1750, which includes it.
        XCTAssertEqual(total(garmin: 1750, fetchedAt: deliveredAt.addingTimeInterval(30), [drink(250, state: .sent, deliveredAt: deliveredAt)]), 1750, "never counted twice")
    }

    func testADrinkDeliveredByAnOlderBuildIsAssumedIncluded() {
        XCTAssertEqual(total(garmin: 1750, fetchedAt: today, [drink(250, state: .sent, deliveredAt: nil)]), 1750)
    }

    func testAFailedDrinkStillCountsBecauseTheUserDrankIt() {
        XCTAssertEqual(total(garmin: 1500, fetchedAt: today, [drink(250, state: .failed)]), 1750)
    }

    func testAQueuedCorrectionLowersTheTotalAtOnce() {
        XCTAssertEqual(total(garmin: 1750, fetchedAt: today, [drink(-250, state: .pending)]), 1500)
    }

    func testOtherDaysDontCount() {
        let yesterday = today.addingTimeInterval(-86_400)
        XCTAssertEqual(total(garmin: 1500, fetchedAt: today, [drink(500, state: .pending, at: yesterday)]), 1500)
    }

    func testWithoutAnyGarminReadTheLocalEntriesAreTheTotal() {
        let entries = [drink(250, state: .sent), drink(500, state: .pending), drink(-100, state: .pending)]
        XCTAssertEqual(total(garmin: nil, fetchedAt: nil, entries), 650)
    }

    func testAGarminDayWithNothingLoggedCountsAsZero() {
        let result = HydrationDayTotal.total(
            garminDaily: HydrationDaily(calendarDate: "2026-09-23", valueInML: nil, goalInML: 2800),
            garminFetchedAt: today,
            outboxEntries: [drink(250, state: .pending)],
            on: today,
            calendar: calendar
        )
        XCTAssertEqual(result, 250)
    }

    func testTheTotalNeverGoesNegative() {
        XCTAssertEqual(total(garmin: 100, fetchedAt: today, [drink(-250, state: .pending)]), 0)
    }

    /// 2026-09-23 review fix: a correction Garmin gave up on was still
    /// subtracted, so the total diverged from Garmin for good.
    func testAFailedCorrectionIsNotApplied() {
        XCTAssertEqual(total(garmin: 1750, fetchedAt: today, [drink(-250, state: .failed)]), 1750)
        XCTAssertEqual(total(garmin: 1750, fetchedAt: today, [drink(-250, state: .pending)]), 1500, "a pending one still counts at once")
    }

    /// 2026-09-23 race fix: a drink removed while its delivery is in flight
    /// counts for nothing until the drain settles it.
    func testADrinkRemovedMidFlightCountsForNothingUntilSettled() {
        let withdrawn = HydrationOutboxEntry(valueInML: 500, loggedAt: today, state: .pending, removalRequested: true)
        XCTAssertEqual(total(garmin: 1500, fetchedAt: today.addingTimeInterval(-60), [withdrawn]), 1500)
        XCTAssertEqual(total(garmin: nil, fetchedAt: nil, [withdrawn]), 0, "same without any Garmin read")

        // Settled as delivered: it counts again, and so does its correction.
        let deliveredAt = today.addingTimeInterval(10)
        let sent = HydrationOutboxEntry(valueInML: 500, loggedAt: today, state: .sent, deliveredAt: deliveredAt, removalRequested: true)
        let correction = drink(-500, state: .pending)
        XCTAssertEqual(total(garmin: 2000, fetchedAt: deliveredAt.addingTimeInterval(30), [sent, correction]), 1500, "Garmin's read includes the 500; the queued -500 takes it back out")
    }
}
