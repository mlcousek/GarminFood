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
    /// unglamorous-to-grind curve": 1.3 makes each level cost 30% more XP
    /// than the last, so early levels feel frequent while later ones become
    /// a genuine long-term arc (by level 20 a single level-up costs roughly
    /// 100x the first one) without ever being a wall.
    public static let growthFactor: Double = 1.3

    /// A safety ceiling, not a design statement -- purely so
    /// `level(forTotalXP:)` always terminates. At `growthFactor` 1.3 this
    /// is already an astronomically large cumulative total; no realistic
    /// amount of logging reaches it.
    public static let maxLevel = 200

    /// XP required to advance from `level` to `level + 1`.
    public static func xpRequired(afterLevel level: Int) -> Int {
        precondition(level >= 1, "levels start at 1")
        let raw = baseXPForFirstLevelUp * pow(growthFactor, Double(level - 1))
        return max(1, Int(raw.rounded()))
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
        var level = 1
        var thresholdForCurrentLevel = 0
        while level < maxLevel {
            let bandWidth = xpRequired(afterLevel: level)
            if totalXP < thresholdForCurrentLevel + bandWidth { break }
            thresholdForCurrentLevel += bandWidth
            level += 1
        }
        let bandWidth = level < maxLevel ? xpRequired(afterLevel: level) : 0
        return Progress(
            level: level,
            totalXP: totalXP,
            xpIntoCurrentLevel: totalXP - thresholdForCurrentLevel,
            xpNeededForNextLevel: bandWidth
        )
    }
}
