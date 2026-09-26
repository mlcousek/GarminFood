// SupplementsFeatureTests.swift
//
// add-supplements task 6.1: the optional `supplements` feature -- nothing
// while the digest is missing or inactive, at most one grant per
// stack-complete day (scaled by the optional-source multiplier), none for
// late entries (D14), stable grant keys -- and the spec's "Supplement XP
// does not change levelling pace" scenario through XPBudget.

import XCTest
import FoodLogCore
@testable import Gamification

final class SupplementsFeatureTests: XCTestCase {
    private let today = ST.key(26)

    private func feature() -> SupplementsFeature {
        SupplementsFeature(directory: ST.tempDirectory())
    }

    /// 10..26 Sep, every day stack complete.
    private func completeFortnight() -> [SupplementDaySignal] {
        ST.days(from: ST.key(10), Array(repeating: .complete, count: 17))
    }

    // MARK: - Registry and budget line

    func testRegisteredLastWithAnOptionalBudgetLine() {
        XCTAssertEqual(GamificationFeatureRegistry.orderedIds.last, SupplementsFeature.id)
        let line = XPBudget.lines.first { $0.source == SupplementsFeature.id }
        XCTAssertEqual(line?.optional, true)
        XCTAssertEqual(line?.expectedDailyXP ?? 0, 6, accuracy: 1, "design D9: ~6 XP/day before the multiplier")
        XCTAssertTrue(XPBudget.isOptional(source: SupplementsFeature.id))
        XCTAssertFalse(XPBudget.isOptional(source: WeeklyBossFeature.id))
    }

    func testCoreBudgetIgnoresTheSupplementsLine() {
        let withoutOptional = XPBudget.lines.filter { !$0.optional }
        XCTAssertEqual(XPBudget.coreDailyXP, XPBudget.dailyXP(of: withoutOptional), accuracy: 1e-9)
    }

    /// Spec: "the simulated typical day is run with and without the
    /// supplement budget line -> the days to level 84 differ by less than
    /// 1 %". Uses the grants the feature actually pays (scaled, >= 1 XP).
    func testEnablingSupplementsKeepsLevel84WithinOnePercent() {
        let multiplier = XPBudget.optionalMultiplier(enabledOptionalSources: [SupplementsFeature.id])
        XCTAssertLessThan(multiplier, 1, "~6 XP/day is over the 0.5% allowance, so it is scaled")
        XCTAssertEqual(SupplementsFeature.grantXP(XPAward.supplementStackComplete),
                       XPBudget.scaledGrant(XPAward.supplementStackComplete, multiplier: multiplier))

        let off = XPBudget.daysToReach(level: 84)
        // Typical (85% of days complete) and the worst case (every day).
        for completeShare in [0.85, 1.0] {
            let paid = Double(SupplementsFeature.grantXP(XPAward.supplementStackComplete)) * completeShare
                + Double(SupplementsFeature.grantXP(XPAward.journeyMilestone)) * 5 / 1_095
                + Double(SupplementsFeature.grantXP(XPAward.achievementBonus)) * 10 / 1_095
            let on = XPBudget.daysToReach(level: 84, dailyXP: XPBudget.coreDailyXP + paid)
            XCTAssertEqual(on / off, 1, accuracy: 0.01, "\(completeShare): level 84 after \(on) vs \(off) days")
        }
    }

    // MARK: - Disabled / no plan

    func testDoesNothingWithoutAnActiveDigest() async {
        let feature = feature()
        let days = completeFortnight()
        let cases: [SupplementSignals?] = [
            nil,
            ST.signals(today: today, days: days, isEnabled: false),
            ST.signals(today: today, days: days, hasPlan: false),
        ]
        for signals in cases {
            let update = await feature.update(ST.context(signals, today: today))
            XCTAssertEqual(update, .empty)
        }
    }

    // MARK: - Grants

    func testOneScaledGrantPerCompleteDayInTheGraceWindow() async {
        let update = await feature().update(ST.context(ST.signals(today: today, days: completeFortnight()), today: today))
        // today - 7 ... today = 19..26 Sep.
        XCTAssertEqual(update.grants.map(\.key), (19...26).map { "supplements.stack.\(ST.key($0))" })
        let xp = SupplementsFeature.grantXP(XPAward.supplementStackComplete)
        XCTAssertGreaterThanOrEqual(xp, 1)
        XCTAssertLessThanOrEqual(xp, XPAward.supplementStackComplete)
        XCTAssertTrue(update.grants.allSatisfy { $0.kind == .xp(xp) })
        XCTAssertTrue(update.grants.allSatisfy { $0.key.hasPrefix("supplements.") }, "the host drops keys outside the namespace")
    }

    func testOnlyStackCompleteDaysPay() async {
        let days = ST.days(from: ST.key(21), [.complete, .partial, .missed, .neutral, .complete, .partial])
        let update = await feature().update(ST.context(ST.signals(today: today, days: days), today: today))
        XCTAssertEqual(update.grants.map(\.key), ["supplements.stack.\(ST.key(21))", "supplements.stack.\(ST.key(25))"])
    }

    func testLateEntryGrantsNoXP() async {
        // 24 Sep was completed with ticks written more than 7 days later
        // (`grantsXP == false`): history, no XP (D14).
        let days = [
            ST.day(ST.key(23), .complete),
            ST.day(ST.key(24), .complete, grantsXP: false),
            ST.day(ST.key(25), .complete),
        ]
        let update = await feature().update(ST.context(ST.signals(today: today, days: days), today: today))
        XCTAssertEqual(update.grants.map(\.key), ["supplements.stack.\(ST.key(23))", "supplements.stack.\(ST.key(25))"])
    }

    func testGrantKeysAreStableSoTheLedgerPaysADayOnce() async throws {
        let feature = feature()
        let context = ST.context(ST.signals(today: today, days: completeFortnight()), today: today)
        let first = await feature.update(context)
        let second = await feature.update(context)
        XCTAssertEqual(first.grants, second.grants)

        let directory = ST.tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = RewardLedger(fileURL: directory.appendingPathComponent("reward-ledger.json"))
        let xpStore = XPStore(fileURL: directory.appendingPathComponent("xp-ledger.json"))
        let paid = try await ledger.apply(first.grants, day: today, now: context.now, xpStore: xpStore)
        let again = try await ledger.apply(second.grants, day: today, now: context.now, xpStore: xpStore)
        XCTAssertEqual(paid.xpAwarded, first.grants.count * SupplementsFeature.grantXP(XPAward.supplementStackComplete))
        XCTAssertEqual(again.xpAwarded, 0)
    }
}
