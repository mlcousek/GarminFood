// PersonalRecordsTests.swift
//
// add-journeys-and-records design D6/D10 / tasks 3.5: every metric from
// literal `DaySignals`; protein PR once per day; lowest-sugar judged on a
// closed day only; off-target days ignored; 48 h fast cap; warm-up; silent
// first run; hidden records; streak carried across sealing; store decode.

import XCTest
import FoodLogCore
@testable import Gamification

final class PersonalRecordsTests: XCTestCase {
    // MARK: - Metrics

    func testPerDayMetrics() {
        let day = JR.day(5, entries: [
            JR.entry("apple", day: 5, hour: 8, tags: [.fruit], protein: 40),
            JR.entry("carrot", day: 5, hour: 9, tags: [.vegetable], protein: 60),
            JR.entry("apple", day: 5, hour: 10, tags: [.fruit, .vegetable], protein: 0),
            JR.entry("bread", day: 5, hour: 11, protein: 10),
        ], waterML: 2_500, activeKcal: 640)
        XCTAssertEqual(PersonalRecordCatalog.proteinGrams(day), 110)
        XCTAssertEqual(PersonalRecordCatalog.fruitVegEntries(day), 3, "an entry with both tags counts once")
        XCTAssertEqual(PersonalRecordCatalog.distinctFoods(day), 3)
        XCTAssertEqual(PersonalRecordCatalog.waterML(day), 2_500)
        XCTAssertEqual(PersonalRecordCatalog.activeKcal(day), 640)
        XCTAssertNil(PersonalRecordCatalog.proteinGrams(JR.day(6, waterML: 100)), "no entries = no protein day")
    }

    func testOnTargetSugar() {
        func threeEntries(_ dayOfMonth: Int, calories: Double, sugar: Double) -> [SignalEntry] {
            (0..<3).map { JR.entry("f\($0)", day: dayOfMonth, hour: 8 + $0 * 4, calories: calories / 3, sugar: sugar / 3) }
        }
        let onTarget = JR.day(5, entries: threeEntries(5, calories: 1_950, sugar: 12), calorieGoal: 2_000)
        XCTAssertEqual(PersonalRecordCatalog.onTargetSugarGrams(onTarget) ?? -1, 12, accuracy: 0.0001)

        let offTarget = JR.day(6, entries: threeEntries(6, calories: 1_200, sugar: 5), calorieGoal: 2_000)
        XCTAssertNil(PersonalRecordCatalog.onTargetSugarGrams(offTarget), "40 % under the goal is not on target")

        let twoEntries = JR.day(7, entries: Array(threeEntries(7, calories: 1_950, sugar: 12).prefix(2)), calorieGoal: 1_300)
        XCTAssertNil(PersonalRecordCatalog.onTargetSugarGrams(twoEntries), "fewer than 3 entries")

        let noGoal = JR.day(8, entries: threeEntries(8, calories: 1_950, sugar: 12))
        XCTAssertNil(PersonalRecordCatalog.onTargetSugarGrams(noGoal))
    }

    func testLongestFastIgnoresGapsOver48Hours() {
        let snapshot = JR.snapshot([
            JR.day(1, entries: [JR.entry("a", day: 1, hour: 20)]),
            JR.day(2, entries: [JR.entry("b", day: 2, hour: 12), JR.entry("c", day: 2, hour: 18)]),
            // Nothing logged on days 3-5: 72 h later.
            JR.day(5, entries: [JR.entry("d", day: 5, hour: 18)]),
        ], today: 10)
        let hours = RecordsEvaluator.longestFastHours(snapshot)
        XCTAssertEqual(hours[JR.key(2)] ?? 0, 16, accuracy: 0.0001, "20:00 -> 12:00 next day")
        XCTAssertNil(hours[JR.key(5)], "a 72 h gap is unlogged days, not a fast")
        XCTAssertNil(hours[JR.key(1)], "the first entry ends no fast")
    }

    func testWaterStreakRuns() {
        func water(_ d: Int, _ ml: Double) -> DaySignals { JR.day(d, waterML: ml, waterGoalML: 1_500) }
        let snapshot = JR.snapshot([
            water(1, 2_000), water(2, 2_000), water(3, 1_600), water(4, 1_000), water(5, 2_000), water(6, 2_000),
        ], today: 7)
        let values = RecordsEvaluator.dayValues(.waterStreak, snapshot: snapshot)
        XCTAssertEqual(values[JR.key(3)], 3)
        XCTAssertEqual(values[JR.key(4)], 0)
        XCTAssertEqual(values[JR.key(6)], 2)
        XCTAssertNil(values[JR.key(7)], "no water data = not a qualifying day")
    }

