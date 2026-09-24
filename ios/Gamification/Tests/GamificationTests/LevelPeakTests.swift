// LevelPeakTests.swift
//
// add-gamification-signals 6.6 (design D10): the 1.0505 curve, and the rule
// that a level once reached is never taken away -- an XP ledger written on
// the old 1.045 curve keeps its level, and a level-up moment fires only
// when the new curve passes that peak.

import XCTest
@testable import Gamification

final class LevelPeakTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-peak-\(UUID().uuidString).json")
    }

    private func legacyThreshold(forLevel level: Int) -> Int {
        (1..<level).reduce(0) { $0 + LevelCurve.xpRequired(afterLevel: $1, growthFactor: LevelCurve.legacyGrowthFactor) }
    }

    private func writeLegacyLedger(totalXP: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-20"}"#
        try Data(json.utf8).write(to: url)
    }

    func testLevel84NeedsAbout116kXP() {
        XCTAssertEqual(LevelCurve.growthFactor, 1.0505)
        let threshold = LevelCurve.threshold(forLevel: 84)
        XCTAssertGreaterThan(threshold, 114_000)
        XCTAssertLessThan(threshold, 118_000)
        XCTAssertEqual(LevelCurve.level(forTotalXP: threshold).level, 84)
        XCTAssertEqual(LevelCurve.level(forTotalXP: threshold - 1).level, 83)
    }

    func testPeakHoldsTheDisplayedLevel() {
        let total = LevelCurve.threshold(forLevel: 10) + 5
        let held = LevelCurve.level(forTotalXP: total, peakLevel: 12)
        XCTAssertEqual(held.level, 12)
        XCTAssertEqual(held.xpIntoCurrentLevel, 0)
        XCTAssertEqual(held.xpNeededForNextLevel, LevelCurve.xpRequired(afterLevel: 12))
        // A peak below the curve changes nothing.
        XCTAssertEqual(LevelCurve.level(forTotalXP: total, peakLevel: 3), LevelCurve.level(forTotalXP: total))
        XCTAssertEqual(LevelCurve.level(forTotalXP: total, peakLevel: nil), LevelCurve.level(forTotalXP: total))
    }

    func testOldLedgerDecodesAndKeepsItsOldCurveLevel() async throws {
        let url = tempURL()
        let oldTotal = legacyThreshold(forLevel: 40)
        try writeLegacyLedger(totalXP: oldTotal, to: url)
        // Sanity: on the new curve this total alone is a lower level.
        XCTAssertLessThan(LevelCurve.level(forTotalXP: oldTotal).level, 40)

        let store = XPStore(fileURL: url)
        let total = await store.currentTotal()
        XCTAssertEqual(total, oldTotal)
        let progress = await store.currentProgress()
        XCTAssertGreaterThanOrEqual(progress.level, 40)
        let peak = await store.peakLevel()
        XCTAssertEqual(peak, 40)
    }

    func testLevelUpFiresOnlyAbovePeak() async throws {
        let url = tempURL()
        let oldTotal = legacyThreshold(forLevel: 40)
        try writeLegacyLedger(totalXP: oldTotal, to: url)
        let store = XPStore(fileURL: url)

        let small = try await store.recordChallengeCompletion(xp: 10)
        XCTAssertFalse(small.didLevelUp)
        XCTAssertEqual(small.levelAfter.level, 40)

        // Enough to pass 40 on the NEW curve -> exactly one level-up, to 41.
        let needed = LevelCurve.threshold(forLevel: 41) - small.totalXPAfter
        let big = try await store.recordChallengeCompletion(xp: needed)
        XCTAssertTrue(big.didLevelUp)
        XCTAssertEqual(big.levelAfter.level, 41)
        let peak = await store.peakLevel()
        XCTAssertEqual(peak, 41)

        // The peak survives a reload.
        let reloaded = await XPStore(fileURL: url).peakLevel()
        XCTAssertEqual(reloaded, 41)
    }

    func testFreshStoreStartsAtLevelOne() async throws {
        let store = XPStore(fileURL: tempURL())
        let progress = await store.currentProgress()
        XCTAssertEqual(progress.level, 1)
        let result = try await store.recordLog(nutritionDay: "2026-09-24", streakExtendedToday: false, goalMetToday: false)
        XCTAssertFalse(result.didLevelUp)
    }
}
