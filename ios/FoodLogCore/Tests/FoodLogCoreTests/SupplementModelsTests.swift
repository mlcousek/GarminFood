// SupplementModelsTests.swift
//
// add-supplements 1.1: the model's day arithmetic, unit conversion, schedule
// history and -- because every model lands in a store file that is
// quarantined when it no longer decodes -- tolerant decoding of values a
// later build may write.

import XCTest
@testable import FoodLogCore

final class SupplementDateTests: XCTestCase {
    func testOrdinalRoundTripsAndRejectsImpossibleDays() {
        XCTAssertEqual(SupplementDate.ordinal("1970-01-01"), 0)
        XCTAssertEqual(SupplementDate.string(fromOrdinal: 0), "1970-01-01")
        for day in ["2024-02-29", "2026-09-25", "2026-12-31", "2027-01-01", "2000-03-01"] {
            let value = SupplementDate.ordinal(day)
            XCTAssertNotNil(value, day)
            XCTAssertEqual(value.map(SupplementDate.string(fromOrdinal:)), day)
        }
        XCTAssertNil(SupplementDate.ordinal("2026-02-29"))
        XCTAssertNil(SupplementDate.ordinal("2026-13-01"))
        XCTAssertNil(SupplementDate.ordinal("2026-9-25"))
        XCTAssertNil(SupplementDate.ordinal("not a day"))
    }

    func testArithmeticAcrossMonthAndYearBoundaries() {
        XCTAssertEqual(SupplementDate.adding(1, to: "2026-12-31"), "2027-01-01")
        XCTAssertEqual(SupplementDate.adding(-1, to: "2024-03-01"), "2024-02-29")
        XCTAssertEqual(SupplementDate.daysBetween("2025-09-25", "2026-09-25"), 365)
        XCTAssertEqual(SupplementDate.days(from: "2026-09-29", through: "2026-10-02"), ["2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02"])
        XCTAssertEqual(SupplementDate.days(from: "2026-10-02", through: "2026-10-01"), [])
    }

    func testWeekdayUsesCalendarNumbering() {
        XCTAssertEqual(SupplementDate.weekday("1970-01-01"), 5, "Thursday")
        XCTAssertEqual(SupplementDate.weekday("2026-10-04"), 1, "Sunday")
        XCTAssertEqual(SupplementDate.weekday("2026-10-10"), 7, "Saturday")
        XCTAssertEqual(SupplementDate.weekday("1969-12-31"), 4, "Wednesday, before the epoch")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        XCTAssertEqual(SupplementDate.weekday("2026-09-25"), calendar.component(.weekday, from: date))
    }
}

final class SupplementModelsTests: XCTestCase {
    func testVitaminDIUConvertsAtFortyPerMicrogram() {
        XCTAssertEqual(DoseUnit.convert(4000, of: .vitaminD, from: .iu, to: .ug), 100)
        XCTAssertEqual(DoseUnit.convert(25, of: .vitaminD, from: .ug, to: .iu), 1000)
        XCTAssertNil(DoseUnit.convert(100, of: .vitaminC, from: .iu, to: .mg), "IU converts only for vitamin D")
        XCTAssertEqual(DoseUnit.convert(5, of: .creatine, from: .g, to: .mg), 5000)
        XCTAssertEqual(DoseUnit.convert(250, of: .selenium, from: .ug, to: .mg) ?? 0, 0.25, accuracy: 1e-12)
        XCTAssertEqual(IngredientAmount(ingredient: .vitaminD, amount: 2000, unit: .iu).canonicalAmount, 50)
        XCTAssertEqual(DoseUnit.ug.symbol, "µg")
    }

    func testScheduleEditsApplyFromTheirDayForward() {
        let daily = SupplementSchedule(slots: [.evening], pattern: .daily)
        let weekdays = SupplementSchedule(slots: [.evening], pattern: .weekdays([2, 3, 4, 5, 6]))
        var item = PlanItem(productId: UUID())
        item.setSchedule(daily, from: "2026-10-01")
        item.setSchedule(weekdays, from: "2026-10-10")

        XCTAssertNil(item.schedule(on: "2026-09-30"), "nothing before the product was added")
        XCTAssertEqual(item.schedule(on: "2026-10-04"), daily)
        XCTAssertEqual(item.schedule(on: "2026-10-09"), daily)
        XCTAssertEqual(item.schedule(on: "2026-10-10"), weekdays)

        // A same-day edit replaces that day's version, not the history.
        item.setSchedule(daily, from: "2026-10-10")
        XCTAssertEqual(item.versions.count, 1, "identical to what already ran: the later version is dropped")
        item.setSchedule(nil, from: "2026-10-20")
        XCTAssertNil(item.schedule(on: "2026-10-21"))
        XCTAssertEqual(item.schedule(on: "2026-10-19"), daily)
    }

