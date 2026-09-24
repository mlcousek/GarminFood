// SportRulesTests.swift
//
// add-sport-and-body-achievements design D1/D2/D7: activity classification
// (walking 44 vs 45 min, mobility excluded), fuel-window edges (29/30/180/
// 181 min), the carb-rich fallback, recovery summed across entries with
// unknown protein ignored, Earned It floor/ceiling/today/399 kcal, Gel Guru
// and Long Haul "strictly inside", Double Day, race days and Carb Loader
// with a missing carb goal. Pure functions over literal snapshots.

import XCTest
import FoodLogCore
@testable import Gamification

final class SportRulesTests: XCTestCase {
    private typealias F = SportFixtures

    // MARK: - D1 classification

    func testClassificationTable() {
        let cases: [(String, Double, SportActivityClass)] = [
            ("running", 30, .endurance),
            ("trail_running", 240, .endurance),
            ("treadmill_running", 25, .endurance),
            ("indoor_cycling", 45, .endurance),
            ("mountain_biking", 60, .endurance),
            ("hiking", 120, .endurance),
            ("lap_swimming", 40, .endurance),
            ("backcountry_skiing", 90, .endurance),
            ("indoor_rowing", 20, .endurance),
            ("walking", 44, .other),
            ("walking", 45, .endurance),
            ("strength_training", 40, .strength),
            ("mobility", 30, .other),
            ("yoga", 60, .other),
            ("breathwork", 25, .other),
            ("running", 19, .other),
            ("strength_training", 19, .other),
        ]
        for (typeKey, minutes, expected) in cases {
            XCTAssertEqual(SportActivityClass.classify(typeKey: typeKey, durationMinutes: minutes), expected, "\(typeKey) \(minutes) min")
        }
    }

    // MARK: - Fuel

    private let runStart = SportFixtures.at(2026, 9, 20, 7, 30)

    func testFuelWindowEdges() {
        func fuelled(minutesBefore: Double) -> Bool {
            let entry = F.entry("Ovesná kaše", at: runStart.addingTimeInterval(-minutesBefore * 60), carbs: 45)
            return SportRules.isFuelEntry(entry, before: runStart)
        }
        XCTAssertFalse(fuelled(minutesBefore: 29))
        XCTAssertTrue(fuelled(minutesBefore: 30))
        XCTAssertTrue(fuelled(minutesBefore: 180))
        XCTAssertFalse(fuelled(minutesBefore: 181))
    }

    func testFuelNeedsThirtyGramsWhenCarbsAreKnown() {
        let enough = F.entry("Ovesná kaše", at: runStart.addingTimeInterval(-90 * 60), carbs: 30)
        let tooLittle = F.entry("Ovesná kaše", at: runStart.addingTimeInterval(-90 * 60), carbs: 29)
        // Carbs known: the grams decide, even for a carb-rich food.
        let smallBanana = F.entry("Banán", at: runStart.addingTimeInterval(-90 * 60), carbs: 10)
        XCTAssertTrue(SportRules.isFuelEntry(enough, before: runStart))
        XCTAssertFalse(SportRules.isFuelEntry(tooLittle, before: runStart))
        XCTAssertFalse(SportRules.isFuelEntry(smallBanana, before: runStart))
    }

    func testUnknownCarbsFallBackToTheCarbRichTag() {
        let banana = F.entry("Banán", at: runStart.addingTimeInterval(-60 * 60), carbs: nil)
        let chicken = F.entry("Kuřecí prsa", at: runStart.addingTimeInterval(-60 * 60), carbs: nil)
        XCTAssertTrue(banana.has(.sportCarbRich))
        XCTAssertTrue(SportRules.isFuelEntry(banana, before: runStart))
        XCTAssertFalse(SportRules.isFuelEntry(chicken, before: runStart))
    }

