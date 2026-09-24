// LevelCurve.swift
//
// Levels spec's "Level is a deterministic function of total XP" requirement
// (design.md D3, task 24.2): a fixed, geometrically-growing threshold
// curve, no configuration or randomness. Per design.md D3's own framing,
// "the exact curve... is an implementation-time tuning detail, not a
// spec-level requirement" -- the numbers below are a deliberate first
// choice, not a spec-derived constant; see this change's final report for
// the reasoning and for how quickly they make levels arrive in practice.

import Foundation

public enum LevelCurve {
    /// XP required to go from level 1 to level 2. Chosen so that a single
    /// realistic day of logging (roughly 3 entries, one of them extending
    /// the streak -- see `XPStore`'s constants) gets more than a third of
    /// the way there: levels should arrive within the first week of real
    /// use, not the first sitting, or the whole mechanic reads as inert.
    public static let baseXPForFirstLevelUp: Double = 100

    /// The geometric growth factor applied per level, per D3's "thresholds
    /// growing roughly geometrically" and the proposal's "deliberately
    /// unglamorous-to-grind curve".
    ///
    /// 2026-09-18 retune (`expand-gamification-depth` design.md D1): the
    /// original `1.3` made anything past roughly level 20 practically
    /// unreachable -- by level 60 a single level-up already cost hundreds
    /// of millions of XP, which defeats the entire point of having 200
    /// levels. `1.045` (4.5% more XP per level) keeps the same early-game
    /// pacing (the level 1->2 band is unaffected by this constant) while
    /// producing a genuine multi-year arc at a realistic ~75 XP/day: level
    /// 10 in a few weeks, level 50 within about a year, level ~84 by year
    /// three, and level 100 around six years in -- with levels past ~150
    /// staying honestly aspirational, the same "may never be reached in
    /// practice" role `maxLevel` below already plays.
    ///
    /// 2026-09-24 (`add-gamification-signals` design D10): 1.045 -> 1.0505.
    /// The new sources (bingo, boss, records, collections, journeys) add
    /// ~31 XP/day on average; the steeper curve keeps level 84 about three
    /// years away (≈ 116 k XP instead of ≈ 84 k). Because a steeper curve
    /// can map an existing XP total to a LOWER level, `XPStore` remembers
    /// the highest level ever reached (`peakLevel`) and the displayed level
    /// is never below it -- see `level(forTotalXP:peakLevel:)`.
    public static let growthFactor: Double = 1.0505

    /// The pre-2026-09-24 factor, only used to seed `XPStore.peakLevel` for
    /// an XP ledger written before the retune (so nobody loses a level).
    public static let legacyGrowthFactor: Double = 1.045

    /// A safety ceiling, not a design statement -- purely so
    /// `level(forTotalXP:)` always terminates. At `growthFactor` 1.3 this
    /// is already an astronomically large cumulative total; no realistic
    /// amount of logging reaches it.
    public static let maxLevel = 200

    /// XP required to advance from `level` to `level + 1`.
    public static func xpRequired(afterLevel level: Int) -> Int {
        xpRequired(afterLevel: level, growthFactor: growthFactor)
    }

    static func xpRequired(afterLevel level: Int, growthFactor factor: Double) -> Int {
        precondition(level >= 1, "levels start at 1")
        let raw = baseXPForFirstLevelUp * pow(factor, Double(level - 1))
        return max(1, Int(raw.rounded()))
    }

    /// Total XP at which `level` is reached (0 for level 1).
    public static func threshold(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return (1..<min(level, maxLevel)).reduce(0) { $0 + xpRequired(afterLevel: $1) }
    }

    public struct Progress: Equatable, Sendable {
        public let level: Int
        public let totalXP: Int
        /// XP earned within the current level's band (0 at the moment the
        /// level was reached).
        public let xpIntoCurrentLevel: Int
        /// The width of the current level's band, i.e. the XP needed to
        /// reach the next level from the start of this one. `0` once
        /// `maxLevel` is reached (there is no "next" band).
        public let xpNeededForNextLevel: Int

        public var fractionToNextLevel: Double {
            xpNeededForNextLevel > 0 ? Double(xpIntoCurrentLevel) / Double(xpNeededForNextLevel) : 1
        }

        public init(level: Int, totalXP: Int, xpIntoCurrentLevel: Int, xpNeededForNextLevel: Int) {
            self.level = level
            self.totalXP = totalXP
            self.xpIntoCurrentLevel = xpIntoCurrentLevel
            self.xpNeededForNextLevel = xpNeededForNextLevel
        }
    }

    /// Deterministic level-from-XP (levels spec's core requirement):
    /// same `totalXP` always yields the same `Progress`, with no
    /// configuration or randomness involved.
    public static func level(forTotalXP totalXP: Int) -> Progress {
        level(forTotalXP: totalXP, growthFactor: growthFactor)
    }

    /// add-gamification-signals D10: the DISPLAYED level -- never below
    /// `peakLevel` (a level once reached is never taken away). When the
    /// peak is above the curve level, progress is measured toward
    /// `peakLevel + 1` on the current curve (0 into the band until the XP
    /// total catches up).
    public static func level(forTotalXP totalXP: Int, peakLevel: Int?) -> Progress {
        let curve = level(forTotalXP: totalXP)
        guard let peak = peakLevel.map({ min($0, maxLevel) }), peak > curve.level else { return curve }
        let bandWidth = peak < maxLevel ? xpRequired(afterLevel: peak) : 0
        return Progress(
            level: peak,
            totalXP: totalXP,
            xpIntoCurrentLevel: max(0, totalXP - threshold(forLevel: peak)),
            xpNeededForNextLevel: bandWidth
        )
    }

    static func level(forTotalXP totalXP: Int, growthFactor factor: Double) -> Progress {
        var level = 1
        var thresholdForCurrentLevel = 0
        while level < maxLevel {
            let bandWidth = xpRequired(afterLevel: level, growthFactor: factor)
            if totalXP < thresholdForCurrentLevel + bandWidth { break }
            thresholdForCurrentLevel += bandWidth
            level += 1
        }
        let bandWidth = level < maxLevel ? xpRequired(afterLevel: level, growthFactor: factor) : 0
        return Progress(
            level: level,
            totalXP: totalXP,
            xpIntoCurrentLevel: totalXP - thresholdForCurrentLevel,
            xpNeededForNextLevel: bandWidth
        )
    }
}
