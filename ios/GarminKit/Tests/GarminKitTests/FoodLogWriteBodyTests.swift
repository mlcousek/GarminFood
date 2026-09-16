// FoodLogWriteBodyTests.swift
//
// Pins the create-food-log wire body to what garmin_mcp sends -- the client
// this contract was taken from, which writes to a real account in its own
// end-to-end tests. The body this project inferred before (a flat POST) was
// wrong in almost every field and was never once sent successfully, so these
// tests exist to make any drift from the proven shape a CI failure rather
// than another device round trip.
//
// Every id below is synthetic. The meal windows mirror the shape that
// `GET /nutrition-service/meals/{date}` returned on 2026-09-16.

import XCTest
@testable import GarminKit

final class FoodLogWriteBodyTests: XCTestCase {
    private let mealsJSON = """
    {
      "meals": [
        { "mealId": 101, "mealName": "BREAKFAST", "startTime": "04:00:00", "endTime": "07:00:00" },
        { "mealId": 102, "mealName": "LUNCH", "startTime": "10:00:00", "endTime": "12:00:00" },
        { "mealId": 103, "mealName": "DINNER", "startTime": "14:00:00", "endTime": "17:00:00" },
        { "mealId": 104, "mealName": "SNACKS" }
      ],
      "dailyTimelineStartTime": "04:00:00",
      "dailyTimelineEndTime": "17:00:00"
    }
    """

    private let utc = TimeZone(identifier: "UTC")!

    private func meals() throws -> [Meal] {
        try JSONDecoder().decode(MealsForDate.self, from: Data(mealsJSON.utf8)).meals ?? []
    }

