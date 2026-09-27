// WaterDayTotalsTests.swift
//
// Review note 17: every screen reads one per-day water total. In Garmin mode
// that's Garmin's cached day total (plus drinks Garmin can't include yet),
// so water logged on the watch counts on Trends and in the streak exactly as
// it does on Today; standalone sums this phone's drinks. The streak treats
// an unfinished today as in progress. The Garmin snapshot comes from a real
// `GarminHealthCacheStore` on a temp file, as the app's `HydrationLoader`
// reads it.

import XCTest
@testable import FoodLogCore
import GarminKit

final class WaterDayTotalsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// 2026-09-23 around 09:00 CEST.
    private let today = Date(timeIntervalSince1970: 1_790_150_000)

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    private func key(_ date: Date) -> String {
        NutritionDate.string(from: date, calendar: calendar)
    }

    /// A real cache store holding Garmin's totals for the given days, read
    /// back the way `HydrationLoader.refresh()` does.
    private func makeSnapshot(garminML: [Int: Double]) async throws -> GarminHealthSnapshot {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("water-day-totals-\(UUID().uuidString).json")
        let store = GarminHealthCacheStore(fileURL: url)
        for (offset, ml) in garminML {
            let date = day(offset)
            // Read at the end of that day, after every local drink was delivered.
            let fetchedAt = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date)!
            try await store.storeHydration(HydrationDaily(calendarDate: key(date), valueInML: ml, goalInML: 2000), for: key(date), fetchedAt: fetchedAt)
        }
        return await store.current()
    }

    private func delivered(_ ml: Double, dayOffset: Int) -> HydrationOutboxEntry {
        let date = day(dayOffset)
        return HydrationOutboxEntry(valueInML: ml, loggedAt: date, state: .sent, deliveredAt: date.addingTimeInterval(60))
    }

    func testGarminModeUsesGarminsTotalForPastDaysToo() async throws {
        // Yesterday: 500 ml in this app, 2 500 ml in Garmin (watch + app).
        let snapshot = try await makeSnapshot(garminML: [-1: 2500])
        let totals = WaterDayTotals(
            isStandalone: false,
            snapshot: snapshot,
            outboxEntries: [delivered(500, dayOffset: -1)],
            localEntries: [HydrationEntry(valueInML: 500, loggedAt: day(-1))],
            calendar: calendar
        )

        XCTAssertEqual(totals.total(on: day(-1)), 2500, "Garmin's total, not just this app's drinks")
    }

    func testTodayMatchesWhatTodayShows() async throws {
        let snapshot = try await makeSnapshot(garminML: [0: 1200])
        let pending = HydrationOutboxEntry(valueInML: 300, loggedAt: today, state: .pending)
        let totals = WaterDayTotals(isStandalone: false, snapshot: snapshot, outboxEntries: [pending], localEntries: [], calendar: calendar)

        XCTAssertEqual(
            totals.total(on: today),
            WeightAndWaterOverview.waterTotalML(snapshot: snapshot, outboxEntries: [pending], on: today, calendar: calendar)
        )
    }

    func testGarminModeDayNeverReadFallsBackToTheAppsOwnDrinks() async throws {
        let snapshot = try await makeSnapshot(garminML: [:])
        let totals = WaterDayTotals(
            isStandalone: false,
            snapshot: snapshot,
            outboxEntries: [delivered(750, dayOffset: -3)],
            localEntries: [HydrationEntry(valueInML: 750, loggedAt: day(-3))],
            calendar: calendar
        )

        XCTAssertEqual(totals.total(on: day(-3)), 750)
    }

    func testStandaloneIgnoresGarminAndSumsThisPhonesDrinks() async throws {
        let snapshot = try await makeSnapshot(garminML: [-1: 2500])
        let totals = WaterDayTotals(
            isStandalone: true,
            snapshot: snapshot,
            outboxEntries: [],
            localEntries: [HydrationEntry(valueInML: 400, loggedAt: day(-1)), HydrationEntry(valueInML: 600, loggedAt: day(-1))],
            calendar: calendar
        )

        XCTAssertEqual(totals.total(on: day(-1)), 1000)
    }

    func testStreakCountsGarminWaterAndTreatsTodayAsInProgress() async throws {
        // Only Garmin (the watch) knows yesterday and two days ago met the
        // goal; this app logged nothing then. Today is short so far.
        let snapshot = try await makeSnapshot(garminML: [0: 800, -1: 2100, -2: 2000, -3: 900])
        let totals = WaterDayTotals(isStandalone: false, snapshot: snapshot, outboxEntries: [], localEntries: [], calendar: calendar)

        XCTAssertEqual(totals.streak(goalML: 2000, today: today), 2, "yesterday + two days ago; today in progress")
    }

    func testStreakIncludesTodayOnceItsGoalIsMet() async throws {
        let snapshot = try await makeSnapshot(garminML: [0: 2000, -1: 2100, -2: 500])
        let totals = WaterDayTotals(isStandalone: false, snapshot: snapshot, outboxEntries: [], localEntries: [], calendar: calendar)

        XCTAssertEqual(totals.streak(goalML: 2000, today: today), 2)
    }
}
