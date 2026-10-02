// XPCurveMigrationTests.swift
//
// rebalance-xp-economy task 3.3 (design D1, D5) and
// add-training-gamification-and-150-levels D4: a curve change never shows
// anyone a lower level, whatever curve their ledger was written under.
//
// Until 2026-10-01 every retune made the curve STEEPER, so the stored peak
// had to hold the displayed level up. The 150-level curve is flatter than
// every earlier one: the same XP now maps to the same or a higher level, a
// held peak is usually overtaken at once, and a ledger written before it
// gets a one-time announcement naming the level it had and the level it
// has. These tests cover ledgers of all three older formats (version 1: no
// peak; version 2: a peak, no version; version 3: both), the idempotent
// seeding, and the announcement (once, never on a new install). The peak
// rule itself is in LevelPeakTests.
//
// Depends on: XPStore (seededPeakLevel, file format, announcement),
// LevelCurve (pastGrowthFactors, curveVersion), XPBudget (typical day).

import XCTest
@testable import Gamification

final class XPCurveMigrationTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-migration-\(UUID().uuidString).json")
    }

    /// Total XP at which `level` is reached on the curve with `factor`.
    private func threshold(forLevel level: Int, factor: Double) -> Int {
        (1..<level).reduce(0) { $0 + LevelCurve.xpRequired(afterLevel: $1, growthFactor: factor) }
    }

    /// A file written by the first build: no peak, no version.
    private func writeVersion1Ledger(totalXP: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-20"}"#
        try Data(json.utf8).write(to: url)
    }

    /// A file written by the 1.0505 build: `peakLevel`, no `curveVersion`.
    private func writeVersion2Ledger(totalXP: Int, peakLevel: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-24","peakLevel":\#(peakLevel)}"#
        try Data(json.utf8).write(to: url)
    }

    /// A file written by the 1.05358 build: both fields.
    private func writeVersion3Ledger(totalXP: Int, peakLevel: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-30","peakLevel":\#(peakLevel),"curveVersion":3}"#
        try Data(json.utf8).write(to: url)
    }

    func testPastFactorsAndVersion() {
        XCTAssertEqual(LevelCurve.pastGrowthFactors, [1.045, 1.0505, 1.05358])
        XCTAssertEqual(LevelCurve.curveVersion, 4)
        XCTAssertEqual(LevelCurve.curveVersionWith150Levels, 4)
        for past in LevelCurve.pastGrowthFactors {
            XCTAssertLessThan(LevelCurve.growthFactor, past, "the 150-level curve is flatter than every earlier one")
        }
    }

    // MARK: - Never lower

    func testALevelReachedOnAnyEarlierCurveIsNeverShownLower() async throws {
        for factor in LevelCurve.pastGrowthFactors {
            for level in [5, 20, 40, 84, 120] {
                let total = threshold(forLevel: level, factor: factor)
                // The live curve alone already shows at least that level.
                XCTAssertGreaterThanOrEqual(LevelCurve.level(forTotalXP: total).level, level, "\(total) XP was level \(level) on \(factor)")

                // And so does the store, even when the stored peak lags.
                let url = tempURL()
                try writeVersion2Ledger(totalXP: total, peakLevel: 1, to: url)
                let store = XPStore(fileURL: url)
                let progress = await store.currentProgress()
                XCTAssertGreaterThanOrEqual(progress.level, level, "XP \(total) was level \(level) under \(factor)")
                let stored = await store.currentTotal()
                XCTAssertEqual(stored, total, "XP is never touched")
            }
        }
    }

    func testStoredPeakIsNeverLowered() {
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 30, storedCurveVersion: 2), 30)
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 30, storedCurveVersion: 3), 30)
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 30, storedCurveVersion: LevelCurve.curveVersion), 30)
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: nil, storedCurveVersion: nil), 1)
        // A peak above the new last level (it cannot exist) is clamped.
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 180, storedCurveVersion: 3), LevelCurve.maxLevel)
    }

    func testSeedIsTheMaxOverTheLiveCurveAndEveryPastFactor() {
        let total = 12_000
        let expected = ([LevelCurve.growthFactor] + LevelCurve.pastGrowthFactors)
            .map { LevelCurve.level(forTotalXP: total, growthFactor: $0).level }
            .max()
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: total, storedPeak: nil, storedCurveVersion: nil), expected)
        // The live curve is the flattest now, so it wins.
        XCTAssertEqual(expected, LevelCurve.level(forTotalXP: total).level)
        XCTAssertEqual(expected, 51)
    }

    func testSeedingIsIdempotent() {
        for total in [0, 150, 3_000, 12_000, 60_000, 400_000] {
            for (peak, version) in [(nil, nil), (1, 2), (20, 2), (50, 2), (25, 3)] as [(Int?, Int?)] {
                let once = XPStore.seededPeakLevel(totalXP: total, storedPeak: peak, storedCurveVersion: version)
                let twice = XPStore.seededPeakLevel(totalXP: total, storedPeak: once, storedCurveVersion: LevelCurve.curveVersion)
                XCTAssertEqual(once, twice, "XP \(total), peak \(String(describing: peak)), version \(String(describing: version))")
                let againFromOld = XPStore.seededPeakLevel(totalXP: total, storedPeak: once, storedCurveVersion: version)
                XCTAssertEqual(once, againFromOld, "XP \(total), re-seeded from version \(String(describing: version))")
                XCTAssertLessThanOrEqual(once, LevelCurve.maxLevel)
            }
        }
    }

    func testSeededFileKeepsItsLevelAcrossReloads() async throws {
        let url = tempURL()
        let total = threshold(forLevel: 40, factor: 1.0505)
        try writeVersion2Ledger(totalXP: total, peakLevel: 40, to: url)
        let first = XPStore(fileURL: url)
        _ = try await first.recordChallengeCompletion(xp: 1) // persists curveVersion
        let firstPeak = await first.peakLevel()
        XCTAssertGreaterThanOrEqual(firstPeak, 40)
        XCTAssertEqual(firstPeak, LevelCurve.level(forTotalXP: total + 1).level)

        let reloaded = XPStore(fileURL: url)
        let reloadedPeak = await reloaded.peakLevel()
        XCTAssertEqual(reloadedPeak, firstPeak)
        let progress = await reloaded.currentProgress()
        XCTAssertEqual(progress.level, firstPeak)
    }

    /// Design D4: a ledger of about 3,000 XP displayed level 20 (a peak
    /// seeded from 1.045, held above level 19 of the 1.05358 curve). On the
    /// 150-level curve it is level 22 at once -- no waiting at a held peak --
    /// and typical days keep bringing level-ups.
    func testOwnerLikeLedgerMovesUpAtOnce() async throws {
        let url = tempURL()
        try writeVersion3Ledger(totalXP: 3_000, peakLevel: 20, to: url)
        let store = XPStore(fileURL: url)
        let start = await store.currentProgress()
        XCTAssertEqual(start.level, 22)
        XCTAssertEqual(start.totalXP, 3_000)
        XCTAssertGreaterThan(start.xpIntoCurrentLevel, 0, "the bar is not stuck at a held peak")

        let typicalDay = Int(XPBudget.typicalDailyXP.rounded())
        var level = start.level
        for day in 1...5 {
            let result = try await store.recordChallengeCompletion(xp: typicalDay)
            XCTAssertGreaterThanOrEqual(result.levelAfter.level, level, "day \(day)")
            level = result.levelAfter.level
        }
        XCTAssertGreaterThanOrEqual(level, 25, "five typical days bring several levels this early")
    }

    // MARK: - The one-time "150 levels" announcement

    func testAnOlderLedgerGetsTheAnnouncementOnce() async throws {
        let url = tempURL()
        try writeVersion3Ledger(totalXP: 3_000, peakLevel: 20, to: url)
        let store = XPStore(fileURL: url)
        let announcement = await store.pendingCurveAnnouncement()
        XCTAssertEqual(announcement, CurveAnnouncement(levelBefore: 20, levelAfter: 22, maxLevel: 150))
        let moment = try XCTUnwrap(announcement?.moment)
        XCTAssertTrue(moment.title.contains("150"), moment.title)
        XCTAssertTrue(moment.message.contains("20") && moment.message.contains("22"), moment.message)
        XCTAssertEqual(moment.xpAwarded, 0)

        // Still pending until it is marked shown -- also in a new process
        // that loads the file after an XP write persisted the new version.
        _ = try await store.recordChallengeCompletion(xp: 1)
        let afterWrite = await XPStore(fileURL: url).pendingCurveAnnouncement()
        XCTAssertEqual(afterWrite?.levelBefore, 20)

        try await store.markCurveAnnouncementShown()
        let shown = await store.pendingCurveAnnouncement()
        XCTAssertNil(shown)
        let reloaded = await XPStore(fileURL: url).pendingCurveAnnouncement()
        XCTAssertNil(reloaded, "shown once, for good")
    }

    func testEveryOlderFormatIsAnnounced() async throws {
        let v1 = tempURL()
        try writeVersion1Ledger(totalXP: threshold(forLevel: 30, factor: 1.045), to: v1)
        let first = await XPStore(fileURL: v1).pendingCurveAnnouncement()
        XCTAssertEqual(first?.levelBefore, 30, "the level on the 1.045 curve that wrote it")
        XCTAssertEqual(first?.levelAfter, 34)

        let v2 = tempURL()
        try writeVersion2Ledger(totalXP: 500, peakLevel: 12, to: v2)
        let second = await XPStore(fileURL: v2).pendingCurveAnnouncement()
        XCTAssertEqual(second?.levelBefore, 12)
        XCTAssertEqual(second?.levelAfter, 12, "a held peak above the curve: the level is unchanged")
        XCTAssertTrue(second?.moment.message.contains("12") ?? false)
    }

    func testANewInstallIsNeverAnnounced() async throws {
        let store = XPStore(fileURL: tempURL())
        let fresh = await store.pendingCurveAnnouncement()
        XCTAssertNil(fresh)
        // Marking with nothing pending writes nothing and does not throw.
        try await store.markCurveAnnouncementShown()
        _ = try await store.recordLog(nutritionDay: "2030-10-01", streakExtendedToday: true, goalMetToday: false)
        let afterFirstLog = await store.pendingCurveAnnouncement()
        XCTAssertNil(afterFirstLog)
    }
}