    func testSpecScenarioFuelledRun() throws {
        // Porridge with 45 g carbs at 06:00, a 60-minute run at 07:30.
        let run = F.activity("run-1", "running", start: runStart, minutes: 60)
        let porridge = F.entry("Ovesná kaše", at: F.at(2026, 9, 20, 6, 0), carbs: 45)
        let evaluation = try XCTUnwrap(SportRules.evaluate(run, entries: [porridge]))
        XCTAssertTrue(evaluation.isFuelled)
        XCTAssertEqual(evaluation.fuelEntries, [porridge])
        XCTAssertEqual(evaluation.headlineFuelEntry, porridge)
    }

    func testStrengthIsNeverFuelled() throws {
        let gym = F.activity("gym", "strength_training", start: runStart, minutes: 45)
        let porridge = F.entry("Ovesná kaše", at: F.at(2026, 9, 20, 6, 0), carbs: 45)
        let evaluation = try XCTUnwrap(SportRules.evaluate(gym, entries: [porridge]))
        XCTAssertFalse(evaluation.isFuelled)
    }

    func testFuelLinksAcrossDaysByInstant() {
        // A run just after midnight fuelled by a late-evening snack on the
        // previous day.
        let start = F.at(2026, 9, 21, 0, 30)
        let run = F.activity("night", "trail_running", start: start, minutes: 90)
        let snack = F.entry("Rohlík", at: F.at(2026, 9, 20, 22, 30), carbs: 40)
        let snapshot = F.snapshot([
            F.day(F.key(2026, 9, 20), entries: [snack]),
            F.day(F.key(2026, 9, 21), activities: [run]),
        ], today: F.key(2026, 9, 21))
        XCTAssertEqual(SportRules.evaluations(in: snapshot).first?.isFuelled, true)
    }

    // MARK: - Recovery

    private let runEnd = SportFixtures.at(2026, 9, 20, 8, 30)

    private var sixtyMinuteRun: ActivitySummary {
        F.activity("run-r", "running", start: F.at(2026, 9, 20, 7, 30), minutes: 60)
    }

    func testRecoveryAcrossTwoEntries() throws {
        // Run ends 08:30; 12 g protein at 08:45 and 10 g at 09:15.
        let entries = [
            F.entry("Skyr", at: F.at(2026, 9, 20, 8, 45), protein: 12),
            F.entry("Vejce", at: F.at(2026, 9, 20, 9, 15), protein: 10),
        ]
        let evaluation = try XCTUnwrap(SportRules.evaluate(sixtyMinuteRun, entries: entries))
        XCTAssertEqual(evaluation.recoveryProteinGrams, 22, accuracy: 0.001)
        XCTAssertTrue(evaluation.isRecovered)
    }

    func testRecoveryWindowIsSixtyMinutes() throws {
        let entries = [
            F.entry("Skyr", at: F.at(2026, 9, 20, 8, 45), protein: 12),
            F.entry("Vejce", at: runEnd.addingTimeInterval(61 * 60), protein: 10),
        ]
        let evaluation = try XCTUnwrap(SportRules.evaluate(sixtyMinuteRun, entries: entries))
        XCTAssertFalse(evaluation.isRecovered)

        let atEdge = [F.entry("Tvaroh", at: runEnd.addingTimeInterval(60 * 60), protein: 20)]
        XCTAssertEqual(SportRules.evaluate(sixtyMinuteRun, entries: atEdge)?.isRecovered, true)
    }

    func testUnknownProteinIsIgnored() throws {
        let entries = [
            F.entry("Skyr", at: F.at(2026, 9, 20, 8, 45), protein: 12),
            F.entry("Něco", at: F.at(2026, 9, 20, 8, 50), protein: nil),
        ]
        let evaluation = try XCTUnwrap(SportRules.evaluate(sixtyMinuteRun, entries: entries))
        XCTAssertEqual(evaluation.recoveryEntries.count, 1)
        XCTAssertFalse(evaluation.isRecovered)
    }

    func testStrengthCountsForRecovery() throws {
        let gym = F.activity("gym", "strength_training", start: F.at(2026, 9, 20, 17, 0), minutes: 50)
        let shake = F.entry("Protein", at: gym.end.addingTimeInterval(10 * 60), protein: 25)
        XCTAssertEqual(SportRules.evaluate(gym, entries: [shake])?.isRecovered, true)
    }

