// WeeklyBingoEvaluatorTests.swift
//
// add-weekly-bingo task 2.4 (design D4, D5, D9): every catalog task is
// ticked by a literal week of `DaySignals` and NOT by plain days; squares
// only complete inside the card's week and up to today; completions are
// sticky; an unknown task id counts as FREE; the eight lines, four corners
// and the X. Pure -- no stores (the feature-level rewards live in
// WeeklyBingoFeatureTests).

import XCTest
import FoodLogCore
@testable import Gamification

final class WeeklyBingoEvaluatorTests: XCTestCase {
    private typealias F = BingoFixtures

    /// Whether `taskId`, alone on a one-square card, completes over `days`
    /// with today = Thursday (offset 3). Returns the completion day.
    private func completionDay(
        _ taskId: String,
        _ days: [DaySignals],
        firstSeenDayByFood: [String: String] = [:],
        firstSeenDayByCzechBrand: [String: String] = [:],
        today: String = BingoFixtures.key(3)
    ) -> String? {
        let snapshot = F.snapshot(
            days,
            today: today,
            firstSeenDayByFood: firstSeenDayByFood,
            firstSeenDayByCzechBrand: firstSeenDayByCzechBrand
        )
        return BingoEvaluator.completions(
            taskIds: [taskId],
            week: F.week,
            today: today,
            snapshot: snapshot,
            calendar: F.calendar,
            stored: [:]
        )[0]
    }

    private func tagged(_ tags: Set<FoodTag>, _ id: String = "food", on offset: Int = 1, meal: SignalMeal = .lunch) -> DaySignals {
        F.day(offset, [F.entry(id, tags, on: offset, meal: meal)])
    }

    private func entries(_ count: Int, _ tags: Set<FoodTag> = [], on offset: Int = 1) -> [SignalEntry] {
        (0..<count).map { F.entry("food-\(offset)-\($0)", tags, on: offset, hour: 10 + $0 % 8) }
    }

    private static let brandEntry = BingoFixtures.entry("kofola", [.czechBrand], on: 1, brand: "Kofola")

