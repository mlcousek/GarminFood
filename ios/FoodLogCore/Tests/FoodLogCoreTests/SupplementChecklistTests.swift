// SupplementChecklistTests.swift
//
// add-supplements 1.3: complete / partial / missed / neutral, extras never
// standing in for a planned item, slot completeness (what reminders and the
// Today card ask), and per-product adherence.

import XCTest
@testable import FoodLogCore

final class SupplementChecklistTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func product(_ name: String, _ ingredient: IngredientID) -> SupplementProduct {
        SupplementProduct(name: name, ingredients: [IngredientAmount(ingredient: ingredient, amount: 1, unit: ingredient.canonicalUnit)])
    }

    private func tick(_ product: SupplementProduct, _ slot: TimeSlot, _ day: String) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: slot, servings: 1, takenAt: takenAt, kind: .planned)
    }

    private func extra(_ product: SupplementProduct, _ day: String) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: nil, servings: 1, takenAt: takenAt, kind: .extra)
    }

    // Spec: One item missing.
    func testThreeOfFourPlusAnExtraIsNotComplete() {
        let items = [product("Creatine", .creatine), product("D3", .vitaminD), product("Omega", .omega3EPA_DHA), product("Mg", .magnesium)]
        let caffeine = product("Caffeine", .caffeine)
        var plan = SupplementPlan(products: items + [caffeine])
        for item in items { plan.setSchedule(SupplementSchedule(slots: [.morning]), for: item.id, from: "2026-10-01") }
        let records = items.prefix(3).map { tick($0, .morning, "2026-10-02") } + [extra(caffeine, "2026-10-02")]

        let checklist = SupplementChecklist(day: "2026-10-02", plan: plan, records: records, trainingDays: [])

        XCTAssertEqual(checklist.status, .partial)
        XCTAssertEqual(checklist.extras.count, 1)
        XCTAssertFalse(checklist.isComplete(.morning))
    }

    func testAnExtraOfAPlannedProductDoesNotTickIt() {
        let creatine = product("Creatine", .creatine)
        var plan = SupplementPlan(products: [creatine])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: creatine.id, from: "2026-10-01")

        let checklist = SupplementChecklist(day: "2026-10-02", plan: plan, records: [extra(creatine, "2026-10-02")], trainingDays: [])

        XCTAssertEqual(checklist.status, .missed)
    }

    // Spec: Nothing planned.
    func testNothingPlannedIsNeutral() {
        let creatine = product("Creatine", .creatine)
        var plan = SupplementPlan(products: [creatine])
        plan.setSchedule(SupplementSchedule(slots: [.morning], pattern: .weekdays([2])), for: creatine.id, from: "2026-10-01")

        let sunday = SupplementChecklist(day: "2026-10-04", plan: plan, records: [extra(creatine, "2026-10-04")], trainingDays: [])

        XCTAssertEqual(sunday.status, .neutral)
        XCTAssertTrue(sunday.slots.isEmpty)
        XCTAssertNil(sunday.currentSlot())
    }

    // Spec: Take all / Fix yesterday.
    func testTickingEveryItemCompletesTheDayAndOtherDaysDontCount() {
        let creatine = product("Creatine", .creatine)
        let vitaminD = product("D3", .vitaminD)
        let magnesium = product("Mg", .magnesium)
        var plan = SupplementPlan(products: [creatine, vitaminD, magnesium])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: creatine.id, from: "2026-10-01")
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: vitaminD.id, from: "2026-10-01")
        plan.setSchedule(SupplementSchedule(slots: [.evening]), for: magnesium.id, from: "2026-10-01")
        var records = [tick(creatine, .morning, "2026-10-02"), tick(vitaminD, .morning, "2026-10-02"), tick(magnesium, .evening, "2026-10-03")]

        var yesterday = SupplementChecklist(day: "2026-10-02", plan: plan, records: records, trainingDays: [])
        XCTAssertEqual(yesterday.status, .partial, "a tick on another day doesn't count")
        XCTAssertTrue(yesterday.isComplete(.morning))
        XCTAssertEqual(yesterday.currentSlot(), .evening)

        records.append(tick(magnesium, .evening, "2026-10-02"))
        yesterday = SupplementChecklist(day: "2026-10-02", plan: plan, records: records, trainingDays: [])
        XCTAssertEqual(yesterday.status, .complete)
        XCTAssertNil(yesterday.currentSlot())
    }

    // Spec: Slot variant after the morning.
    func testCurrentSlotPrefersTheNextDueSlot() {
        let vitaminD = product("D3", .vitaminD)
        let magnesium = product("Mg", .magnesium)
        var plan = SupplementPlan(products: [vitaminD, magnesium])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: vitaminD.id, from: "2026-10-01")
        plan.setSchedule(SupplementSchedule(slots: [.evening]), for: magnesium.id, from: "2026-10-01")

        let untouched = SupplementChecklist(day: "2026-10-02", plan: plan, records: [], trainingDays: [])
        XCTAssertEqual(untouched.currentSlot(), .morning)
        XCTAssertEqual(untouched.currentSlot(preferring: .evening), .evening)
        XCTAssertEqual(untouched.status, .missed)

        let morningDone = SupplementChecklist(day: "2026-10-02", plan: plan, records: [tick(vitaminD, .morning, "2026-10-02")], trainingDays: [])
        XCTAssertEqual(morningDone.currentSlot(preferring: .morning), .evening)
        XCTAssertEqual(morningDone.entries(in: .evening).map(\.item.productId), [magnesium.id])
    }

    // Spec: Partial adherence.
    func testAdherenceCountsPlannedOccurrencesPerProduct() {
        let creatine = product("Creatine", .creatine)
        let vitaminD = product("D3", .vitaminD)
        var plan = SupplementPlan(products: [creatine, vitaminD])
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: creatine.id, from: "2026-09-01")
        plan.setSchedule(SupplementSchedule(slots: [.morning], pattern: .everyNDays(n: 2, anchor: "2026-09-01")), for: vitaminD.id, from: "2026-09-01")
        let days = SupplementDate.days(from: "2026-09-01", through: "2026-09-30")
        let missedDays: Set<String> = ["2026-09-03", "2026-09-10", "2026-09-20"]
        let records = days.filter { !missedDays.contains($0) }.map { tick(creatine, .morning, $0) }

        let adherence = SupplementAdherence.over(days: days, productId: creatine.id, plan: plan, records: records, trainingDays: [])

        XCTAssertEqual(adherence, SupplementAdherence(planned: 30, taken: 27))
        XCTAssertEqual(adherence.percent, 90)
        let stack = SupplementAdherence.over(days: days, productId: nil, plan: plan, records: records, trainingDays: [])
        XCTAssertEqual(stack.planned, 45, "30 creatine + 15 every-other-day D3")
        XCTAssertNil(SupplementAdherence(planned: 0, taken: 0).percent)
    }
}