    func testWaterStreakCarriesAcrossSealedDays() {
        func water(_ d: Int) -> DaySignals { JR.day(d, waterML: 2_000, waterGoalML: 1_500) }
        var state = RecordsEvaluator.evaluate(state: RecordsState(), snapshot: JR.snapshot((1...10).map(water), today: 10)).state
        XCTAssertEqual(state.waterStreakCarry, WaterStreakCarry(day: JR.key(7), length: 7))
        // Later the window no longer reaches back to day 1.
        state = RecordsEvaluator.evaluate(state: state, snapshot: JR.snapshot((5...14).map(water), from: 5, today: 14)).state
        XCTAssertEqual(state.record(.waterStreak).current?.value, 14)
    }

    // MARK: - Announcing

    func testProteinPRDuringTheDayIsAnnouncedOnce() async {
        let feature = PersonalRecordsFeature(directory: JR.tempDirectory())
        var history = (1...9).map { JR.protein($0, 150) }
        history[4] = JR.protein(5, 171)

        // First run: silent baseline.
        let baseline = await feature.update(JR.context(JR.snapshot(history + [JR.protein(10, 100)], today: 10), today: 10, hour: 9))
        XCTAssertTrue(baseline.moments.isEmpty)
        XCTAssertTrue(baseline.grants.isEmpty)

        // Today passes 171 g: one PR.
        let first = await feature.update(JR.context(JR.snapshot(history + [JR.protein(10, 175)], today: 10), today: 10, hour: 13))
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(first.moments.first?.style, .record)
        XCTAssertEqual(first.moments.first?.xpAwarded, 20)
        XCTAssertEqual(first.grants, [RewardGrant(key: "records.protein-day.\(JR.key(10))", kind: .xp(20))])
        XCTAssertTrue(first.unlockBadgeIds.contains("record.first-pr"))

        // Later the same day 186 g: no second moment, same single grant key.
        let later = await feature.update(JR.context(JR.snapshot(history + [JR.protein(10, 186)], today: 10), today: 10, hour: 19))
        XCTAssertTrue(later.moments.isEmpty)
        XCTAssertEqual(later.grants.map(\.key), ["records.protein-day.\(JR.key(10))"])

        let protein = await feature.records().first { $0.definition.id == .proteinDay }
        XCTAssertEqual(protein?.value, 186)
        XCTAssertEqual(protein?.day, JR.key(10))
        XCTAssertEqual(protein?.previousValue, 171)
        XCTAssertEqual(protein?.previousDay, JR.key(5))
        XCTAssertEqual(protein?.isRecentPR, true)
    }

    func testLowestSugarIsJudgedOnlyOnceTheDayIsClosed() {
        func onTarget(_ d: Int, sugar: Double) -> DaySignals {
            JR.day(d, entries: ["a", "b", "c"].enumerated().map { index, id in
                JR.entry(id, day: d, hour: 8 + index * 5, calories: 650, sugar: sugar / 3)
            }, calorieGoal: 2_000)
        }
        let history = (1...8).map { onTarget($0, sugar: 30) }
        var result = RecordsEvaluator.evaluate(state: RecordsState(), snapshot: JR.snapshot(history, today: 9))
        XCTAssertEqual(result.state.record(.lowSugarOnTarget).current?.value ?? 0, 30, accuracy: 0.0001)

        // Today (still open) is a 10 g day: not judged yet.
        result = RecordsEvaluator.evaluate(state: result.state, snapshot: JR.snapshot(history + [onTarget(9, sugar: 10)], today: 9))
        XCTAssertTrue(result.announced.isEmpty)
        XCTAssertEqual(result.state.record(.lowSugarOnTarget).current?.value ?? 0, 30, accuracy: 0.0001)

        // The next day it is closed: announced once.
        result = RecordsEvaluator.evaluate(state: result.state, snapshot: JR.snapshot(history + [onTarget(9, sugar: 10)], today: 10))
        XCTAssertEqual(result.announced.map(\.id), [.lowSugarOnTarget])
        XCTAssertEqual(result.announced.first?.day, JR.key(9))
        XCTAssertEqual(result.announced.first?.previousValue ?? 0, 30, accuracy: 0.0001)
    }

    func testOffTargetLowSugarDayIsIgnored() {
        let offTarget = JR.day(9, entries: (0..<3).map { JR.entry("x\($0)", day: 9, hour: 8 + $0, calories: 400, sugar: 1) }, calorieGoal: 2_000)
        let values = RecordsEvaluator.dayValues(.lowSugarOnTarget, snapshot: JR.snapshot([offTarget], today: 10))
        XCTAssertTrue(values.isEmpty)
    }