    /// One literal week (Mon..Thu at most) per task that must tick it.
    private func positiveCase(_ taskId: String) -> (days: [DaySignals], foods: [String: String], brands: [String: String])? {
        let plain = [F.plainDay(0), F.plainDay(2), F.plainDay(3)]
        switch taskId {
        case "e-early-log":
            return ([F.day(1, [F.entry("oats", on: 1, hour: 8, meal: .breakfast)])], [:], [:])
        case "e-fruit": return ([tagged([.fruit])] + plain, [:], [:])
        case "e-veg-lunch": return ([tagged([.vegetable], meal: .lunch)], [:], [:])
        case "e-three-meals":
            return ([F.day(1, [
                F.entry("oats", on: 1, hour: 8, meal: .breakfast),
                F.entry("rice", on: 1, hour: 12, meal: .lunch),
                F.entry("pasta", on: 1, hour: 18, meal: .dinner),
            ])], [:], [:])
        case "e-new-food": return ([tagged([], "kiwi")], ["kiwi": F.key(1)], [:])
        case "e-soup": return ([tagged([.soup])], [:], [:])
        case "e-tea": return ([tagged([.tea])], [:], [:])
        case "e-fermented": return ([tagged([.fermented])], [:], [:])
        case "e-nuts": return ([tagged([.nuts])], [:], [:])
        case "e-egg": return ([tagged([.egg])], [:], [:])
        case "m-fish": return ([tagged([.fish], "pstruh-na-masle")], [:], [:])
        case "m-three-fruits": return ([F.day(1, entries(3, [.fruit]))], [:], [:])
        case "m-water-goal": return ([F.day(1, entries(1), waterML: 2000, waterGoalML: 2000)], [:], [:])
        case "m-czech-brand":
            let key = SignalEvaluator.czechBrandKey(Self.brandEntry) ?? "kofola"
            return ([F.day(1, [Self.brandEntry])], [:], [key: F.key(1)])
        case "m-no-soda": return ([F.day(1, entries(3))], [:], [:])
        case "m-protein-2":
            return ([
                F.day(1, entries(1, on: 1), goalStatus: F.goals(protein: true)),
                F.day(2, entries(1, on: 2), goalStatus: F.goals(protein: true)),
            ], [:], [:])
        case "m-veg-breakfast": return ([tagged([.vegetable], meal: .breakfast)], [:], [:])
        case "m-legume": return ([tagged([.legume])], [:], [:])
        case "m-colours-4":
            return ([tagged([.colourRed, .colourOrange, .colourYellow, .colourGreen])], [:], [:])
        case "m-cuisine": return ([tagged([.cuisineItalian])], [:], [:])
        case "m-early-dinner":
            return ([F.day(1, [F.entry("soup", on: 1, hour: 18, meal: .dinner)])], [:], [:])
        case "m-whole-grain": return ([tagged([.wholeGrain])], [:], [:])
        case "m-refuel":
            return ([F.day(
                1,
                [F.entry("shake", on: 1, hour: 10, minute: 30, meal: .snack, protein: 25)],
                activities: [F.activity(on: 1, endHour: 10, minutes: 45)]
            )], [:], [:])
        case "m-calories-2":
            return ([
                F.day(1, entries(1, on: 1), goalStatus: F.goals(calories: true)),
                F.day(2, entries(1, on: 2), goalStatus: F.goals(calories: true)),
            ], [:], [:])
        case "h-fish-2": return ([tagged([.fish], on: 1), tagged([.seafood], "shrimp", on: 2)], [:], [:])
        case "h-protein-3":
            return ((1...3).map { F.day($0, entries(1, on: $0), goalStatus: F.goals(protein: true)) }, [:], [:])
        case "h-water-4":
            return ((0...3).map { F.day($0, entries(1, on: $0), waterML: 2500, waterGoalML: 2000) }, [:], [:])
        case "h-ten-foods": return ([F.day(1, entries(10))], [:], [:])
        case "h-meatless": return ([F.day(1, entries(3, [.vegetable]))], [:], [:])
        case "h-fibre-30": return ([F.day(1, [F.entry("bran", on: 1, fiber: 30)])], [:], [:])
        case "h-sugar-low": return ([F.day(1, entries(3))], [:], [:])
        case "h-five-a-day":
            return ([F.day(1, entries(3, [.fruit]) + [
                F.entry("carrot", [.vegetable], on: 1, hour: 19),
                F.entry("pepper", [.vegetable], on: 1, hour: 20),
            ])], [:], [:])
        case "h-rainbow":
            return ([
                tagged([.colourRed, .colourOrange, .colourYellow], "salad", on: 1),
                tagged([.colourGreen, .colourPurple, .colourWhite], "bowl", on: 2),
            ], [:], [:])
        case "h-earned-it":
            return ([F.day(
                1,
                entries(1),
                goalStatus: F.goals(calories: true),
                activities: [F.activity(on: 1, endHour: 8, minutes: 30)]
            )], [:], [:])
        case "h-clean-sweep":
            return ([F.day(1, entries(1), goalStatus: F.goals(calories: true, protein: true, carbs: true, fat: true))], [:], [:])
        default:
            return nil
        }
    }

    // MARK: - Every task

    func testEveryCatalogTaskHasAPositiveCaseThatTicksIt() {
        for task in BingoTaskCatalog.all {
            guard let input = positiveCase(task.id) else {
                XCTFail("no positive case for \(task.id)")
                continue
            }
            let day = completionDay(task.id, input.days, firstSeenDayByFood: input.foods, firstSeenDayByCzechBrand: input.brands)
            XCTAssertNotNil(day, task.id)
        }
    }

    func testPlainDaysTickNoTask() {
        let week = (0...3).map { F.plainDay($0) }
        for task in BingoTaskCatalog.all {
            XCTAssertNil(completionDay(task.id, week), task.id)
        }
    }

    func testWeekScopedTaskCompletesOnTheDayTheWeekFirstSatisfiedIt() {
        let days = [
            F.day(0, entries(1, on: 0), goalStatus: F.goals(protein: true)),
            F.plainDay(1),
            F.day(2, entries(1, on: 2), goalStatus: F.goals(protein: true)),
            F.day(3, entries(1, on: 3), goalStatus: F.goals(protein: true)),
        ]
        XCTAssertEqual(completionDay("m-protein-2", days), F.key(2))
        XCTAssertEqual(completionDay("h-protein-3", days), F.key(3))
    }

