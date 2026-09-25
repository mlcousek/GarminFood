// XPCurveMigrationTests.swift
//
// rebalance-xp-economy task 3.3 (design D1, D5): moving the live curve from
// 1.0505 to the budget-solved factor never shows anyone a lower level, the
// peak seeding is idempotent, and the owner's real ledger (~3k XP, peak 20
// seeded from 1.045 on 2026-09-24) waits only a few typical days for its
// next level-up. The 1.045 -> 1.0505 rule is in LevelPeakTests.
//
// Depends on: XPStore (seededPeakLevel, file format), LevelCurve
// (pastGrowthFactors, curveVersion), XPBudget (typical day).

import XCTest
@testable import Gamification

final class XPCurveMigrationTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-migration-\(UUID().uuidString).json")
    }

    /// Total XP at which `level` is reached on the 1.0505 curve.
    private func threshold1_0505(forLevel level: Int) -> Int {
        (1..<level).reduce(0) { $0 + LevelCurve.xpRequired(afterLevel: $1, growthFactor: LevelCurve.pastGrowthFactors[1]) }
    }

    /// A file written by the 1.0505 build: it has `peakLevel` but no
    /// `curveVersion`.
    private func writeVersion2Ledger(totalXP: Int, peakLevel: Int, to url: URL) throws {
        let json = #"{"totalXP":\#(totalXP),"lastStreakBonusDay":"2026-09-24","peakLevel":\#(peakLevel)}"#
        try Data(json.utf8).write(to: url)
    }

    func testPastFactorsAndVersion() {
        XCTAssertEqual(LevelCurve.pastGrowthFactors, [1.045, 1.0505])
        XCTAssertEqual(LevelCurve.curveVersion, 3)
        XCTAssertGreaterThan(LevelCurve.growthFactor, LevelCurve.pastGrowthFactors[1])
    }

    func testLevelUnder1_0505IsNeverShownLower() async throws {
        for level in [5, 20, 40, 84] {
            let total = threshold1_0505(forLevel: level)
            // The live curve alone would show less.
            XCTAssertLessThanOrEqual(LevelCurve.level(forTotalXP: total).level, level)

            // Even a file whose stored peak lags behind its XP is seeded up.
            let url = tempURL()
            try writeVersion2Ledger(totalXP: total, peakLevel: 1, to: url)
            let store = XPStore(fileURL: url)
            let progress = await store.currentProgress()
            XCTAssertGreaterThanOrEqual(progress.level, level, "XP \(total) was level \(level) under 1.0505")
            let peak = await store.peakLevel()
            XCTAssertEqual(peak, level, "XP \(total)")
        }
    }

    func testStoredPeakIsNeverLowered() {
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 30, storedCurveVersion: 2), 30)
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: 30, storedCurveVersion: LevelCurve.curveVersion), 30)
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: 0, storedPeak: nil, storedCurveVersion: nil), 1)
    }

    func testVersion1LedgerTakesTheMaxOverEveryPastFactor() {
        let total = 12_000
        let expected = ([LevelCurve.growthFactor] + LevelCurve.pastGrowthFactors)
            .map { LevelCurve.level(forTotalXP: total, growthFactor: $0).level }
            .max()
        XCTAssertEqual(XPStore.seededPeakLevel(totalXP: total, storedPeak: nil, storedCurveVersion: nil), expected)
        // 1.045 is the flattest, so it wins.
        XCTAssertEqual(expected, LevelCurve.level(forTotalXP: total, growthFactor: 1.045).level)
    }

    func testSeedingIsIdempotent() {
        for total in [0, 150, 3_000, 12_000, 60_000] {
            for (peak, version) in [(nil, nil), (1, 2), (20, 2), (50, 2)] as [(Int?, Int?)] {
                let once = XPStore.seededPeakLevel(totalXP: total, storedPeak: peak, storedCurveVersion: version)
                let twice = XPStore.seededPeakLevel(totalXP: total, storedPeak: once, storedCurveVersion: LevelCurve.curveVersion)
                XCTAssertEqual(once, twice, "XP \(total), peak \(String(describing: peak)), version \(String(describing: version))")
                let againFromOld = XPStore.seededPeakLevel(totalXP: total, storedPeak: once, storedCurveVersion: version)
                XCTAssertEqual(once, againFromOld, "XP \(total), re-seeded from version \(String(describing: version))")
            }
        }
    }

    func testSeededFileKeepsItsPeakAcrossReloads() async throws {
        let url = tempURL()
        let total = threshold1_0505(forLevel: 40)
        try writeVersion2Ledger(totalXP: total, peakLevel: 40, to: url)
        let first = XPStore(fileURL: url)
        _ = try await first.recordChallengeCompletion(xp: 1) // persists curveVersion
        let firstPeak = await first.peakLevel()
        XCTAssertEqual(firstPeak, 40)

        let reloaded = XPStore(fileURL: url)
        let reloadedPeak = await reloaded.peakLevel()
        XCTAssertEqual(reloadedPeak, 40)
        let progress = await reloaded.currentProgress()
        XCTAssertEqual(progress.level, 40)
    }

    /// Design D1: the owner has ~3k XP and a peak of 20 seeded from 1.045.
    /// On the new curve that is level 19, so level 20 stays displayed with
    /// the bar at 0 for a while. Typical days must bring level 21 within a
    /// few days, and the displayed level must never drop on the way.
    func testOwnerLedgerWaitsOnlyAFewDaysForTheNextLevel() async throws {
        let url = tempURL()
        try writeVersion2Ledger(totalXP: 3_000, peakLevel: 20, to: url)
        let store = XPStore(fileURL: url)
        let start = await store.currentProgress()
        XCTAssertEqual(start.level, 20)
        XCTAssertLessThan(LevelCurve.level(forTotalXP: 3_000).level, 20, "the scenario needs a held peak")

        let typicalDay = Int(XPBudget.coreDailyXP.rounded())
        var daysToLevelUp: Int?
        for day in 1...30 {
            let result = try await store.recordChallengeCompletion(xp: typicalDay)
            XCTAssertGreaterThanOrEqual(result.levelAfter.level, 20, "day \(day)")
            if result.didLevelUp {
                XCTAssertEqual(result.levelAfter.level, 21)
                daysToLevelUp = day
                break
            }
        }
        let days = try XCTUnwrap(daysToLevelUp, "no level-up in 30 typical days")
        XCTAssertLessThanOrEqual(days, 5, "the owner waits \(days) days for level 21")
    }
}
