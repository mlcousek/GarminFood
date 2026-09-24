// JourneysTests.swift
//
// add-journeys-and-records design D10 / tasks 2.5: conversions, milestone
// crossings (several per day = several grants, one moment), stage rollover,
// Podolí percentage, weight fallback, missing-data days, store decode.

import XCTest
import FoodLogCore
@testable import Gamification

final class JourneysTests: XCTestCase {
    // MARK: - Conversions

    func testConversions() {
        XCTAssertEqual(JourneyCatalog.metres(proteinGrams: 130), 65)
        XCTAssertEqual(JourneyCatalog.litres(waterML: 1_500), 1.5)
        XCTAssertEqual(JourneyCatalog.kilometres(activeKcal: 700, weightKg: 70), 10)
        XCTAssertEqual(JourneyCatalog.kilometres(activeKcal: 800, weightKg: 80), 10)
        XCTAssertEqual(JourneyCatalog.kilometres(activeKcal: 700, weightKg: nil), 10, "70 kg fallback")
        XCTAssertEqual(JourneyCatalog.kilometres(activeKcal: 700, weightKg: 0), 10, "a zero weight falls back too")
    }

    func testCatalogThresholdsAndStages() {
        let protein = JourneyCatalog.protein
        XCTAssertEqual(protein.milestones.first { $0.id == "snezka" }?.threshold, 1_603)
        XCTAssertEqual(protein.milestones.first { $0.id == "everest" }?.threshold, 8_849)
        // Stage 2 starts at 0 m when Everest is reached.
        XCTAssertEqual(protein.milestones.first { $0.id == "seven-everest" }?.threshold, 17_698)
        XCTAssertEqual(protein.milestones.first { $0.id == "karman" }?.threshold, 152_162)
        XCTAssertEqual(JourneyCatalog.road.milestones.last?.threshold, 7_295)
        XCTAssertEqual(JourneyCatalog.passport.milestones.map(\.threshold), [10, 25, 50, 100, 250, 500])
        for definition in JourneyCatalog.all {
            XCTAssertEqual(Set(definition.milestones.map(\.id)).count, definition.milestones.count, "\(definition.id) ids unique")
        }
    }

    func testRequirements() {
        XCTAssertEqual(JourneyCatalog.road.requirement, .activities, "active kcal only exist with Garmin activity data")
        XCTAssertEqual(JourneyCatalog.protein.requirement, .macros)
        XCTAssertEqual(JourneyCatalog.water.requirement, .water)
        XCTAssertTrue(JourneyCatalog.passport.requirement.isEmpty)
    }

    func testAvailability() {
        let kcalOnly = DaySignals(day: JR.key(5), date: TestClock.date(2026, 9, 5, hour: 0), activeKcal: 300)
        XCTAssertTrue(JourneysEvaluator.isAvailable(.road, days: [kcalOnly]), "cached active kcal alone is enough")
        XCTAssertFalse(JourneysEvaluator.isAvailable(.road, days: [JR.day(5, waterML: 100)]))
        XCTAssertTrue(JourneysEvaluator.isAvailable(.water, days: [JR.day(5, waterML: 100)]))
        XCTAssertTrue(JourneysEvaluator.isAvailable(.passport, days: []))
    }

    // MARK: - Evaluation

    func testProteinReachesSnezkaAndShowsGerlachNext() {
        // 3,160 g sealed on the first run = 1,580 m.
        var result = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: JR.snapshot([JR.protein(1, 3_160)], today: 10))
        XCTAssertEqual(result.state.total(.protein), 1_580)
        XCTAssertFalse(result.state.reachedMilestones(.protein).contains("snezka"))