    func testDayScopedTaskRecordsTheFirstDayItHeld() {
        let days = [F.plainDay(0), tagged([.fish], on: 2), tagged([.fish], "carp", on: 3)]
        XCTAssertEqual(completionDay("m-fish", days), F.key(2))
    }

    // MARK: - Only this week, up to today

    func testFishTheSundayBeforeDoesNotTickThisWeeksCard() {
        let days = [tagged([.fish], on: -1), F.plainDay(0), F.plainDay(1)]
        XCTAssertNil(completionDay("m-fish", days))
    }

    func testDaysAfterTodayDoNotCount() {
        let days = [F.plainDay(0), tagged([.fish], on: 5)]
        XCTAssertNil(completionDay("m-fish", days, today: F.key(3)))
        XCTAssertEqual(completionDay("m-fish", days, today: F.key(5)), F.key(5))
    }

    func testWholeDaySquaresNeverTickOnTodaysUnfinishedDay() {
        // Three entries and no soda by lunchtime says nothing yet: a cola
        // at 20:00 would still spoil the day. Judged once the day is over.
        // Same for the calorie goal: it is a 95-105 % band, met for a while
        // mid-dinner and lost again after dessert. Last day of each
        // positive case -> the square may only tick the day after.
        let wholeDayCases: [(id: String, lastDay: Int)] = [
            ("m-no-soda", 1), ("m-early-dinner", 1), ("h-meatless", 1), ("h-sugar-low", 1),
            ("m-calories-2", 2), ("h-earned-it", 1), ("h-clean-sweep", 1),
        ]
        for (taskId, lastDay) in wholeDayCases {
            XCTAssertEqual(BingoTaskCatalog.task(id: taskId)?.judgesCompletedDaysOnly, true, taskId)
            guard let input = positiveCase(taskId) else { continue }
            XCTAssertNil(completionDay(taskId, input.days, today: F.key(lastDay)), "\(taskId) ticked on today's partial day")
            XCTAssertEqual(completionDay(taskId, input.days, today: F.key(lastDay + 1)), F.key(lastDay), taskId)
        }
        // An ordinary square still ticks the moment it holds.
        XCTAssertEqual(completionDay("m-fish", [tagged([.fish], on: 1)], today: F.key(1)), F.key(1))
    }

    func testSettlingLastWeekOnlyTouchesWholeDaySquares() {
        // Day 6 is the card week's Sunday; "today" is the next Monday.
        let sunday = F.day(6, entries(3, on: 6) + [F.entry("carp", [.fish], on: 6)])
        let snapshot = F.snapshot([sunday], today: F.key(7))
        let settled = BingoEvaluator.completions(
            taskIds: ["m-no-soda", "m-fish"],
            week: F.week,
            today: F.key(7),
            snapshot: snapshot,
            calendar: F.calendar,
            stored: [:],
            onlyCompletedDayTasks: true
        )
        XCTAssertEqual(settled[0], F.key(6), "Sunday's soda-free day is judged once the week is over")
        XCTAssertNil(settled[1], "other squares of a past card stay frozen as they were")
    }

    // MARK: - Sticky

    func testStoredCompletionsAreNeverRemoved() {
        let snapshot = F.snapshot([F.plainDay(1), F.plainDay(2)])
        let merged = BingoEvaluator.completions(
            taskIds: F.fixedCard,
            week: F.week,
            today: F.key(3),
            snapshot: snapshot,
            calendar: F.calendar,
            stored: [6: F.key(1)]
        )
        XCTAssertEqual(merged, [6: F.key(1)], "the fish square stays done after its entry is gone")
    }

    func testStoredCompletionDayIsNotRewrittenByALaterDay() {
        let snapshot = F.snapshot([tagged([.fish], on: 2)])
        let merged = BingoEvaluator.completions(
            taskIds: F.fixedCard,
            week: F.week,
            today: F.key(3),
            snapshot: snapshot,
            calendar: F.calendar,
            stored: [6: F.key(1)]
        )
        XCTAssertEqual(merged[6], F.key(1))
    }

