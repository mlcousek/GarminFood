// HydrationTrackingTests.swift
//
// HydrationEntry's JSON-file-backed store (same pattern as
// WeightTrackingTests.swift) plus HydrationHistory's pure day-total logic.

import XCTest
@testable import FoodLogCore

final class HydrationTrackingTests: XCTestCase {
    private func makeStore() -> HydrationStore {
        HydrationStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hydration-store-test-\(UUID().uuidString).json"))
    }

    // MARK: - Store CRUD

    func testUpsertThenAllReturnsTheEntry() async throws {
        let store = makeStore()
        let entry = HydrationEntry(valueInML: 250)

        try await store.upsert(entry)

        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [entry.id])
        XCTAssertEqual(all.first?.valueInML, 250)
    }

    func testAllIsSortedNewestFirst() async throws {
        let store = makeStore()
        let older = HydrationEntry(valueInML: 250, loggedAt: Date(timeIntervalSince1970: 1_000))
        let newer = HydrationEntry(valueInML: 500, loggedAt: Date(timeIntervalSince1970: 2_000))

        try await store.upsert(older)
        try await store.upsert(newer)

        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [newer.id, older.id])
    }

    func testDeleteRemovesTheEntry() async throws {
        let store = makeStore()
        let entry = HydrationEntry(valueInML: 250)
        try await store.upsert(entry)

        try await store.delete(id: entry.id)

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testEntriesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hydration-store-persist-\(UUID().uuidString).json")
        let store1 = HydrationStore(fileURL: url)
        let entry = HydrationEntry(valueInML: 250)
        try await store1.upsert(entry)

        let store2 = HydrationStore(fileURL: url)
        let reloaded = await store2.all()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
    }

    // MARK: - HydrationHistory.total / .entries

    func testTotalSumsOnlyEntriesOnTheGivenDay() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_758_500_000) // an arbitrary fixed instant
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let entries = [
            HydrationEntry(valueInML: 250, loggedAt: today),
            HydrationEntry(valueInML: 500, loggedAt: today),
            HydrationEntry(valueInML: 1000, loggedAt: yesterday)
        ]

        let total = HydrationHistory.total(for: entries, on: today, calendar: calendar)

        XCTAssertEqual(total, 750, "only today's two entries count, not yesterday's")
    }

    func testTotalIsZeroWhenNoEntriesMatchTheDay() {
        let today = Date()
        let total = HydrationHistory.total(for: [], on: today)
        XCTAssertEqual(total, 0)
    }

    func testEntriesFiltersToOnlyTheGivenDay() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_758_500_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let todayEntry = HydrationEntry(valueInML: 250, loggedAt: today)
        let yesterdayEntry = HydrationEntry(valueInML: 1000, loggedAt: yesterday)

        let filtered = HydrationHistory.entries(for: [todayEntry, yesterdayEntry], on: today, calendar: calendar)

        XCTAssertEqual(filtered.map(\.id), [todayEntry.id])
    }

    // MARK: - HydrationHistory.streak

    func testStreakCountsConsecutiveDaysMeetingTheGoal() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_758_500_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let entries = [
            HydrationEntry(valueInML: 2000, loggedAt: today),
            HydrationEntry(valueInML: 2000, loggedAt: yesterday),
            HydrationEntry(valueInML: 2000, loggedAt: twoDaysAgo)
        ]

        let streak = HydrationHistory.streak(for: entries, goalML: 2000, on: today, calendar: calendar)

        XCTAssertEqual(streak, 3)
    }

    func testStreakStopsAtTheFirstDayBelowGoal() {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date(timeIntervalSince1970: 1_758_500_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let entries = [
            HydrationEntry(valueInML: 2000, loggedAt: today),
            HydrationEntry(valueInML: 500, loggedAt: yesterday), // short of goal, breaks the streak
            HydrationEntry(valueInML: 2000, loggedAt: twoDaysAgo)
        ]

        let streak = HydrationHistory.streak(for: entries, goalML: 2000, on: today, calendar: calendar)

        XCTAssertEqual(streak, 1, "only today counts; yesterday's shortfall breaks the streak before two-days-ago is ever reached")
    }

    func testStreakIsZeroWhenTodayItselfIsBelowGoal() {
        let today = Date()
        let entries = [HydrationEntry(valueInML: 250, loggedAt: today)]

        let streak = HydrationHistory.streak(for: entries, goalML: 2000, on: today)

        XCTAssertEqual(streak, 0, "today doesn't get a free pass -- it must itself meet the goal to count")
    }

    func testStreakIsZeroWhenGoalIsZeroOrNegative() {
        let today = Date()
        let entries = [HydrationEntry(valueInML: 3000, loggedAt: today)]

        XCTAssertEqual(HydrationHistory.streak(for: entries, goalML: 0, on: today), 0)
        XCTAssertEqual(HydrationHistory.streak(for: entries, goalML: -100, on: today), 0)
    }
}