    func testPatternsAndSlotsRoundTrip() throws {
        let patterns: [SchedulePattern] = [
            .daily,
            .everyNDays(n: 2, anchor: "2026-10-01"),
            .weekdays([1, 7]),
            .trainingDays,
            .cycle(phases: [CyclePhase(servingsPerSlot: 4, days: 7), CyclePhase(servingsPerSlot: 1, days: 1)], anchor: "2026-10-01", repeats: false)
        ]
        let slots: [TimeSlot] = [.morning, .withBreakfast, .preWorkout, .evening, .custom(name: "Lunch", minute: 750), .custom(name: "Bed", minute: nil)]
        for pattern in patterns {
            let schedule = SupplementSchedule(slots: slots, servingsPerSlot: 2, pattern: pattern)
            let data = try JSONEncoder().encode(schedule)
            XCTAssertEqual(try JSONDecoder().decode(SupplementSchedule.self, from: data), schedule)
        }
        let sources: [ProductSource] = [.catalog("creatineMonohydrate"), .custom, .barcode("openFoodFacts")]
        for source in sources {
            XCTAssertEqual(try JSONDecoder().decode(ProductSource.self, from: JSONEncoder().encode(source)), source)
        }
    }

    func testValuesFromALaterBuildStillDecode() throws {
        let json = """
        {
          "products": [{
            "id": "6F1C1A40-1C1B-4B7C-9A55-2F1B8E6C0D11",
            "name": "Mystery stack",
            "form": "chewingGum",
            "ingredients": [
              { "ingredient": "ashwagandha", "amount": 300, "unit": "mg" },
              { "ingredient": "vitaminD", "unit": "nanogramsPerDrop", "futureKey": true },
              { "ingredient": "zinc" }
            ],
            "source": { "kind": "aiScan", "reference": "x" },
            "futureField": [1, 2, 3]
          }],
          "items": [{
            "productId": "6F1C1A40-1C1B-4B7C-9A55-2F1B8E6C0D11",
            "versions": [
              { "effectiveFrom": "2026-10-01", "schedule": { "slots": [{ "kind": "lunchtime", "minute": 720 }], "pattern": { "kind": "moonPhase" } } },
              { "effectiveFrom": "not-a-day", "schedule": null }
            ]
          }],
          "schemaVersion": 7
        }
        """
        let plan = try JSONDecoder().decode(SupplementPlan.self, from: Data(json.utf8))

        let product = try XCTUnwrap(plan.products.first)
        XCTAssertEqual(product.form?.rawValue, "chewingGum")
        XCTAssertEqual(product.ingredients.map(\.ingredient.rawValue), ["ashwagandha", "vitaminD", "zinc"])
        XCTAssertEqual(product.ingredients[1].unit.rawValue, "nanogramsPerDrop", "an unknown unit round-trips")
        XCTAssertNil(product.ingredients[1].canonicalAmount)
        XCTAssertEqual(product.ingredients[2].unit, .mg, "a missing unit falls back to the canonical one")
        XCTAssertEqual(product.source, .custom)
        XCTAssertEqual(product.effectiveCurrency, "CZK")

        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.versions.count, 1, "a version with an invalid day is dropped")
        let schedule = try XCTUnwrap(item.schedule(on: "2026-10-02"))
        XCTAssertEqual(schedule.pattern, .unknown("moonPhase"))
        XCTAssertEqual(schedule.slots, [.custom(name: "lunchtime", minute: 720)])
        XCTAssertEqual(schedule.servingsPerSlot, 1)
    }

    func testIntakeRecordDecodesWithOnlyIdentity() throws {
        let json = """
        { "id": "0B8B7E57-9D5E-4E4B-9E0A-1C6E1F4B2A10", "day": "2026-09-25", "productId": "6F1C1A40-1C1B-4B7C-9A55-2F1B8E6C0D11" }
        """
        let record = try JSONDecoder().decode(IntakeRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.kind, .planned)
        XCTAssertEqual(record.servings, 1)
        XCTAssertNil(record.slot)
        XCTAssertNil(record.recordedOn)
        XCTAssertNil(record.plannedKey, "a planned record without a slot has no checklist key")
    }

    func testSlotsSortBuiltInFirstThenCustomByTime() {
        let slots: [TimeSlot] = [.custom(name: "B", minute: nil), .evening, .custom(name: "A", minute: 600), .morning, .preWorkout]
        XCTAssertEqual(slots.sorted(), [.morning, .preWorkout, .evening, .custom(name: "A", minute: 600), .custom(name: "B", minute: nil)])
    }
}