    // MARK: - Free squares

    func testUnknownTaskIdIsTreatedAsFree() {
        XCTAssertTrue(BingoEvaluator.isFree(BingoTaskCatalog.freeId))
        XCTAssertTrue(BingoEvaluator.isFree("x-retired-task"))
        XCTAssertFalse(BingoEvaluator.isFree("e-fruit"))

        var card = F.fixedCard
        card[3] = "x-retired-task"
        // Nuts square replaced by an unknown id: soup alone completes row 2.
        let lines = BingoEvaluator.completedLines(taskIds: card, completed: [5: F.key(1)])
        XCTAssertEqual(lines.map(\.id), ["row1"])
        let merged = BingoEvaluator.completions(
            taskIds: card,
            week: F.week,
            today: F.key(3),
            snapshot: F.snapshot([F.plainDay(1)]),
            calendar: F.calendar,
            stored: [:]
        )
        XCTAssertNil(merged[3], "an unknown id never records a completion of its own")
    }

    // MARK: - Lines

    func testThereAreEightLinesWithStableIds() {
        XCTAssertEqual(BingoLine.all.map(\.id), ["row0", "row1", "row2", "col0", "col1", "col2", "diag0", "diag1"])
        XCTAssertEqual(Set(BingoLine.all.map(\.id)).count, 8)
        for line in BingoLine.all {
            XCTAssertEqual(BingoLine.line(id: line.id), line)
            XCTAssertFalse(line.displayName.isEmpty, line.id)
        }
    }

    func testFreeCentreCountsTowardTheMiddleRow() {
        let lines = BingoEvaluator.completedLines(taskIds: F.fixedCard, completed: [3: F.key(1), 5: F.key(2)])
        XCTAssertEqual(lines.map(\.id), ["row1"])
        XCTAssertFalse(BingoEvaluator.isFull(taskIds: F.fixedCard, completed: [3: F.key(1), 5: F.key(2)]))
    }

    func testNothingDoneMeansNoLines() {
        XCTAssertTrue(BingoEvaluator.completedLines(taskIds: F.fixedCard, completed: [:]).isEmpty)
    }

    func testFourCornersAlsoCompleteBothDiagonals() {
        let corners: [Int: String] = [0: F.key(0), 2: F.key(1), 6: F.key(2), 8: F.key(3)]
        XCTAssertTrue(BingoEvaluator.hasFourCorners(taskIds: F.fixedCard, completed: corners))
        let lines = BingoEvaluator.completedLines(taskIds: F.fixedCard, completed: corners)
        XCTAssertEqual(lines.map(\.id), ["diag0", "diag1"])
        XCTAssertFalse(BingoEvaluator.hasFourCorners(taskIds: F.fixedCard, completed: [0: F.key(0), 2: F.key(1), 6: F.key(2)]))
    }

    func testAllEightSquaresMakeAFullCardWithEveryLine() {
        var all: [Int: String] = [:]
        for index in 0..<9 where index != 4 { all[index] = F.key(1) }
        XCTAssertTrue(BingoEvaluator.isFull(taskIds: F.fixedCard, completed: all))
        XCTAssertEqual(BingoEvaluator.completedLines(taskIds: F.fixedCard, completed: all).count, 8)
    }

    // MARK: - Reward keys

    func testGrantKeysLiveInTheBingoNamespace() {
        let line = BingoLine.all[1]
        XCTAssertEqual(BingoEvaluator.lineGrantKey(week: F.week, line: line), "bingo.line.2026-W39.row1")
        XCTAssertEqual(BingoEvaluator.fullCardGrantKey(week: F.week), "bingo.full.2026-W39")
        XCTAssertEqual(BingoEvaluator.freezeGrantKey(week: F.week), "bingo.freeze.2026-W39")
        // FeatureHost drops any grant whose key is outside "<featureId>.".
        for key in [
            BingoEvaluator.lineGrantKey(week: F.week, line: line),
            BingoEvaluator.fullCardGrantKey(week: F.week),
            BingoEvaluator.freezeGrantKey(week: F.week),
        ] {
            XCTAssertTrue(key.hasPrefix(WeeklyBingoFeature.id + "."), key)
        }
    }
}
