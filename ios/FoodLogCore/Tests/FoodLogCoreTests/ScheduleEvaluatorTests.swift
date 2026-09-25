// ScheduleEvaluatorTests.swift
//
// add-supplements 1.2: every schedule pattern, cycles across phase
// boundaries, and edits that apply only from their day forward -- one test
// per spec scenario ("Schedules decide what is due each day") plus the
// edges around them.

import XCTest
@testable import FoodLogCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let creatine = SupplementProduct(name: "Creatine", ingredients: [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)])
    private let vitaminD = SupplementProduct(name: "D3", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 1000, unit: .iu)])
    private let magnesium = SupplementProduct(name: "Magnesium", ingredients: [IngredientAmount(ingredient: .magnesium, amount: 200, unit: .mg)])

    private func plan(_ entries: [(SupplementProduct, SupplementSchedule, String)]) -> SupplementPlan {
        var plan = SupplementPlan(products: entries.map { $0.0 })
        for (product, schedule, from) in entries {
            plan.setSchedule(schedule, for: product.id, from: from)
        }
        return plan
    }

    private func servings(_ plan: SupplementPlan, _ day: String, training: Set<String> = []) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for item in ScheduleEvaluator.due(on: day, plan: plan, trainingDays: training) {
            result[item.productId, default: 0] += item.servings
        }
        return result
    }

    // Spec: Creatine loading cycle.
    func testCreatineLoadingCycleThenMaintenance() {
        let schedule = SupplementSchedule(
            slots: [.morning],
            pattern: .cycle(phases: [CyclePhase(servingsPerSlot: 4, days: 7), CyclePhase(servingsPerSlot: 1, days: 1)], anchor: "2026-10-01", repeats: false)
        )
        let plan = plan([(creatine, schedule, "2026-10-01")])

        XCTAssertEqual(servings(plan, "2026-10-01")[creatine.id], 4)
        XCTAssertEqual(servings(plan, "2026-10-07")[creatine.id], 4)
        XCTAssertEqual(servings(plan, "2026-10-08")[creatine.id], 1)
        XCTAssertEqual(servings(plan, "2027-03-01")[creatine.id], 1, "without repeat the last phase continues")
        XCTAssertNil(servings(plan, "2026-09-30")[creatine.id], "nothing before the anchor")
    }

    func testRepeatingCycleOnAndOff() {
        // 8 weeks on, 4 off.
        let phases = [CyclePhase(servingsPerSlot: 1, days: 56), CyclePhase(servingsPerSlot: 0, days: 28)]
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: phases, offset: 55, repeats: true), 1)
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: phases, offset: 56, repeats: true), 0)
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: phases, offset: 83, repeats: true), 0)
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: phases, offset: 84, repeats: true), 1, "starts over")
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: phases, offset: -1, repeats: true), 0)
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: [], offset: 3, repeats: true), 0)
        XCTAssertEqual(ScheduleEvaluator.cycleServings(phases: [CyclePhase(servingsPerSlot: 2, days: 0)], offset: 0, repeats: false), 0)
    }

    // Spec: Every other day.
    func testEveryOtherDay() {
        let plan = plan([(vitaminD, SupplementSchedule(slots: [.morning], pattern: .everyNDays(n: 2, anchor: "2026-10-01")), "2026-09-01")])

        XCTAssertNotNil(servings(plan, "2026-10-01")[vitaminD.id])
        XCTAssertNil(servings(plan, "2026-10-02")[vitaminD.id])
        XCTAssertNotNil(servings(plan, "2026-10-03")[vitaminD.id])
        XCTAssertNil(servings(plan, "2026-09-29")[vitaminD.id], "not before its anchor")
    }

    func testChosenWeekdays() {
        // Monday, Wednesday, Friday.
        let plan = plan([(magnesium, SupplementSchedule(slots: [.evening], pattern: .weekdays([2, 4, 6])), "2026-10-01")])

        XCTAssertNotNil(servings(plan, "2026-10-05")[magnesium.id], "Monday")
        XCTAssertNil(servings(plan, "2026-10-06")[magnesium.id], "Tuesday")
        XCTAssertNotNil(servings(plan, "2026-10-09")[magnesium.id], "Friday")
        XCTAssertNil(servings(plan, "2026-10-11")[magnesium.id], "Sunday")
    }

    // Spec: Training days without activity data.
    func testTrainingDaysComeOnlyFromTheTrainingDaySet() {
        let plan = plan([(creatine, SupplementSchedule(slots: [.preWorkout], pattern: .trainingDays), "2026-10-01")])
        let raceDay: Set<String> = ["2026-10-18"]

        XCTAssertNotNil(servings(plan, "2026-10-18", training: raceDay)[creatine.id])
        XCTAssertNil(servings(plan, "2026-10-17", training: raceDay)[creatine.id])
        XCTAssertNil(servings(plan, "2026-10-19", training: raceDay)[creatine.id])
    }

    // Spec: Schedule edited.
    func testAScheduleEditDoesNotChangeEarlierDays() {
        var plan = plan([(magnesium, SupplementSchedule(slots: [.evening], pattern: .daily), "2026-09-01")])
        // On 2026-10-10 magnesium changes from daily to weekdays only.
        plan.setSchedule(SupplementSchedule(slots: [.evening], pattern: .weekdays([2, 3, 4, 5, 6])), for: magnesium.id, from: "2026-10-10")

        XCTAssertNotNil(servings(plan, "2026-10-04")[magnesium.id], "2026-10-04, a Sunday, still counts magnesium")
        XCTAssertNil(servings(plan, "2026-10-11")[magnesium.id], "2026-10-11, a Sunday, does not")
        XCTAssertNotNil(servings(plan, "2026-10-12")[magnesium.id], "Monday after the edit")
    }

    func testItemsAreOrderedBySlotThenStackOrderAndSlotsAreNotDoubled() {
        let plan = plan([
            (vitaminD, SupplementSchedule(slots: [.morning], servingsPerSlot: 1, pattern: .daily), "2026-10-01"),
            (creatine, SupplementSchedule(slots: [.evening, .morning, .morning], servingsPerSlot: 2, pattern: .daily), "2026-10-01")
        ])

        let due = ScheduleEvaluator.due(on: "2026-10-02", plan: plan, trainingDays: [])

        XCTAssertEqual(due, [
            DueItem(productId: vitaminD.id, slot: .morning, servings: 1),
            DueItem(productId: creatine.id, slot: .morning, servings: 2),
            DueItem(productId: creatine.id, slot: .evening, servings: 2)
        ])
    }

    func testRemovedUnknownAndOrphanedItemsAreNeverDue() {
        var plan = plan([
            (vitaminD, SupplementSchedule(slots: [.morning], pattern: .daily), "2026-10-01"),
            (magnesium, SupplementSchedule(slots: [.evening], pattern: .unknown("moonPhase")), "2026-10-01")
        ])
        plan.setSchedule(nil, for: vitaminD.id, from: "2026-10-05")
        // A schedule whose product no longer exists.
        plan.setSchedule(SupplementSchedule(slots: [.morning]), for: UUID(), from: "2026-10-01")

        XCTAssertEqual(ScheduleEvaluator.due(on: "2026-10-04", plan: plan, trainingDays: []).map(\.productId), [vitaminD.id])
        XCTAssertTrue(ScheduleEvaluator.due(on: "2026-10-05", plan: plan, trainingDays: []).isEmpty)
        XCTAssertTrue(ScheduleEvaluator.due(on: "garbage", plan: plan, trainingDays: []).isEmpty)
    }
}
