// DayPredicateTests.swift
//
// add-gamification-signals 5.3: one test per `DayPredicate` case (incl.
// the data-missing -> unknown path), the `requirement` mapping, and the
// `WeekPredicate` span rules.

import XCTest
import FoodLogCore
@testable import Gamification

final class DayPredicateTests: XCTestCase {
    private let calendar = SignalFixtures.calendar
    private typealias F = SignalFixtures

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 22) -> Date {
        TestClock.date(2026, 9, day, hour: hour, minute: minute)
    }

    private func eval(_ predicate: DayPredicate, _ day: DaySignals, history: SignalsSnapshot? = nil) -> Bool? {
        SignalEvaluator.evaluate(predicate, on: day, history: history ?? F.snapshot([day]), calendar: calendar)
    }

    func testHasTagAndCounts() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("salmon", tags: [.fish], at: at(12)),
            F.entry("apple", tags: [.fruit, .colourRed], at: at(15)),
            F.entry("pear", tags: [.fruit, .colourGreen], at: at(16)),
            F.entry("carrot", tags: [.vegetable, .colourOrange], at: at(18)),
        ])
        XCTAssertEqual(eval(.hasTag(.fish), day), true)
        XCTAssertEqual(eval(.hasTag(.nuts), day), false)
        XCTAssertEqual(eval(.tagCountAtLeast(.fruit, 2), day), true)
        XCTAssertEqual(eval(.tagCountAtLeast(.fruit, 3), day), false)
        XCTAssertEqual(eval(.anyTagCountAtLeast([.fruit, .vegetable], 3), day), true)
        XCTAssertEqual(eval(.anyTagCountAtLeast([.fruit, .vegetable], 4), day), false)
        XCTAssertEqual(eval(.distinctTagsAtLeast(prefix: FoodTag.colourPrefix, 3), day), true)
        XCTAssertEqual(eval(.distinctTagsAtLeast(prefix: FoodTag.colourPrefix, 4), day), false)
    }

    func testNoTagNeedsEnoughEntries() {
        let soda = F.day(2026, 9, 22, entries: [
            F.entry("kofola", tags: [.sugaryDrink], at: at(12)),
            F.entry("bread", at: at(13)),
        ])
        let clean = F.day(2026, 9, 22, entries: [F.entry("bread", at: at(12)), F.entry("ham", at: at(13))])
        let thin = F.day(2026, 9, 22, entries: [F.entry("bread", at: at(12))])
        XCTAssertEqual(eval(.noTag(.sugaryDrink, minEntries: 2), soda), false)
        XCTAssertEqual(eval(.noTag(.sugaryDrink, minEntries: 2), clean), true)
        XCTAssertNil(eval(.noTag(.sugaryDrink, minEntries: 2), thin))
    }

    func testMealRules() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("spinach", tags: [.vegetable], at: at(8), meal: .breakfast),
            F.entry("cake", tags: [.sweets], at: at(15), meal: .snack),
        ])
        XCTAssertEqual(eval(.tagInMeal(.vegetable, .breakfast), day), true)
        XCTAssertEqual(eval(.tagInMeal(.vegetable, .snack), day), false)
        XCTAssertEqual(eval(.mealLogged(.snack), day), true)
        XCTAssertEqual(eval(.mealLogged(.dinner), day), false)
    }

    func testFirstAndLastLogTimes() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("coffee", at: at(8, 30)),
            F.entry("dinner", at: at(19, 45)),
        ])
        XCTAssertEqual(eval(.firstLogBefore(hour: 9, minute: 0), day), true)
        XCTAssertEqual(eval(.firstLogBefore(hour: 8, minute: 0), day), false)
        XCTAssertEqual(eval(.lastLogBefore(hour: 20, minute: 0), day), true)
        XCTAssertEqual(eval(.lastLogBefore(hour: 19, minute: 30), day), false)

        // An entry after midnight that belongs to this nutrition day is late.
        let lateNight = F.day(2026, 9, 22, entries: [
            F.entry("toast", at: at(12)),
            F.entry("snack", at: TestClock.date(2026, 9, 23, hour: 1)),
        ])
        XCTAssertEqual(eval(.lastLogBefore(hour: 20, minute: 0), lateNight), false)

        let empty = F.day(2026, 9, 22, waterML: 500)
        XCTAssertEqual(eval(.firstLogBefore(hour: 9, minute: 0), empty), false)
    }

    func testDistinctFoods() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("a", at: at(10)), F.entry("a", at: at(11)), F.entry("b", at: at(12)),
        ])
        XCTAssertEqual(eval(.distinctFoodsAtLeast(2), day), true)
        XCTAssertEqual(eval(.distinctFoodsAtLeast(3), day), false)
    }

    func testGoalMetUsesCachedStatusElseUnknown() {
        let status = SignalGoalStatus(metCalorieGoal: true, metProteinGoal: false, metCarbGoal: false, metFatGoal: true)
        let day = F.day(2026, 9, 22, entries: [F.entry("x", at: at(12))], goalStatus: status)
        XCTAssertEqual(eval(.goalMet(.calories), day), true)
        XCTAssertEqual(eval(.goalMet(.protein), day), false)
        XCTAssertNil(eval(.goalMet(.calories), F.day(2026, 9, 22, entries: [F.entry("x", at: at(12))])))
    }

    func testMacroThresholdsAndUnknownFibre() {
        let rich = F.day(2026, 9, 22, entries: [
            F.entry("oats", at: at(8), fiber: 12, sugar: 5),
            F.entry("beans", at: at(13), fiber: 20, sugar: 2),
            F.entry("apple", at: at(16), fiber: 3, sugar: 15),
        ])
        XCTAssertEqual(eval(.macroAtLeast(.fiber, grams: 30), rich), true)
        XCTAssertEqual(eval(.macroAtLeast(.fiber, grams: 40), rich), false)
        XCTAssertEqual(eval(.macroAtMost(.sugar, grams: 40, minEntries: 3), rich), true)
        XCTAssertEqual(eval(.macroAtMost(.sugar, grams: 20, minEntries: 3), rich), false)
        XCTAssertNil(eval(.macroAtMost(.sugar, grams: 40, minEntries: 4), rich))

        let unknownFibre = F.day(2026, 9, 22, entries: [
            F.entry("oats", at: at(8), fiber: 40),
            F.entry("mystery", at: at(13), fiber: nil),
        ])
        XCTAssertNil(eval(.macroAtLeast(.fiber, grams: 30), unknownFibre))
        XCTAssertFalse(SignalEvaluator.holds(.macroAtLeast(.fiber, grams: 30), on: unknownFibre,
                                             history: F.snapshot([unknownFibre]), calendar: calendar))
    }

    func testMealMacroAtLeast() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("eggs", at: at(7), meal: .breakfast, protein: 14),
            F.entry("skyr", at: at(8), meal: .breakfast, protein: 9),
            F.entry("steak", at: at(19), meal: .dinner, protein: 40),
        ])
        XCTAssertEqual(eval(.mealMacroAtLeast(.breakfast, .protein, grams: 20), day), true)
        XCTAssertEqual(eval(.mealMacroAtLeast(.breakfast, .protein, grams: 30), day), false)
        XCTAssertEqual(eval(.mealMacroAtLeast(.lunch, .protein, grams: 1), day), false)
        let unknown = F.day(2026, 9, 22, entries: [
            F.entry("eggs", at: at(7), meal: .breakfast, protein: 14),
            F.entry("mystery", at: at(8), meal: .breakfast, protein: nil),
        ])
        XCTAssertNil(eval(.mealMacroAtLeast(.breakfast, .protein, grams: 20), unknown))
        XCTAssertEqual(DayPredicate.mealMacroAtLeast(.breakfast, .protein, grams: 20).requirement, .macros)
    }

    func testWaterGoal() {
        XCTAssertEqual(eval(.waterGoalMet, F.day(2026, 9, 22, waterML: 2600, waterGoalML: 2500)), true)
        XCTAssertEqual(eval(.waterGoalMet, F.day(2026, 9, 22, waterML: 1200, waterGoalML: 2500)), false)
        XCTAssertNil(eval(.waterGoalMet, F.day(2026, 9, 22, entries: [F.entry("x", at: at(12))])))
        XCTAssertNil(eval(.waterGoalMet, F.day(2026, 9, 22, waterML: 1200, waterGoalML: nil)))
    }

    func testActivityRules() {
        let run = ActivitySummary(id: "1", typeKey: "running", day: F.dayKey(2026, 9, 22),
                                  start: at(17), durationS: 45 * 60)
        let day = F.day(2026, 9, 22, entries: [
            F.entry("shake", at: at(18), protein: 25),
            F.entry("bread", at: at(20), protein: 5),
        ], activities: [run])
        XCTAssertEqual(eval(.hasActivity(minMinutes: 30), day), true)
        XCTAssertEqual(eval(.hasActivity(minMinutes: 60), day), false)
        XCTAssertEqual(eval(.proteinAfterActivity(grams: 20, withinMinutes: 60), day), true)
        XCTAssertEqual(eval(.proteinAfterActivity(grams: 30, withinMinutes: 60), day), false)

        let unknownProtein = F.day(2026, 9, 22, entries: [F.entry("shake", at: at(18), protein: nil)],
                                   activities: [run])
        XCTAssertNil(eval(.proteinAfterActivity(grams: 20, withinMinutes: 60), unknownProtein))

        let noActivityData = F.day(2026, 9, 22, entries: [F.entry("x", at: at(12))])
        XCTAssertNil(eval(.hasActivity(minMinutes: 1), noActivityData))
        XCTAssertEqual(eval(.hasActivity(minMinutes: 1), F.day(2026, 9, 22, activities: [])), false)
    }

    func testNewFoodAndNewCzechBrand() {
        let day = F.day(2026, 9, 22, entries: [
            F.entry("old", at: at(10)),
            F.entry("kofola", tags: [.czechBrand, .sugaryDrink], at: at(12), brand: "Kofola"),
        ])
        let history = F.snapshot([day],
                                 firstSeenDayByFood: ["old": "2026-08-01", "kofola": "2026-09-22"],
                                 firstSeenDayByCzechBrand: ["kofola": "2026-09-22"])
        XCTAssertEqual(eval(.newFood, day, history: history), true)
        XCTAssertEqual(eval(.newCzechBrand, day, history: history), true)

        let seenBefore = F.snapshot([day],
                                    firstSeenDayByFood: ["old": "2026-08-01", "kofola": "2026-08-02"],
                                    firstSeenDayByCzechBrand: ["kofola": "2026-08-02"])
        XCTAssertEqual(eval(.newFood, day, history: seenBefore), false)
        XCTAssertEqual(eval(.newCzechBrand, day, history: seenBefore), false)
    }

    func testAllAndAnyPropagateUnknown() {
        let day = F.day(2026, 9, 22, entries: [F.entry("salmon", tags: [.fish], at: at(12))])
        XCTAssertEqual(eval(.all([.hasTag(.fish), .mealLogged(.lunch)]), day), true)
        XCTAssertEqual(eval(.all([.hasTag(.fish), .hasTag(.nuts)]), day), false)
        XCTAssertNil(eval(.all([.hasTag(.fish), .waterGoalMet]), day))
        XCTAssertEqual(eval(.all([.hasTag(.nuts), .waterGoalMet]), day), false)
        XCTAssertEqual(eval(.any([.hasTag(.nuts), .hasTag(.fish)]), day), true)
        XCTAssertNil(eval(.any([.hasTag(.nuts), .waterGoalMet]), day))
        XCTAssertEqual(eval(.any([.hasTag(.nuts), .hasTag(.egg)]), day), false)
    }

    func testRequirements() {
        XCTAssertEqual(DayPredicate.hasTag(.fish).requirement, [])
        XCTAssertEqual(DayPredicate.macroAtLeast(.fiber, grams: 30).requirement, .macros)
        XCTAssertEqual(DayPredicate.waterGoalMet.requirement, .water)
        XCTAssertEqual(DayPredicate.hasActivity(minMinutes: 30).requirement, .activities)
        XCTAssertEqual(DayPredicate.all([.waterGoalMet, .hasActivity(minMinutes: 1)]).requirement,
                       [.water, .activities])
        XCTAssertEqual(WeekPredicate.daysSatisfying(.waterGoalMet, atLeast: 5).requirement, .water)

        let noWater = F.day(2026, 9, 22, entries: [F.entry("x", at: at(12))])
        XCTAssertFalse(DataRequirement.water.isSatisfied(byAnyOf: [noWater]))
        XCTAssertTrue(DataRequirement.water.isSatisfied(byAnyOf: [noWater, F.day(2026, 9, 23, waterML: 300)]))
        XCTAssertTrue(DataRequirement().isSatisfied(byAnyOf: []))
        XCTAssertTrue(DataRequirement.macros.isSatisfied(by: noWater))
    }

    func testWeekPredicates() {
        let monday = F.day(2026, 9, 21, entries: [
            F.entry("salmon", tags: [.fish, .colourOrange], at: TestClock.date(2026, 9, 21)),
            F.entry("kofola", tags: [.czechBrand], at: TestClock.date(2026, 9, 21, hour: 13), brand: "Kofola"),
        ])
        let friday = F.day(2026, 9, 25, entries: [
            F.entry("tuna", tags: [.fish, .colourRed], at: TestClock.date(2026, 9, 25)),
            F.entry("madeta", tags: [.czechBrand], at: TestClock.date(2026, 9, 25, hour: 13), brand: "Madeta"),
            F.entry("kofola", tags: [.czechBrand], at: TestClock.date(2026, 9, 25, hour: 14), brand: "KOFOLA"),
        ])
        let days = [monday, friday]
        let history = F.snapshot(days, firstSeenDayByFood: ["salmon": monday.day, "tuna": "2026-01-01",
                                                            "kofola": "2026-01-01", "madeta": friday.day])
        func progress(_ p: WeekPredicate) -> Int {
            SignalEvaluator.progress(p, over: days, history: history, calendar: calendar)
        }
        XCTAssertEqual(progress(.daysSatisfying(.hasTag(.fish), atLeast: 2)), 2)
        XCTAssertTrue(SignalEvaluator.holds(.daysSatisfying(.hasTag(.fish), atLeast: 2),
                                            over: days, history: history, calendar: calendar))
        XCTAssertEqual(progress(.distinctTagsAcrossWeek(prefix: FoodTag.colourPrefix, atLeast: 6)), 2)
        XCTAssertEqual(progress(.distinctCzechBrandsAtLeast(3)), 2) // "Kofola" == "KOFOLA"
        XCTAssertEqual(progress(.newFoodsAtLeast(5)), 2)
        XCTAssertEqual(progress(.daysSatisfying(.hasTag(.fish), atLeast: 1)), 1) // capped at target
    }
}
