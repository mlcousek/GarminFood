// GarminHistoryImportTests.swift
//
// add-standalone-mode task 5.5: "Copy my last 90 days from Garmin" -- the
// read-back mapping (per-serving x quantity, like MealDashboard), the
// idempotent ids (a second run copies nothing twice), and the stop rules
// (sign-in / rate limit / route unavailable). A fake `NutritionLogReading`
// stands in for Garmin; the food log is a real `LocalFoodLogStore` on a
// temp directory.

import XCTest
import GarminKit
@testable import FoodLogCore

final class GarminHistoryImportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GarminHistoryImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// Answers `dailyFoodLog` from a table; everything else is unused.
    private final class FakeReader: NutritionLogReading, @unchecked Sendable {
        var logs: [String: DailyFoodLog] = [:]
        var errors: [String: Error] = [:]
        var failEverything: Error?
        private(set) var requested: [String] = []

        func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
            requested.append(date)
            if let failEverything { throw failEverything }
            if let error = errors[date] { throw error }
            return logs[date]
        }
        func mealsForDate(date: String) async throws -> MealsForDate { throw GarminClientError.noHTTPResponse }
        func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse { throw GarminClientError.noHTTPResponse }
        func dailyUserSummary(date: String) async throws -> DailyUserSummary { throw GarminClientError.noHTTPResponse }
    }

    private func oatmealLog(day: String) -> DailyFoodLog {
        DailyFoodLog(
            mealDate: day,
            mealDetails: [
                MealDetail(
                    meal: Meal(mealName: MealType.breakfast.rawValue),
                    loggedFoods: [
                        LoggedFood(
                            logId: "abc123",
                            logTimestamp: "\(day)T07:30:00.000",
                            servingQty: 1.5,
                            foodMetaData: FoodMetaData(foodId: "5638212", foodName: "Oatmeal", brandName: "Emco", source: "GARMIN", regionCode: "CZ", languageCode: "cs"),
                            nutritionContent: LoggedNutritionContent(servingId: "s-1", servingUnit: "g", numberOfUnits: 50, calories: 180, carbs: 30, protein: 6, fat: 3)
                        )
                    ]
                ),
                MealDetail(meal: Meal(mealName: "SOMETHING_NEW"), loggedFoods: [LoggedFood(logId: "zzz")]),
            ]
        )
    }

    // MARK: - Mapping

    func testReadBackBecomesTheLoggedAmount() throws {
        let entries = GarminHistoryImport.localEntries(from: oatmealLog(day: "2026-09-20"), day: "2026-09-20", calendar: calendar)

        XCTAssertEqual(entries.count, 1, "a meal this app doesn't know is skipped")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.day, "2026-09-20")
        XCTAssertEqual(entry.mealType, .breakfast)
        XCTAssertEqual(entry.food.id, "5638212")
        XCTAssertEqual(entry.food.name, "Oatmeal")
        XCTAssertEqual(entry.food.brandName, "Emco")
        XCTAssertEqual(entry.food.source, .garmin)
        XCTAssertEqual(entry.servingId, "s-1")
        XCTAssertEqual(entry.quantity, 1.5)
        // nutritionContent is per serving; the stored amount is x quantity.
        XCTAssertEqual(entry.nutrients[NutrientKind.calories.rawValue], 270)
        XCTAssertEqual(entry.nutrients[NutrientKind.carbs.rawValue], 45)
        XCTAssertEqual(entry.nutrients[NutrientKind.protein.rawValue], 9)
        XCTAssertNil(entry.nutrients[NutrientKind.fiber.rawValue], "Garmin didn't say")
        XCTAssertEqual(calendar.component(.hour, from: entry.loggedAt), 7)
    }

    func testIdsAreStableAcrossRunsAndDistinctPerEntry() {
        let first = GarminHistoryImport.stableId(day: "2026-09-20", logId: "abc123", fallback: "x")
        XCTAssertEqual(first, GarminHistoryImport.stableId(day: "2026-09-20", logId: "abc123", fallback: "y"))
        XCTAssertNotEqual(first, GarminHistoryImport.stableId(day: "2026-09-21", logId: "abc123", fallback: "x"))
        XCTAssertNotEqual(first, GarminHistoryImport.stableId(day: "2026-09-20", logId: "abc124", fallback: "x"))
    }

    func testNinetyDaysEndingTodayOldestFirst() {
        let days = GarminHistoryImport.days(endingOn: "2026-09-26", count: 90)
        XCTAssertEqual(days.count, 90)
        XCTAssertEqual(days.first, "2026-06-29")
        XCTAssertEqual(days.last, "2026-09-26")
    }

    // MARK: - Run

    func testRunCopiesOnceAndASecondRunAddsNothing() async throws {
        let reader = FakeReader()
        reader.logs["2026-09-25"] = oatmealLog(day: "2026-09-25")
        reader.logs["2026-09-26"] = oatmealLog(day: "2026-09-26")
        let store = LocalFoodLogStore(directoryURL: directory)

        let first = try await GarminHistoryImport.run(reader: reader, store: store, today: "2026-09-26", days: 3, calendar: calendar)
        XCTAssertEqual(first.daysRead, 3)
        XCTAssertEqual(first.entriesCopied, 2)
        XCTAssertEqual(reader.requested, ["2026-09-24", "2026-09-25", "2026-09-26"])

        let second = try await GarminHistoryImport.run(reader: reader, store: store, today: "2026-09-26", days: 3, calendar: calendar)
        XCTAssertEqual(second.entriesCopied, 0)
        XCTAssertEqual(second.alreadyOnPhone, 2)
        let stored = try await store.entries(fromDay: "2026-09-24", toDay: "2026-09-26")
        XCTAssertEqual(stored.count, 2)
    }

    func testOneBadDayIsCountedAndTheRestStillCopy() async throws {
        let reader = FakeReader()
        reader.logs["2026-09-26"] = oatmealLog(day: "2026-09-26")
        reader.errors["2026-09-25"] = GarminClientError.httpError(statusCode: 500, body: nil)
        let store = LocalFoodLogStore(directoryURL: directory)

        let result = try await GarminHistoryImport.run(reader: reader, store: store, today: "2026-09-26", days: 2, calendar: calendar)

        XCTAssertEqual(result.failedDays, 1)
        XCTAssertEqual(result.entriesCopied, 1)
    }

    func testSignInProblemStopsAtOnce() async throws {
        let reader = FakeReader()
        reader.failEverything = GarminClientError.unauthorized(body: nil)
        let store = LocalFoodLogStore(directoryURL: directory)

        do {
            _ = try await GarminHistoryImport.run(reader: reader, store: store, today: "2026-09-26", days: 90, calendar: calendar)
            XCTFail("expected a sign-in error")
        } catch let error as GarminHistoryImport.ImportError {
            XCTAssertEqual(error, .signInNeeded(copiedSoFar: 0))
        }
        XCTAssertEqual(reader.requested.count, 1)
    }

    func testRouteUnavailableStopsAfterFiveDaysInARow() async throws {
        let reader = FakeReader()
        reader.failEverything = URLError(.notConnectedToInternet)
        let store = LocalFoodLogStore(directoryURL: directory)

        do {
            _ = try await GarminHistoryImport.run(reader: reader, store: store, today: "2026-09-26", days: 90, calendar: calendar)
            XCTFail("expected unavailable")
        } catch let error as GarminHistoryImport.ImportError {
            XCTAssertEqual(error, .unavailable(copiedSoFar: 0))
        }
        XCTAssertEqual(reader.requested.count, GarminHistoryImport.maxConsecutiveFailures)
    }
}
