// TrainingXPBudget.swift
//
// add-training-gamification-and-150-levels (design D2, D3): the training
// experience's XP, source by source, as the same kind of explicit table
// `XPBudget` keeps for the food economy -- one line per source: its reward
// constant and how often it is expected to pay in three scenarios:
//
//   - `typical`: a consistent athlete who is not perfect (6 check-ins a
//     week, 85 % of 7 planned sessions done within the light, 6 kept weeks
//     in 10). The level curve is solved against this column.
//   - `poor`: a bad week (3 check-ins, 4 sessions, no kept week).
//   - `perfect`: everything, every day.
//
// The sum of the typical column is the `training` line of `XPBudget.lines`;
// the other two only describe the range ("3 to 5 years") and are checked by
// XPBudgetTests against `tools/level-curve-model.mjs`, which mirrors this
// file line by line because Swift does not run on the development machine.
//
// Frequencies are per `Period`: a week, a year, or `span` -- a one-off (a
// streak milestone, a badge) spread over the `XPBudget.targetDays` the whole
// climb takes.
//
// Honest calls and the wise call are NOT things to maximise: their perfect
// frequency equals the typical one (more amber mornings are not better
// play).
//
// Pure: no I/O, no state. Depends on: XPAward (+Training). Depended on by:
// XPBudget (the `training` line and the scenario totals), XPBudgetTests.

import Foundation

public struct TrainingXPBudgetLine: Sendable, Equatable {
    public enum Period: Sendable, Equatable {
        case week
        case year
        /// Once over the whole climb (`XPBudget.targetDays`).
        case span
    }

    public let source: String
    /// XP paid each time.
    public let reward: Int
    public let period: Period
    /// How many times per period it pays.
    public let typical: Double
    public let poor: Double
    public let perfect: Double

    public init(_ source: String, reward: Int, per period: Period, typical: Double, poor: Double, perfect: Double) {
        self.source = source
        self.reward = reward
        self.period = period
        self.typical = typical
        self.poor = poor
        self.perfect = perfect
    }

    private var days: Double {
        switch period {
        case .week: return 7.0
        case .year: return 365.0
        case .span: return Double(XPBudget.targetDays)
        }
    }

    public var typicalDailyXP: Double { Double(reward) * typical / days }
    public var poorDailyXP: Double { Double(reward) * poor / days }
    public var perfectDailyXP: Double { Double(reward) * perfect / days }
}

public enum TrainingXPBudget {
    /// Every training badge: 14 from add-winter-arc-nutrition-and-rewards
    /// plus the ladders of TrainingProgressCatalog (TrainingProgressTests
    /// checks the count).
    public static let badgeCount = 55

    /// All four habit-streak milestones together.
    static var habitStreakTotalXP: Int {
        XPAward.trainingHabitStreakMilestones.reduce(0) { $0 + $1.xp }
    }

