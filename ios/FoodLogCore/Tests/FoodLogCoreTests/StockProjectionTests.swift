// StockProjectionTests.swift
//
// add-supplements 1.8: stock after ticks, days left under the current
// schedule, the once-per-pack restock trigger, and cost per day/month --
// spec scenarios "Days left", "Cost" and "Running low".

import XCTest
@testable import FoodLogCore

final class StockProjectionTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ product: SupplementProduct, _ day: String, servings: Double = 1, kind: IntakeKind = .planned) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: kind == .planned ? TimeSlot.morning : nil, servings: servings, takenAt: takenAt, kind: kind)
    }

    private func omega(stock: Double = 120, setOn: String = "2026-09-01") -> SupplementProduct {
        SupplementProduct(
            name: "Omega",
            form: .capsule,
            ingredients: [IngredientAmount(ingredient: .omega3EPA_DHA, amount: 300, unit: .mg)],
            packServings: 120,
            stockServings: stock,
            stockSetOn: setOn
        )
    }

    // Spec: Days left.
    func testThirtyCapsulesAtTwoADayLastFifteenDays() {
        let product = omega()
        var plan = SupplementPlan(products: [product])
        plan.setSchedule(SupplementSchedule(slots: [.morning], servingsPerSlot: 2), for: product.id, from: "2026-09-01")
        // 45 days x 2 capsules = 90 of the 120 taken.
        let days = SupplementDate.days(from: "2026-09-01", through: "2026-10-15")
        XCTAssertEqual(days.count, 45)
        let records = days.map { record(product, $0, servings: 2) }

        XCTAssertEqual(StockProjection.remainingServings(of: product, records: records), 30)
        XCTAssertEqual(StockProjection.daysLeft(of: product, plan: plan, records: records, today: "2026-10-16", trainingDays: []), 15)

        let withExtra = records + [record(product, "2026-10-15", servings: 2, kind: .extra)]
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: withExtra), 28, "extras drain the pack too")
        XCTAssertEqual(StockProjection.daysLeft(of: product, plan: plan, records: withExtra, today: "2026-10-16", trainingDays: []), 14)
    }

    func testNoStockOrNothingPlannedMeansNoProjection() {
        var product = omega()
        product.stockServings = nil
        var plan = SupplementPlan(products: [product])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: product.id, from: "2026-09-01")
        XCTAssertNil(StockProjection.daysLeft(of: product, plan: plan, records: [], today: "2026-10-01", trainingDays: []))

        let stocked = omega()
        XCTAssertNil(StockProjection.daysLeft(of: stocked, plan: SupplementPlan(products: [stocked]), records: [], today: "2026-10-01", trainingDays: []),
                     "never runs out when nothing is planned")
        var empty = omega(stock: 1)
        empty.stockSetOn = "2026-09-01"
        plan = SupplementPlan(products: [empty])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: empty.id, from: "2026-09-01")
        XCTAssertEqual(StockProjection.daysLeft(of: empty, plan: plan, records: [record(empty, "2026-09-02", servings: 3)], today: "2026-10-01", trainingDays: []), 0)
    }

    func testTheRateFollowsThePattern() {
        let product = omega()
        var plan = SupplementPlan(products: [product])
        plan.setSchedule(SupplementSchedule(slots: [.morning, .evening], pattern: .everyNDays(n: 2, anchor: "2026-10-01")), for: product.id, from: "2026-09-01")
        XCTAssertEqual(StockProjection.plannedServingsPerDay(of: product.id, plan: plan, today: "2026-10-01", trainingDays: []), 1, accuracy: 1e-9,
                       "2 slots every other day")

        plan.setSchedule(SupplementSchedule(slots: [.preWorkout], pattern: .trainingDays), for: product.id, from: "2026-10-01")
        let training = Set(["2026-09-24", "2026-09-26", "2026-09-28", "2026-09-30", "2026-10-05"])
        XCTAssertEqual(StockProjection.plannedServingsPerDay(of: product.id, plan: plan, today: "2026-10-01", trainingDays: training), 4.0 / 28, accuracy: 1e-9,
                       "training days: how often the last 28 days were training days")
    }

    // Spec: Running low.
    func testRestockIsRemindedOncePerPack() {
        var product = omega()
        XCTAssertTrue(StockProjection.shouldRemindRestock(product, daysLeft: 7))
        XCTAssertFalse(StockProjection.shouldRemindRestock(product, daysLeft: 8))
        XCTAssertFalse(StockProjection.shouldRemindRestock(product, daysLeft: nil))
        XCTAssertTrue(StockProjection.shouldRemindRestock(product, daysLeft: 10, leadTimeDays: 14))

        product.restockRemindedFor = product.stockSetOn
        XCTAssertFalse(StockProjection.shouldRemindRestock(product, daysLeft: 3), "none again until refilled")

        product.refill(on: "2026-10-05", records: [])
        XCTAssertTrue(StockProjection.shouldRemindRestock(product, daysLeft: 3), "a refill re-arms it")
    }

    func testSettingStockMidDayDoesNotSubtractTodaysTicksTwice() {
        var product = omega(stock: 10, setOn: "2026-09-01")
        let records = [record(product, "2026-09-30", servings: 2), record(product, "2026-10-01", servings: 2)]
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: records), 6)

        // Refilled on 2026-10-01 after that day's tick: 6 left + 120.
        product.refill(on: "2026-10-01", records: records)
        XCTAssertEqual(product.stockSetOn, "2026-10-01")
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: records), 126)

        // A later tick drains the new pack.
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: records + [record(product, "2026-10-02")]), 125)

        product.setStock(servingsOnHand: 50, on: "2026-10-01", records: records)
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: records), 50)
    }

    // Spec: Cost.
    func testCostPerDayAndMonth() throws {
        let product = SupplementProduct(name: "D3", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 1000, unit: .iu)], packServings: 60, pricePerPack: 450)
        var plan = SupplementPlan(products: [product])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: product.id, from: "2026-09-01")

        let cost = try XCTUnwrap(StockProjection.cost(of: product, plan: plan, today: "2026-10-01", trainingDays: []))

        XCTAssertEqual(cost.perDay, 7.5, accuracy: 1e-9)
        XCTAssertEqual(cost.perMonth, 225, accuracy: 1e-9)
        XCTAssertEqual(cost.currency, "CZK")
        XCTAssertNil(StockProjection.costPerServing(of: SupplementProduct(name: "x", ingredients: [], pricePerPack: 100)))
    }
}
