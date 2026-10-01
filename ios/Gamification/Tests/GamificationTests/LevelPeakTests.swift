// LevelPeakTests.swift
//
// add-gamification-signals 6.6 (design D10): the rule that a level once
// reached is never taken away -- the displayed level is never below the
// stored peak, and a level-up moment fires only when the live curve passes
// that peak.
//
// add-training-gamification-and-150-levels D4: the live curve (1.03087, 150
// levels) is flatter than every earlier one, so an old ledger's XP now maps
// to a HIGHER level and the peak rarely has anything to hold. The rule
// stays as a second guard, so it is tested here with a peak written above
// the curve on purpose. The migrations are in XPCurveMigrationTests.

import XCTest
@testable import Gamification

final class LevelPeakTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-peak-\(UUID().uuidString).json")
    }

    private func legacyThreshold(forLevel level: Int) -> Int {
        (1..<level).reduce(0) { $0 + LevelCurve.xpRequired(afterLevel: $1, growthFactor: LevelCurve.pastGrowthFactors[0]) }
    }

    private func writeLegacyLedger(totalXP: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-20"}"#
        try Data(json.utf8).write(to: url)
    }

    /// A ledger of today's format whose peak is above its XP's level.
    private func writeHeldPeakLedger(totalXP: Int, peakLevel: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"peakLevel":\#(peakLevel),"curveVersion":\#(LevelCurve.curveVersion)}"#
        try Data(json.utf8).write(to: url)
    }

    func testLevel150NeedsAbout297kXP() {
        XCTAssertEqual(LevelCurve.growthFactor, 1.03087)
        let threshold = LevelCurve.threshold(forLevel: 150)
        XCTAssertEqual(threshold, 297_264)
        XCTAssertEqual(LevelCurve.level(forTotalXP: threshold).level, 150)
        XCTAssertEqual(LevelCurve.level(forTotalXP: threshold - 1).level, 149)
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

    func testOldLedgerDecodesAndNeverShowsALowerLevel() async throws {
        let url = tempURL()
        let oldTotal = legacyThreshold(forLevel: 40)
        try writeLegacyLedger(totalXP: oldTotal, to: url)
        // On the 150-level curve this total alone is a HIGHER level.
        XCTAssertEqual(LevelCurve.level(forTotalXP: oldTotal).level, 47)

        let store = XPStore(fileURL: url)
        let total = await store.currentTotal()
        XCTAssertEqual(total, oldTotal)
        let progress = await store.currentProgress()
        XCTAssertEqual(progress.level, 47)
        let peak = await store.peakLevel()
        XCTAssertEqual(peak, 47)
    }

    func testLevelUpFiresOnlyAbovePeak() async throws {
        let url = tempURL()
        let total = LevelCurve.threshold(forLevel: 10)
        try writeHeldPeakLedger(totalXP: total, peakLevel: 40, to: url)
        let store = XPStore(fileURL: url)
        let start = await store.currentProgress()
        XCTAssertEqual(start.level, 40, "the peak holds the displayed level")

        let small = try await store.recordChallengeCompletion(xp: 10)
        XCTAssertFalse(small.didLevelUp)
        XCTAssertEqual(small.levelAfter.level, 40)

        // Enough to pass 40 on the live curve -> exactly one level-up, to 41.
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
