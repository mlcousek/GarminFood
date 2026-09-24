// SignalChallengeTests.swift
//
// add-gamification-signals 6.5: signal-kind challenge progress (spec
// scenarios "Something Fishy" and "A day without macro data"), the
// no-signals fallback, and back-compat decode of a pre-change
// ChallengeStore file.

import XCTest
import FoodLogCore
@testable import Gamification

final class SignalChallengeTests: XCTestCase {
    private typealias F = SignalFixtures
    private let calendar = TestClock.calendar

    private func template(_ id: String) throws -> ChallengeTemplate {
        try XCTUnwrap(ChallengeCatalog.all.first { $0.id == id })
    }

    private func progress(_ id: String, startDay: Int, now: Date, signals: SignalsSnapshot?) throws -> ChallengeProgress {
        let template = try template(id)
        let active = ActiveChallenge(templateId: id, startedAt: TestClock.date(2026, 9, startDay), baselineStreakLength: 0)
        return ChallengeEngine.progress(
            for: template, active: active, events: [], goalStatuses: [],
            now: now, signals: signals, calendar: calendar
        )
    }

    private func tagged(_ name: String, day: Int, hour: Int = 12, fiber: Double? = 5) -> SignalEntry {
        F.entry(name, tags: FoodTagger.tags(name: name, brand: nil, barcode: nil),
                at: TestClock.date(2026, 9, day, hour: hour), fiber: fiber)
    }

    // MARK: - Something Fishy: fish on 2 days within 7

    func testSomethingFishyCompletesOnFriday() throws {
        let tuesday = F.day(2026, 9, 22, entries: [tagged("Losos na grilu", day: 22)])
        let wednesday = F.day(2026, 9, 23, entries: [tagged("Rohlík", day: 23)])
        let friday = F.day(2026, 9, 25, entries: [tagged("Tuňákový salát", day: 25)])

        let midweek = try progress("sig-something-fishy", startDay: 21, now: TestClock.date(2026, 9, 24, hour: 20),
                                   signals: F.snapshot([tuesday, wednesday]))
        XCTAssertEqual(midweek.current, 1)
        XCTAssertFalse(midweek.isComplete)

        let onFriday = try progress("sig-something-fishy", startDay: 21, now: TestClock.date(2026, 9, 25, hour: 20),
                                    signals: F.snapshot([tuesday, wednesday, friday]))
        XCTAssertEqual(onFriday.current, 2)
        XCTAssertTrue(onFriday.isComplete)
    }

    func testDaysOutsideTheWindowDoNotCount() throws {
        let before = F.day(2026, 9, 20, entries: [tagged("Losos", day: 20)])
        let inside = F.day(2026, 9, 22, entries: [tagged("Losos", day: 22)])
        let result = try progress("sig-something-fishy", startDay: 21, now: TestClock.date(2026, 9, 27, hour: 20),
                                  signals: F.snapshot([before, inside]))
        XCTAssertEqual(result.current, 1)
    }

    func testNoSignalsMeansNoProgress() throws {
        let result = try progress("sig-something-fishy", startDay: 21, now: TestClock.date(2026, 9, 25, hour: 20), signals: nil)
        XCTAssertEqual(result.current, 0)
        XCTAssertEqual(result.target, 2)
    }

    // MARK: - Fibre Fanatic: >= 30 g fibre on 4 days; unknown fibre never counts

    func testFibreFanaticSkipsADayWithUnknownFibre() throws {
        let rich = (21...23).map { day in
            F.day(2026, 9, day, entries: [tagged("Ovesné vločky", day: day, fiber: 35)])
        }
        let unknown = F.day(2026, 9, 24, entries: [
            tagged("Ovesné vločky", day: 24, fiber: 35),
            tagged("Neznámé jídlo", day: 24, hour: 13, fiber: nil),
        ])
        let signals = F.snapshot(rich + [unknown])
        let result = try progress("sig-fibre-fanatic", startDay: 21, now: TestClock.date(2026, 9, 24, hour: 20), signals: signals)
        XCTAssertEqual(result.current, 3, "the unknown-fibre day must not count")
        XCTAssertFalse(result.isComplete)
        // ...and it is "no data", not "failed".
        XCTAssertNil(SignalEvaluator.evaluate(.macroAtLeast(.fiber, grams: 30), on: unknown, history: signals, calendar: calendar))
    }

    // MARK: - Week-span kinds

    func testRainbowWeekCountsDistinctColours() throws {
        let days = [
            F.day(2026, 9, 21, entries: [F.entry("a", tags: [.colourRed, .colourGreen], at: TestClock.date(2026, 9, 21))]),
            F.day(2026, 9, 23, entries: [F.entry("b", tags: [.colourOrange, .colourRed], at: TestClock.date(2026, 9, 23))]),
        ]
        let result = try progress("sig-rainbow-week", startDay: 21, now: TestClock.date(2026, 9, 23, hour: 20), signals: F.snapshot(days))
        XCTAssertEqual(result.current, 3)
        XCTAssertEqual(result.target, 6)
    }

    // MARK: - Catalog shape

    func testTwentyFourSignalTemplatesWithUniqueIdsAndDesignXP() {
        let signal = ChallengeCatalog.all.filter { $0.kind.isSignalBased }
        XCTAssertEqual(signal.count, 24)
        XCTAssertTrue(signal.allSatisfy { $0.id.hasPrefix("sig-") })
        XCTAssertTrue(signal.allSatisfy { XPAward.creativeChallengeRange.contains($0.xpReward) })
        let ids = ChallengeCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testDataRequirementsOfKeyTemplates() throws {
        XCTAssertEqual(try template("sig-hydration-station").kind.dataRequirement, .water)
        XCTAssertEqual(try template("sig-fibre-fanatic").kind.dataRequirement, .macros)
        XCTAssertEqual(try template("sig-fuel-and-recover").kind.dataRequirement, [.activities, .macros])
        XCTAssertEqual(try template("sig-something-fishy").kind.dataRequirement, [])
        XCTAssertEqual(try template("perfect-week").kind.dataRequirement, [])
    }

    // MARK: - Back-compat

    func testPreChangeChallengeStoreFileDecodes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gamification-challenge-old-\(UUID().uuidString).json")
        // The exact shape the pre-change store wrote (3 recent ids, a ladder
        // tier that is now weight 0 still active).
        let json = #"{"active":{"templateId":"log-streak-4","startedAt":780000000,"baselineStreakLength":2},"recentTemplateIds":["log-streak-4","perfect-week","explorer"]}"#
        try Data(json.utf8).write(to: url)
        let store = ChallengeStore(fileURL: url)
        let active = await store.current()
        XCTAssertEqual(active?.templateId, "log-streak-4", "an active trimmed ladder challenge keeps running")

        // A file without recentTemplateIds also loads (Optional-safe).
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("gamification-challenge-old2-\(UUID().uuidString).json")
        try Data(#"{"active":null}"#.utf8).write(to: url2)
        let empty = await ChallengeStore(fileURL: url2).current()
        XCTAssertNil(empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path), "must not be quarantined")
    }

    func testRecentTemplateCapIsEight() {
        XCTAssertEqual(ChallengeStore.maxRecentTemplateIds, 8)
    }
}