    public static let lines: [TrainingXPBudgetLine] = [
        // --- honest self-monitoring ---
        // A check-in on 6 of 7 mornings.
        TrainingXPBudgetLine("checkIn", reward: XPAward.trainingCheckIn, per: .week, typical: 6, poor: 3, perfect: 7),
        // Pain is asked on about 40 % of days (while pain mode is on).
        TrainingXPBudgetLine("painLogged", reward: XPAward.trainingPainLogged, per: .week, typical: 6 * 0.4, poor: 3 * 0.4, perfect: 7 * 0.4),
        TrainingXPBudgetLine("sessionRPE", reward: XPAward.trainingSessionRPE, per: .week, typical: 4, poor: 1, perfect: 7),
        TrainingXPBudgetLine("sessionNote", reward: XPAward.trainingSessionNote, per: .week, typical: 2, poor: 0, perfect: 7),
        // The weekly gate test, on the same 40 % of weeks.
        TrainingXPBudgetLine("gateTest", reward: XPAward.trainingGateTest, per: .week, typical: 0.4, poor: 0.2, perfect: 0.4),
        // A test session every other week.
        TrainingXPBudgetLine("testRecorded", reward: XPAward.trainingTestRecorded, per: .week, typical: 0.5, poor: 0.25, perfect: 0.5),

        // --- habits ---
        // About three habits a day; four at best.
        TrainingXPBudgetLine("habitTick", reward: XPAward.trainingHabitTick, per: .week, typical: 22, poor: 10, perfect: 28),
        TrainingXPBudgetLine("habitFullDay", reward: XPAward.trainingHabitFullDay, per: .week, typical: 3.5, poor: 0.5, perfect: 7),
        // 7 + 30 + 100 + 365 days: 340 XP once.
        TrainingXPBudgetLine("habitStreak", reward: habitStreakTotalXP, per: .span, typical: 1, poor: 0.2, perfect: 1),
        // Eight ladder steps over the climb.
        TrainingXPBudgetLine("ladderStep", reward: XPAward.trainingLadderStep, per: .span, typical: 8, poor: 4, perfect: 8),

        // --- following the plan ---
        // Seven planned sessions a week, 85 % done within the light.
        TrainingXPBudgetLine("session", reward: XPAward.trainingSession, per: .week, typical: 7 * 0.85, poor: 4, perfect: 7),
        TrainingXPBudgetLine("honestCall", reward: XPAward.trainingHonestCall, per: .week, typical: 0.7, poor: 0.3, perfect: 0.7),
        // Rest days count: 5.5 kept days of 7.
        TrainingXPBudgetLine("dayKept", reward: XPAward.trainingDayKept, per: .week, typical: 5.5, poor: 3, perfect: 7),
        TrainingXPBudgetLine("weekApproved", reward: XPAward.trainingWeekApproved, per: .week, typical: 0.95, poor: 0.8, perfect: 1),
        // Six kept weeks in ten.
        TrainingXPBudgetLine("weekKept", reward: XPAward.trainingWeekKept, per: .week, typical: 0.6, poor: 0, perfect: 1),
        // Every fourth week is an easy one; three in four of them respected.
        TrainingXPBudgetLine("easyWeek", reward: XPAward.trainingEasyWeek, per: .week, typical: 0.25 * 0.75, poor: 0, perfect: 0.25),
        TrainingXPBudgetLine("gymWeek", reward: XPAward.trainingGymWeek, per: .week, typical: 0.7, poor: 0.25, perfect: 1),
        TrainingXPBudgetLine("phaseCompleted", reward: XPAward.trainingPhaseCompleted, per: .year, typical: 4, poor: 3, perfect: 4),
        TrainingXPBudgetLine("seasonCompleted", reward: XPAward.trainingSeasonCompleted, per: .year, typical: 1, poor: 1, perfect: 1),

        // --- races: preparation and execution, never distance or pace ---
        // Eight races a year; the fuel-plan reward is dormant (no line).
        TrainingXPBudgetLine("racePrep", reward: XPAward.trainingRacePrep, per: .year, typical: 6, poor: 1, perfect: 8),
        TrainingXPBudgetLine("carbLoadDay", reward: XPAward.trainingCarbLoadDay, per: .year, typical: 6, poor: 0, perfect: 16),
        TrainingXPBudgetLine("raceFinished", reward: XPAward.trainingRaceFinished, per: .year, typical: 7, poor: 3, perfect: 8),
        TrainingXPBudgetLine("raceReport", reward: XPAward.trainingRaceReport, per: .year, typical: 6, poor: 1, perfect: 8),
        // One wise stop over the whole climb, whatever the play.
        TrainingXPBudgetLine("wiseCall", reward: XPAward.trainingWiseCall, per: .span, typical: 1, poor: 1, perfect: 1),

        // --- badges: each the generic badge bonus, once ---
        TrainingXPBudgetLine("badges", reward: XPAward.achievementBonus, per: .span, typical: 40, poor: 15, perfect: Double(badgeCount)),
    ]

    public static var typicalDailyXP: Double {
        lines.reduce(0.0) { $0 + $1.typicalDailyXP }
    }

    public static var poorDailyXP: Double {
        lines.reduce(0.0) { $0 + $1.poorDailyXP }
    }

    public static var perfectDailyXP: Double {
        lines.reduce(0.0) { $0 + $1.perfectDailyXP }
    }
}
