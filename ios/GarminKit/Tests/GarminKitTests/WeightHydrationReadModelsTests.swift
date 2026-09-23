// WeightHydrationReadModelsTests.swift
//
// Pins the Garmin READ models added by sync-weight-hydration-with-garmin
// (`GarminWeighIn`, `WeighInDayView`, `WeightRangeResponse`,
// `HydrationDaily`) to the payloads actually returned by the owner's live
// account on 2026-09-23 (docs/garmin-routes.json: weighInsDayView,
// getWeighIns, hydrationDaily). The JSON below is trimmed from those real
// responses -- field names, nulls, number formats (grams as integers, a
// float `weightDelta`, epoch-ms timestamps) kept exactly as observed --
// so a model change that would stop decoding the real thing fails here
// first, in CI, instead of silently on the phone.

import XCTest
@testable import GarminKit

final class WeightHydrationReadModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - dayview

    func testDayViewDecodesTheLiveProbedPayloadInGramsAndEpochMillis() throws {
        let json = """
        {
          "startDate": "2026-09-23",
          "endDate": "2026-09-23",
          "dateWeightList": [
            {"samplePk": 1790149333817, "date": 1790156491732, "calendarDate": "2026-09-23", "weight": 83900,
             "bmi": null, "bodyFat": null, "bodyWater": null, "boneMass": null, "muscleMass": null,
             "physiqueRating": null, "visceralFat": null, "metabolicAge": null,
             "sourceType": "MANUAL", "timestampGMT": 1790149291732, "weightDelta": 1100.0000000000086},
            {"samplePk": 1790128696277, "date": 1790135895000, "calendarDate": "2026-09-23", "weight": 82800,
             "bmi": null, "bodyFat": null, "bodyWater": null, "boneMass": null, "muscleMass": null,
             "physiqueRating": null, "visceralFat": null, "metabolicAge": null,
             "sourceType": "MANUAL", "timestampGMT": 1790128695000, "weightDelta": -200.00000000000284}
          ],
          "totalAverage": {"from": 1790121600000, "until": 1790207999999, "weight": 83350.0, "bmi": null}
        }
        """

        let dayView = try decoder.decode(WeighInDayView.self, from: Data(json.utf8))

        XCTAssertEqual(dayView.weighIns.count, 2)
        XCTAssertEqual(dayView.skippedCount, 0)
        let first = try XCTUnwrap(dayView.weighIns.first)
        XCTAssertEqual(first.samplePk, 1_790_149_333_817)
        XCTAssertEqual(first.calendarDate, "2026-09-23")
        XCTAssertEqual(first.weightGrams, 83_900)
        XCTAssertEqual(first.weightKg, 83.9, accuracy: 0.0001, "Garmin weights are GRAMS")
        XCTAssertEqual(first.timestamp, Date(timeIntervalSince1970: 1_790_149_291.732))
        XCTAssertEqual(first.sourceType, "MANUAL")
        XCTAssertNil(first.bodyFat)
        XCTAssertEqual(dayView.weighIns.last?.weightKg ?? 0, 82.8, accuracy: 0.0001)
    }

    func testDayViewSkipsAMalformedSampleInsteadOfFailingTheWholeDay() throws {
        let json = """
        {"dateWeightList": [
          {"samplePk": 1, "calendarDate": "2026-09-23", "weight": null, "timestampGMT": 1790149291732},
          {"samplePk": 2, "calendarDate": "2026-09-23", "weight": 82800, "timestampGMT": 1790128695000}
        ]}
        """

        let dayView = try decoder.decode(WeighInDayView.self, from: Data(json.utf8))

        XCTAssertEqual(dayView.weighIns.map(\.samplePk), [2])
        XCTAssertEqual(dayView.skippedCount, 1)
    }

    func testDayViewWithNoWeighInsDecodesEmpty() throws {
        let dayView = try decoder.decode(WeighInDayView.self, from: Data(#"{"startDate":"2026-09-20","endDate":"2026-09-20","dateWeightList":[]}"#.utf8))
        XCTAssertTrue(dayView.weighIns.isEmpty)
    }

    // MARK: - range

    func testRangeDecodesDailySummariesAndFlattensNewestFirst() throws {
        let json = """
        {
          "dailyWeightSummaries": [
            {"summaryDate": "2026-09-23", "numOfWeightEntries": 2, "minWeight": 82800, "maxWeight": 83900,
             "latestWeight": {"samplePk": 1790149333817, "date": 1790156491732, "calendarDate": "2026-09-23", "weight": 83900,
                              "sourceType": "MANUAL", "timestampGMT": 1790149291732, "weightDelta": 900.0000000000057},
             "allWeightMetrics": [
               {"samplePk": 1790149333817, "date": 1790156491732, "calendarDate": "2026-09-23", "weight": 83900,
                "bmi": null, "sourceType": "MANUAL", "timestampGMT": 1790149291732, "weightDelta": 1100.0000000000086},
               {"samplePk": 1790128696277, "date": 1790135895000, "calendarDate": "2026-09-23", "weight": 82800,
                "bmi": null, "sourceType": "MANUAL", "timestampGMT": 1790128695000, "weightDelta": -200.00000000000284}
             ]},
            {"summaryDate": "2026-09-21", "numOfWeightEntries": 1, "minWeight": 82700, "maxWeight": 82700,
             "allWeightMetrics": [
               {"samplePk": 1789956066169, "date": 1789963224000, "calendarDate": "2026-09-21", "weight": 82700,
                "sourceType": "MANUAL", "timestampGMT": 1789956024000, "weightDelta": -1299.9999999999973}
             ]}
          ],
          "totalAverage": {"from": 1788220800000, "until": 1790207999999, "weight": 82977.77777777778},
          "previousDateWeight": {"samplePk": 1787716279151, "date": 1787723479000, "calendarDate": "2026-08-26", "weight": 84100,
                                 "sourceType": "MANUAL", "timestampGMT": 1787716279000, "weightDelta": 2899.9999999999914},
          "nextDateWeight": null
        }
        """

        let range = try decoder.decode(WeightRangeResponse.self, from: Data(json.utf8))

        XCTAssertEqual(range.dailyWeightSummaries.count, 2, "days without weigh-ins are omitted by Garmin, not sent empty")
        XCTAssertEqual(range.dailyWeightSummaries.first?.summaryDate, "2026-09-23")
        XCTAssertEqual(range.allWeighIns.map(\.samplePk), [1_790_149_333_817, 1_790_128_696_277, 1_789_956_066_169])
        XCTAssertEqual(range.previousDateWeight?.calendarDate, "2026-08-26")
        XCTAssertFalse(range.allWeighIns.contains { $0.samplePk == 1_787_716_279_151 }, "the sample before the range is not part of it")
        XCTAssertEqual(range.skippedCount, 0)
    }

    func testRangeWithNothingInItDecodesEmpty() throws {
        let range = try decoder.decode(WeightRangeResponse.self, from: Data(#"{"dailyWeightSummaries":[],"totalAverage":{},"previousDateWeight":null,"nextDateWeight":null}"#.utf8))
        XCTAssertTrue(range.allWeighIns.isEmpty)
        XCTAssertNil(range.previousDateWeight)
    }

    // MARK: - cache round trip

    func testWeighInEncodesBackToTheWireShapeAndRoundTrips() throws {
        let original = GarminWeighIn(samplePk: 7, calendarDate: "2026-09-23", weightGrams: 83_900, timestampGMT: 1_790_149_291_732, localWallClockMillis: 1_790_156_491_732)

        let data = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["weight"], "cached files use Garmin's own key names")
        XCTAssertNotNil(object["date"])

        XCTAssertEqual(try decoder.decode(GarminWeighIn.self, from: data), original)
    }

    // MARK: - hydration daily

    func testHydrationDailyDecodesTheLiveProbedPayload() throws {
        let json = """
        {"userId": 12345, "calendarDate": "2026-09-23", "valueInML": 1500.0, "goalInML": 2800.0,
         "dailyAverageinML": null, "lastEntryTimestampLocal": "2026-09-23T09:25:26.387",
         "sweatLossInML": null, "activityIntakeInML": 0.0}
        """

        let daily = try decoder.decode(HydrationDaily.self, from: Data(json.utf8))

        XCTAssertEqual(daily.calendarDate, "2026-09-23")
        XCTAssertEqual(daily.valueInML, 1500)
        XCTAssertEqual(daily.goalInML, 2800)
        XCTAssertEqual(daily.lastEntryTimestampLocal, "2026-09-23T09:25:26.387")
        XCTAssertNil(daily.sweatLossInML)
    }

    func testHydrationDailyForAnEmptyDayDecodesWithNilTotal() throws {
        let daily = try decoder.decode(HydrationDaily.self, from: Data(#"{"calendarDate":"2026-09-20","valueInML":null,"goalInML":2800}"#.utf8))
        XCTAssertNil(daily.valueInML)
        XCTAssertEqual(daily.goalInML, 2800)
    }

    // MARK: - delete body

    func testDeleteBodyIsAnEmptyJSONObject() throws {
        let data = try JSONEncoder().encode(EmptyJSONBody())
        XCTAssertEqual(String(data: data, encoding: .utf8), "{}", "matches the owner-approved 2026-09-23 probe")
    }
}