    private func instant(_ iso: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    private func request(
        mealType: MealType,
        loggedAt: String,
        foodId: String = "12345",
        source: GarminFoodSource? = nil
    ) -> CreateFoodLogEntryRequest {
        CreateFoodLogEntryRequest(
            date: "2026-09-16",
            mealType: mealType,
            foodId: foodId,
            servingId: "678",
            numberOfUnits: 1.5,
            source: source,
            loggedAt: instant(loggedAt)
        )
    }

    private func onlyItem(_ body: FoodLogWriteBody) throws -> FoodLogWriteBody.Item {
        XCTAssertEqual(body.foodLogItems.count, 1)
        return try XCTUnwrap(body.foodLogItems.first)
    }

    // MARK: - The wire shape

    func testEncodesExactlyTheFieldsTheLiveTestedClientSends() throws {
        let body = try FoodLogWriteBody.make(
            for: request(mealType: .lunch, loggedAt: "2026-09-16T10:30:00.250Z", source: .fatSecret),
            meals: meals(),
            timeZone: utc
        )
        let encoded = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(Set(json.keys), Set(["mealDate", "foodLogItems"]))
        XCTAssertEqual(json["mealDate"] as? String, "2026-09-16")

        let items = try XCTUnwrap(json["foodLogItems"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        let expectedKeys: Set<String> = [
            "logTimestamp", "logSource", "logCategory", "mealTime", "action", "mealId",
            "foodId", "servingId", "source", "regionCode", "languageCode", "servingQty",
        ]
        XCTAssertEqual(Set(item.keys), expectedKeys, "no numberOfUnits, no mealType, no flat date -- the old inferred body")

        XCTAssertEqual(item["logTimestamp"] as? String, "2026-09-16T10:30:00.250Z")
        XCTAssertEqual(item["logSource"] as? String, "GCW")
        XCTAssertEqual(item["logCategory"] as? String, "REGULAR_LOG")
        XCTAssertEqual(item["action"] as? String, "ADD")
        XCTAssertEqual(item["mealId"] as? Int, 102)
        XCTAssertEqual(item["mealTime"] as? String, "10:00:00")
        XCTAssertEqual(item["foodId"] as? String, "12345")
        XCTAssertEqual(item["servingId"] as? String, "678")
        XCTAssertEqual(item["source"] as? String, "FATSECRET")
        XCTAssertEqual(item["regionCode"] as? String, "US")
        XCTAssertEqual(item["languageCode"] as? String, "en")
        XCTAssertEqual(item["servingQty"] as? Double, 1.5)
    }

    func testMealIdIsResolvedByNameForEveryMealType() throws {
        let expected: [(MealType, Int)] = [(.breakfast, 101), (.lunch, 102), (.dinner, 103), (.snacks, 104)]
        for (mealType, mealId) in expected {
            let body = try FoodLogWriteBody.make(
                for: request(mealType: mealType, loggedAt: "2026-09-16T20:00:00Z"),
                meals: meals(),
                timeZone: utc
            )
            XCTAssertEqual(try onlyItem(body).mealId, mealId, "\(mealType)")
        }
    }

    func testAMissingMealFailsBeforeAnythingIsSent() throws {
        let withoutSnacks = try meals().filter { $0.mealName != "SNACKS" }

        XCTAssertThrowsError(
            try FoodLogWriteBody.make(
                for: request(mealType: .snacks, loggedAt: "2026-09-16T08:00:00Z"),
                meals: withoutSnacks,
                timeZone: utc
            )
        ) { error in
            XCTAssertEqual(error as? FoodLogWriteError, .mealNotFound(mealName: "SNACKS", date: "2026-09-16"))
        }
    }

    // MARK: - mealTime

    func testAWindowedMealIsStampedAtItsStartTimeWheneverItWasLogged() throws {
        let body = try FoodLogWriteBody.make(
            for: request(mealType: .breakfast, loggedAt: "2026-09-16T20:00:00Z"),
            meals: meals(),
            timeZone: utc
        )
        XCTAssertEqual(try onlyItem(body).mealTime, "04:00:00")
    }

    func testASnackOutsideEveryWindowKeepsItsLocalTime() throws {
        let body = try FoodLogWriteBody.make(
            for: request(mealType: .snacks, loggedAt: "2026-09-16T08:15:00Z"),
            meals: meals(),
            timeZone: utc
        )
        XCTAssertEqual(try onlyItem(body).mealTime, "08:15:00")
    }

    func testASnackLoggedDuringLunchIsStampedJustAfterLunch() throws {
        // By garmin_mcp's reading, a mealTime inside a window IS that meal.
        let body = try FoodLogWriteBody.make(
            for: request(mealType: .snacks, loggedAt: "2026-09-16T11:00:00Z"),
            meals: meals(),
            timeZone: utc
        )
        XCTAssertEqual(try onlyItem(body).mealTime, "12:00:01")
    }

    func testASnackUsesTheDevicesLocalTimeNotUTC() throws {
        let prague = try XCTUnwrap(TimeZone(identifier: "Europe/Prague"))
        // 06:15 UTC is 08:15 in Prague in September (CEST, UTC+2).
        let body = try FoodLogWriteBody.make(
            for: request(mealType: .snacks, loggedAt: "2026-09-16T06:15:00Z"),
            meals: meals(),
            timeZone: prague
        )
        XCTAssertEqual(try onlyItem(body).mealTime, "08:15:00")
    }

    func testTimeHelpers() {
        XCTAssertEqual(FoodLogWriteBody.secondsOfDay("12:00:00"), 43_200)
        XCTAssertEqual(FoodLogWriteBody.timeString(43_201), "12:00:01")
        XCTAssertEqual(FoodLogWriteBody.timeString(0), "00:00:00")
        XCTAssertNil(FoodLogWriteBody.secondsOfDay("noon"))
    }

    // MARK: - Food namespace

    func testSourceIsInferredFromTheIdShape() {
        XCTAssertEqual(GarminFoodSource.inferred(fromFoodId: "17926789"), .fatSecret)
        XCTAssertEqual(GarminFoodSource.inferred(fromFoodId: "0123456789abcdef0123456789abcdef"), .garmin)
        XCTAssertEqual(GarminFoodSource.inferred(fromFoodId: ""), .garmin)
    }

    func testARequestWithoutASourceInfersIt() {
        XCTAssertEqual(request(mealType: .lunch, loggedAt: "2026-09-16T10:00:00Z", foodId: "12345").source, .fatSecret)
        XCTAssertEqual(
            request(mealType: .lunch, loggedAt: "2026-09-16T10:00:00Z", foodId: "0123456789abcdef0123456789abcdef").source,
            .garmin
        )
    }

    func testAnExplicitSourceWinsOverInference() {
        XCTAssertEqual(request(mealType: .lunch, loggedAt: "2026-09-16T10:00:00Z", foodId: "12345", source: .garmin).source, .garmin)
    }

    // MARK: - Entries already sitting in users' outbox files

    func testAnOutboxEntryQueuedBeforeSourceExistedStillDecodesAndDelivers() throws {
        // Written by a build that predates `source`; the dates use
        // JSONEncoder's default encoding (seconds since 2001-01-01).
        let oldEntryJSON = """
        {
          "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          "date": "2026-09-16",
          "mealType": "SNACKS",
          "foodId": "12345",
          "servingId": "678",
          "numberOfUnits": 1,
          "state": "pending",
          "attemptCount": 1,
          "lastError": "httpError(statusCode: 405, body: nil)",
          "createdAt": 779727600,
          "nextAttemptAt": 779727600
        }
        """

        let entry = try JSONDecoder().decode(OutboxEntry.self, from: Data(oldEntryJSON.utf8))

        XCTAssertNil(entry.source)
        XCTAssertEqual(entry.createRequest.source, .fatSecret, "a missing source is inferred, not a reason to drop the entry")
        XCTAssertEqual(entry.createRequest.loggedAt, entry.createdAt, "the entry is stamped with when it was logged, not when it's delivered")
    }
}