    func testWarmUpUpdatesSilently() {
        let first = RecordsEvaluator.evaluate(
            state: RecordsState(),
            snapshot: JR.snapshot([JR.day(7, waterML: 1_000), JR.day(8, waterML: 1_200), JR.day(9, waterML: 1_100)], today: 10)
        )
        let second = RecordsEvaluator.evaluate(
            state: first.state,
            snapshot: JR.snapshot([JR.day(7, waterML: 1_000), JR.day(8, waterML: 1_200), JR.day(9, waterML: 1_100), JR.day(10, waterML: 5_000)], today: 10)
        )
        XCTAssertEqual(second.state.record(.waterDay).qualifyingDays, 4)
        XCTAssertEqual(second.state.record(.waterDay).current?.value, 5_000)
        XCTAssertTrue(second.announced.isEmpty, "only 4 qualifying days: no moment yet")
    }

    func testFirstRunSetsEverythingSilently() async {
        let feature = PersonalRecordsFeature(directory: JR.tempDirectory())
        let days = (1...42).map { d in
            JR.day(d, entries: [JR.entry("f\(d)", day: d, hour: 8, tags: [.fruit], protein: Double(d)), JR.entry("g", day: d, hour: 19)],
                   waterML: Double(1_000 + d * 60), waterGoalML: 1_500, activeKcal: Double(d * 10))
        }
        let update = await feature.update(JR.context(JR.snapshot(days, from: 1, today: 42), today: 42))
        XCTAssertTrue(update.moments.isEmpty)
        XCTAssertTrue(update.grants.isEmpty)
        XCTAssertTrue(update.unlockBadgeIds.isEmpty)
        let records = await feature.records()
        XCTAssertEqual(records.first { $0.definition.id == .proteinDay }?.value, 47, "42 g + the 5 g default entry")
        XCTAssertEqual(records.first { $0.definition.id == .waterDay }?.value, 1_000 + 42 * 60)
        XCTAssertTrue(records.filter(\.isVisible).count >= 6)
    }

    func testRecordsWithoutDataAreHidden() async {
        let feature = PersonalRecordsFeature(directory: JR.tempDirectory())
        _ = await feature.update(JR.context(JR.snapshot([JR.protein(8, 100), JR.protein(9, 120)], today: 10), today: 10))
        let byId = Dictionary(uniqueKeysWithValues: await feature.records().map { ($0.definition.id, $0) })
        XCTAssertEqual(byId[.proteinDay]?.isVisible, true)
        XCTAssertEqual(byId[.waterDay]?.isVisible, false)
        XCTAssertEqual(byId[.activeKcalDay]?.isVisible, false)
        XCTAssertNil(byId[.waterDay]?.valueText, "never shown as zero")
    }

    // MARK: - Badges, keys, store

    func testBadges() {
        var state = RecordsState()
        XCTAssertTrue(RecordsEvaluator.earnedBadgeIds(state).isEmpty)
        var records: [String: PersonalRecordState] = [:]
        for id in PersonalRecordId.allCases.prefix(6) {
            records[id.rawValue] = PersonalRecordState(current: RecordMark(value: 10, day: JR.key(1)), prCount: 2)
        }
        state.records = records
        XCTAssertEqual(Set(RecordsEvaluator.earnedBadgeIds(state)), ["record.first-pr", "record.pr-10", "record.full-house"])

        let feature = PersonalRecordsFeature(directory: JR.tempDirectory())
        XCTAssertTrue(feature.badges.allSatisfy { $0.id.hasPrefix("record.") && $0.condition == .featureEvaluated })
        XCTAssertEqual(feature.badges.count, 4)
    }

    func testGrantKeyIsInsideTheFeatureNamespace() {
        XCTAssertEqual(PersonalRecordsFeature.grantKey(.longestFast, day: "2026-09-24"), "records.longest-fast.2026-09-24")
    }

    func testStoreDecodesMissingFields() async throws {
        let directory = JR.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"records":{"protein-day":{"current":{"value":171}}},"history":[{}]}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent(RecordsStore.fileName))

        let loaded = await RecordsStore(directory: directory).load()
        XCTAssertTrue(loaded.isReadable)
        XCTAssertEqual(loaded.state.record(.proteinDay).current?.value, 171)
        XCTAssertNil(loaded.state.record(.proteinDay).current?.day)
        XCTAssertEqual(loaded.state.history?.count, 1)
        XCTAssertTrue(loaded.state.isFirstRun)
    }
}