    func testMobilitySessionDoesNotCount() {
        let mobility = F.activity("mob", "mobility", start: F.at(2026, 9, 20, 18, 0), minutes: 30)
        let protein = F.entry("Tvaroh", at: mobility.end.addingTimeInterval(10 * 60), protein: 30)
        XCTAssertNil(SportRules.evaluate(mobility, entries: [protein]))
    }

    // MARK: - Earned It

    private func earnedDay(intake: Double, activeKcal: Double = 1000, entries: Int = 3, goal: Double? = 2200, key: String? = nil) -> DaySignals {
        let dayKey = key ?? F.key(2026, 9, 20)
        let logs = (0..<entries).map { F.entry("Jídlo \($0)", at: F.at(2026, 9, 20, 8 + $0)) }
        return F.day(dayKey, entries: logs, activeKcal: activeKcal, goals: MacroGoals(calories: goal), caloriesTotal: intake)
    }

    func testEarnedItSpecScenarios() {
        let today = F.key(2026, 9, 24)
        XCTAssertTrue(SportRules.isEarnedDay(earnedDay(intake: 2600), today: today))
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 1500), today: today))
    }

    func testEarnedItFloorAndCeiling() {
        let today = F.key(2026, 9, 24)
        // Floor 0.8 x 2200 = 1760; ceiling 2200 + 0.5 x 1000 = 2700.
        XCTAssertTrue(SportRules.isEarnedDay(earnedDay(intake: 1760), today: today))
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 1759), today: today))
        XCTAssertTrue(SportRules.isEarnedDay(earnedDay(intake: 2700), today: today))
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 2701), today: today))
    }

    func testEarnedItNeedsACompletedActiveDayWithAGoal() {
        let today = F.key(2026, 9, 24)
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 2400, key: today), today: today), "not on the current day")
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 2200, activeKcal: 399), today: today))
        XCTAssertTrue(SportRules.isEarnedDay(earnedDay(intake: 2200, activeKcal: 400), today: today))
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 2400, entries: 2), today: today))
        XCTAssertFalse(SportRules.isEarnedDay(earnedDay(intake: 2400, goal: nil), today: today))
    }

    // MARK: - Gel Guru / Long Haul

    func testGelGuruNeedsThreeEntriesStrictlyInside() throws {
        let start = F.at(2026, 9, 20, 9, 0)
        let run = F.activity("long", "trail_running", start: start, minutes: 90)
        let inside = [20.0, 45.0, 70.0].map { F.entry("Gel", at: start.addingTimeInterval($0 * 60), carbs: 25) }
        XCTAssertEqual(SportRules.evaluate(run, entries: inside)?.isGelGuru, true)

        let edges = [
            F.entry("Gel", at: start, carbs: 25),
            F.entry("Gel", at: start.addingTimeInterval(45 * 60), carbs: 25),
            F.entry("Gel", at: run.end, carbs: 25),
        ]
        let evaluation = try XCTUnwrap(SportRules.evaluate(run, entries: edges))
        XCTAssertEqual(evaluation.duringEntries.count, 1)
        XCTAssertFalse(evaluation.isGelGuru)

        let short = F.activity("short", "running", start: start, minutes: 89)
        XCTAssertEqual(SportRules.evaluate(short, entries: inside)?.isGelGuru, false)
    }

    func testLongHaulNeedsThreeHoursAndOneEntryInside() {
        let start = F.at(2026, 9, 20, 9, 0)
        let gel = F.entry("Gel", at: start.addingTimeInterval(60 * 60), carbs: 25)
        let long = F.activity("ultra", "trail_running", start: start, minutes: 180)
        let shorter = F.activity("almost", "trail_running", start: start, minutes: 179)
        XCTAssertEqual(SportRules.evaluate(long, entries: [gel])?.isLongHaul, true)
        XCTAssertEqual(SportRules.evaluate(long, entries: [])?.isLongHaul, false)
        XCTAssertEqual(SportRules.evaluate(shorter, entries: [gel])?.isLongHaul, false)
    }

    // MARK: - Double Day

    func testDoubleDayNeedsTwoEnduranceActivitiesAndTheProteinGoal() {
        let key = F.key(2026, 9, 20)
        let morning = F.activity("am", "running", start: F.at(2026, 9, 20, 7), minutes: 40)
        let evening = F.activity("pm", "cycling", start: F.at(2026, 9, 20, 18), minutes: 60)
        let gym = F.activity("gym", "strength_training", start: F.at(2026, 9, 20, 18), minutes: 60)
        XCTAssertTrue(SportRules.isDoubleDay(F.day(key, activities: [morning, evening], goalStatus: F.goalsMet(protein: true))))
        XCTAssertFalse(SportRules.isDoubleDay(F.day(key, activities: [morning, evening], goalStatus: F.goalsMet(protein: false))))
        XCTAssertFalse(SportRules.isDoubleDay(F.day(key, activities: [morning, gym], goalStatus: F.goalsMet(protein: true))))
    }

    // MARK: - Race days

    func testRaceDayNeedsTheTagAndAnEntry() {
        let today = F.key(2026, 9, 24)
        let key = F.key(2026, 9, 20)
        let entry = F.entry("Gel", at: F.at(2026, 9, 20, 9))
        XCTAssertTrue(SportRules.isRaceDay(F.day(key, entries: [entry], noteTags: [.race]), today: today))
        XCTAssertFalse(SportRules.isRaceDay(F.day(key, noteTags: [.race]), today: today))
        XCTAssertFalse(SportRules.isRaceDay(F.day(key, entries: [entry], noteTags: [.training]), today: today))
    }

    func testCarbLoaderNeedsTheCarbGoalOnBothDaysBefore() {
        let race = F.day(F.key(2026, 9, 20), entries: [F.entry("Gel", at: F.at(2026, 9, 20, 9))], noteTags: [.race])
        func snapshot(_ first: DaySignals, _ second: DaySignals) -> SignalsSnapshot {
            F.snapshot([first, second, race], today: F.key(2026, 9, 21))
        }
        let met1 = F.day(F.key(2026, 9, 18), goals: MacroGoals(carbs: 300), goalStatus: F.goalsMet(carbs: true))
        let met2 = F.day(F.key(2026, 9, 19), goals: MacroGoals(carbs: 300), goalStatus: F.goalsMet(carbs: true))
        let missed2 = F.day(F.key(2026, 9, 19), goals: MacroGoals(carbs: 300), goalStatus: F.goalsMet(carbs: false))
        let noCarbGoal2 = F.day(F.key(2026, 9, 19), goals: MacroGoals(calories: 2200), goalStatus: F.goalsMet(carbs: true))
        let noStatus2 = F.day(F.key(2026, 9, 19))

        XCTAssertEqual(SportRules.carbLoadedRaceDays(in: snapshot(met1, met2), calendar: F.calendar), [race.day])
        XCTAssertTrue(SportRules.carbLoadedRaceDays(in: snapshot(met1, missed2), calendar: F.calendar).isEmpty)
        XCTAssertTrue(SportRules.carbLoadedRaceDays(in: snapshot(met1, noCarbGoal2), calendar: F.calendar).isEmpty)
        XCTAssertTrue(SportRules.carbLoadedRaceDays(in: snapshot(met1, noStatus2), calendar: F.calendar).isEmpty)
    }

    func testDayKeyArithmetic() {
        XCTAssertEqual(SportRules.dayKey("2026-03-01", offsetBy: -1, calendar: F.calendar), "2026-02-28")
        XCTAssertEqual(SportRules.dayKey("2026-12-31", offsetBy: 1, calendar: F.calendar), "2027-01-01")
        XCTAssertNil(SportRules.dayKey("garbage", offsetBy: 1, calendar: F.calendar))
    }
}