        // Today +120 g = +60 m -> 1,640 m.
        result = JourneysEvaluator.evaluate(
            state: result.state,
            snapshot: JR.snapshot([JR.protein(1, 3_160), JR.protein(10, 120)], today: 10)
        )
        XCTAssertEqual(result.state.total(.protein), 1_640)
        XCTAssertEqual(result.newlyReached.map(\.milestone.id), ["snezka"])
        let progress = JourneysEvaluator.progress(state: result.state, kind: .protein)
        XCTAssertEqual(progress.lastReached?.id, "snezka")
        XCTAssertEqual(progress.next?.id, "gerlach")
        XCTAssertEqual(progress.remainingToNext, 1_015)
    }

    func testRepeatedRefreshesCountEachDayOnce() {
        let snapshot = JR.snapshot((1...10).map { JR.protein($0, 100) }, today: 10)
        var state = JourneysState()
        for _ in 0..<10 {
            state = JourneysEvaluator.evaluate(state: state, snapshot: snapshot).state
        }
        XCTAssertEqual(state.total(.protein), 10 * 50)
        XCTAssertEqual(state.protein?.sealedTotal, 350)
    }

    func testLateLogForYesterdayAddsHalfAMetrePerGram() {
        var state = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: JR.snapshot([JR.protein(9, 100)], today: 10)).state
        let before = state.total(.protein)
        let yesterday = JR.day(9, entries: [
            JR.entry("a", day: 9, protein: 100),
            JR.entry("late", day: 9, hour: 21, protein: 30),
        ])
        state = JourneysEvaluator.evaluate(state: state, snapshot: JR.snapshot([yesterday], today: 10)).state
        XCTAssertEqual(state.total(.protein) - before, 15)
    }

    func testMissingDataDaysContributeNothing() {
        let waterOnly = JR.day(2, waterML: 2_000)
        let unknownProtein = JR.day(3, entries: [JR.entry("x", day: 3, protein: nil)])
        let state = JourneysEvaluator.evaluate(
            state: JourneysState(),
            snapshot: JR.snapshot([waterOnly, unknownProtein], today: 10)
        ).state
        XCTAssertEqual(state.total(.protein), 0)
        XCTAssertEqual(state.total(.road), 0, "no active kcal cached = no distance")
        XCTAssertEqual(state.total(.water), 2)
    }

    func testRoadTripUsesWeightKnownThatDayElseFallback() {
        let snapshot = JR.snapshot([
            JR.day(1, activeKcal: 700),                  // no weigh-in yet -> 70 kg -> 10 km
            JR.day(2, weighInKg: 80),
            JR.day(3, activeKcal: 800),                  // 80 kg -> 10 km
        ], today: 10)
        let state = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: snapshot).state
        XCTAssertEqual(state.total(.road), 20, accuracy: 0.0001)
        XCTAssertEqual(state.road?.lastKnownWeightKg, 80)
    }

    func testRoadTripScenario700KcalAt70KgIsTenKm() {
        let state = JourneysEvaluator.evaluate(
            state: JourneysState(),
            snapshot: JR.snapshot([JR.day(10, activeKcal: 700, weighInKg: 70)], today: 10)
        ).state
        XCTAssertEqual(state.total(.road), 10, accuracy: 0.0001)
    }

    func testStageRollover() {
        var state = JourneysState()
        state.protein = CumulativeJourneyState(sealedTotal: 8_849 * 2 + 100)
        let result = JourneysEvaluator.evaluate(state: state, snapshot: JR.snapshot([], today: 10))
        let reached = result.state.reachedMilestones(.protein)
        XCTAssertTrue(reached.contains("everest"))
        XCTAssertTrue(reached.contains("seven-everest"))
        let progress = JourneysEvaluator.progress(state: result.state, kind: .protein)
        XCTAssertEqual(progress.stageIndex, 1)
        XCTAssertEqual(progress.positionInStage, 8_849 + 100)
        XCTAssertEqual(progress.next?.id, "seven-aconcagua")
    }

    func testPodoliPercentageAfterTheLastFiniteMilestone() {
        var state = JourneysState()
        state.water = CumulativeJourneyState(sealedTotal: 3_000)
        let progress = JourneysEvaluator.progress(state: state, kind: .water)
        XCTAssertNil(progress.next)
        XCTAssertEqual(progress.endlessPercent ?? 0, 3_000 / 2_100_000 * 100, accuracy: 0.00001)

        state.water = CumulativeJourneyState(sealedTotal: 2_000)
        XCTAssertNil(JourneysEvaluator.progress(state: state, kind: .water).endlessPercent)
    }

    func testPassportCountsDistinctFoodsFromEntriesAndHistory() {
        let snapshot = JR.snapshot([
            JR.day(1, entries: [JR.entry("a", day: 1), JR.entry("b", day: 1)]),
            JR.day(9, entries: [JR.entry("a", day: 9)]),
        ], today: 10, firstSeenDayByFood: ["c": JR.key(1)])
        let state = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: snapshot).state
        XCTAssertEqual(state.passport?.foodIds, ["a", "b", "c"])
        XCTAssertEqual(state.total(.passport), 3)
    }

    // MARK: - Feature

    func testTwoMilestonesInOneDayAreTwoGrantsAndOneMoment() async {
        let feature = JourneysFeature(directory: JR.tempDirectory())
        let first = await feature.update(JR.context(JR.snapshot([], today: 10), today: 10))
        XCTAssertTrue(first.moments.isEmpty, "nothing to summarise on an empty first run")

        let update = await feature.update(JR.context(JR.snapshot([JR.day(10, waterML: 60_000)], today: 10), today: 10))
        let waterKeys = update.grants.map(\.key).filter { $0.hasPrefix("journeys.water.") }
        XCTAssertEqual(Set(waterKeys), ["journeys.water.bucket", "journeys.water.beer-keg"])
        XCTAssertTrue(update.grants.allSatisfy { $0.kind == .xp(40) })
        XCTAssertEqual(update.moments.count, 1)
        XCTAssertEqual(update.moments.first?.xpAwarded, 80)
        XCTAssertEqual(update.moments.first?.style, .celebration)

        // The same snapshot again: no new moment (grants re-emitted, the
        // ledger dedups them).
        let again = await feature.update(JR.context(JR.snapshot([JR.day(10, waterML: 60_000)], today: 10), today: 10))
        XCTAssertTrue(again.moments.isEmpty)
    }

    func testFirstRunBackfillGivesOneSummaryMoment() async {
        let feature = JourneysFeature(directory: JR.tempDirectory())
        let days = (1...40).map { JR.day($0, entries: [JR.entry("f\($0)", day: $0, protein: 150)], waterML: 4_000) }
        let update = await feature.update(JR.context(JR.snapshot(days, today: 40), today: 40))
        XCTAssertEqual(update.moments.count, 1)
        XCTAssertGreaterThan(update.moments.first?.xpAwarded ?? 0, 40)
        XCTAssertTrue(update.grants.contains { $0.key == "journeys.protein.petrin" })
        XCTAssertTrue(update.unlockBadgeIds.contains("journey.bathtub"), "40 x 4 L = 160 L")
        XCTAssertNotNil(update.summary)
    }

    func testBadgesAreDeclaredAndNamespaced() {
        let feature = JourneysFeature(directory: JR.tempDirectory())
        let ids = feature.badges.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("journey.") })
        let milestoneBadges = Set(JourneyCatalog.all.flatMap { $0.milestones.compactMap(\.badgeId) })
        XCTAssertEqual(milestoneBadges, Set(ids), "every badge is unlocked by exactly one milestone")
        XCTAssertTrue(feature.badges.allSatisfy { $0.condition == .featureEvaluated })
    }

    // MARK: - Store

    func testStoreDecodesMissingFields() async throws {
        let directory = JR.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"protein":{"sealedTotal":12},"passport":{}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent(JourneysStore.fileName))

        let loaded = await JourneysStore(directory: directory).load()
        XCTAssertTrue(loaded.isReadable)
        XCTAssertEqual(loaded.state.total(.protein), 12)
        XCTAssertEqual(loaded.state.total(.passport), 0)
        XCTAssertNil(loaded.state.water)
    }

    func testStoreRoundTrip() async throws {
        let directory = JR.tempDirectory()
        let result = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: JR.snapshot([JR.protein(1, 1_000)], today: 10))
        try await JourneysStore(directory: directory).save(result.state)
        let reopened = await JourneysStore(directory: directory).load()
        XCTAssertEqual(reopened.state, result.state)
        XCTAssertFalse(reopened.state.isFirstRun)
    }
}
