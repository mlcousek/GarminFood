// PastDayLoggingTests.swift
//
// add-supplements 1.9 (design D14): backfilling any day up to 365 days
// back, evaluated against that day's schedule; stock untouched by intake
// dated before the current pack; no XP for entries more than 7 days late.
// The store-level guard is in SupplementStoresTests.

import XCTest
@testable import FoodLogCore

final class PastDayLoggingTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func tick(_ product: SupplementProduct, _ slot: TimeSlot, _ day: String, recordedOn: String) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: slot, servings: 1, takenAt: takenAt, kind: .planned, recordedOn: recordedOn)
    }

    // Spec: Too far back.
    func testTheEditableWindowIsTodayBack365Days() {
        XCTAssertEqual(PastDayLogging.editability(of: "2026-09-25", today: "2026-09-25"), .editable)
        XCTAssertEqual(PastDayLogging.editability(of: "2025-09-25", today: "2026-09-25"), .editable, "exactly 365 days back")
        XCTAssertEqual(PastDayLogging.editability(of: "2025-09-24", today: "2026-09-25"), .tooFarBack)
        XCTAssertEqual(PastDayLogging.editability(of: "2026-09-26", today: "2026-09-25"), .future)
        XCTAssertEqual(PastDayLogging.editability(of: "yesterday", today: "2026-09-25"), .invalidDay)
        XCTAssertEqual(PastDayLogging.earliestEditableDay(today: "2026-09-25"), "2025-09-25")
        XCTAssertEqual(PastDayLogging.earliestEditableDay(today: "2025-03-01"), "2024-03-01", "across a leap day")
    }

    // Spec: Backfill a month ago (with a schedule change in between).
    func testBackfillIsJudgedByTheScheduleActiveThatDay() {
        let creatine = SupplementProduct(name: "Creatine", ingredients: [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)])
        let vitaminD = SupplementProduct(name: "D3", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 1000, unit: .iu)])
        let magnesium = SupplementProduct(name: "Mg", ingredients: [IngredientAmount(ingredient: .magnesium, amount: 200, unit: .mg)])
        var plan = SupplementPlan(products: [creatine, vitaminD, magnesium])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: creatine.id, from: "2026-08-01")
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: vitaminD.id, from: "2026-08-01")
        // Magnesium joined the stack only on 2026-09-10.
        plan.setSchedule(SupplementSchedule(slots: [.evening]), for: magnesium.id, from: "2026-09-10")

        let before = SupplementChecklist(day: "2026-08-25", plan: plan, records: [], trainingDays: [])
        XCTAssertEqual(before.status, .missed)
        XCTAssertEqual(before.entries.count, 2, "magnesium wasn't planned yet on 2026-08-25")

        let records = [tick(creatine, .morning, "2026-08-25", recordedOn: "2026-09-25"), tick(vitaminD, .morning, "2026-08-25", recordedOn: "2026-09-25")]
        let after = SupplementChecklist(day: "2026-08-25", plan: plan, records: records, trainingDays: [])

        XCTAssertEqual(after.status, .complete, "the backfilled day re-classifies from the log")
        XCTAssertEqual(PastDayLogging.editability(of: "2026-08-25", today: "2026-09-25"), .editable)
    }

    func testStockCountsOnlyIntakeFromTheCurrentPackOn() {
        let product = SupplementProduct(
            name: "D3",
            ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 1000, unit: .iu)],
            packServings: 60,
            stockServings: 60,
            stockSetOn: "2026-09-20"
        )
        let current = [tick(product, .morning, "2026-09-20", recordedOn: "2026-09-20"), tick(product, .morning, "2026-09-21", recordedOn: "2026-09-21")]
        XCTAssertEqual(StockProjection.remainingServings(of: product, records: current), 58)

        let backfilled = current + SupplementDate.days(from: "2026-08-25", through: "2026-09-19").map {
            tick(product, .morning, $0, recordedOn: "2026-09-25")
        }

        XCTAssertEqual(StockProjection.remainingServings(of: product, records: backfilled), 58, "backfilling before the pack doesn't drain it")
    }

    func testLateEntriesGrantNoXP() {
        XCTAssertTrue(PastDayLogging.grantsXP(day: "2026-09-25", recordedOn: "2026-09-25"))
        XCTAssertTrue(PastDayLogging.grantsXP(day: "2026-09-18", recordedOn: "2026-09-25"), "7 days late still counts")
        XCTAssertFalse(PastDayLogging.grantsXP(day: "2026-09-17", recordedOn: "2026-09-25"), "8 days late: history only")
        XCTAssertFalse(PastDayLogging.grantsXP(day: "2026-08-25", recordedOn: "2026-09-25"))
        XCTAssertFalse(PastDayLogging.grantsXP(day: "garbage", recordedOn: "2026-09-25"))

        let product = SupplementProduct(name: "x", ingredients: [])
        XCTAssertFalse(PastDayLogging.grantsXP(tick(product, .morning, "2026-08-25", recordedOn: "2026-09-25")))
        let legacy = IntakeRecord(day: "2026-08-25", productId: product.id, slot: .morning, servings: 1, takenAt: takenAt, kind: .planned)
        XCTAssertTrue(PastDayLogging.grantsXP(legacy))
    }
}
