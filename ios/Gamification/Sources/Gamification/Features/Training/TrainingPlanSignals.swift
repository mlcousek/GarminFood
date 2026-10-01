// TrainingPlanSignals.swift
//
// add-training-gamification-and-150-levels (design D6): the training plan's
// facts as the training XP reads them -- plain strings, numbers and flags,
// so this package never imports TrainingCore (it depends only on
// FoodLogCore). The app's adapter (GarminFood/Training/
// TrainingPlanSignalsBridge.swift) copies TrainingCore's `TrainingPlanFacts`
// into this shape, field by field.
//
// These are FACTS, not judgements: a session says whether it is done and
// with which option, a day carries the morning light of a check-in. Whether
// that makes the session "within the light", the day "kept" or the week
// "kept within plan" is decided by `TrainingXPRules`, in this package, where
// every guard is tested with literal signals.
//
// `TrainingSignals` (add-winter-arc-nutrition-and-rewards) stays as it is,
// beside this: it is what the five original badge ladders were built on,
// and an app that passes only it keeps working.
//
// Days are `yyyy-MM-dd` and weeks `YYYY-Www`, the strings both sides already
// use, so they double as reward keys and store ids. The light's cases avoid
// colour words (`greenLight`, not `green`) for the same reason TrainingCore's
// do: the app's design-token lint forbids `.green` / `.red` literals in
// views and adapters.
//
// Depended on by: FeatureContext, TrainingXPRules, TrainingRewardsFeature,
// the training variants of boss, bingo and journeys. Tests:
// TrainingXPRulesTests.

import Foundation

public struct TrainingPlanSignals: Sendable, Equatable {
    /// The morning traffic light of a CHECK-IN.
    public enum Light: String, Sendable, Equatable {
        case greenLight = "green"
        case amberLight = "amber"
        case redLight = "red"
    }

    /// A traffic-light option: G (as planned), A (easier), R (no running).
    public enum Option: String, Sendable, Equatable {
        case g = "G"
        case a = "A"
        case r = "R"
    }

    public enum RaceOutcome: String, Sendable, Equatable {
        case finished
        case dnf
        case dns
    }

    public struct Session: Sendable, Equatable {
        public let id: String
        public let isDone: Bool
        public let isSkipped: Bool
        /// The plan marked it missed (its day is over, nothing matched).
        public let isMissed: Bool
        public let isTrafficLight: Bool
        /// The option actually executed, when the plan can tell.
        public let doneOption: Option?
        public let isStrength: Bool
        public let isRace: Bool
        public let raceId: String?
        public let isTest: Bool
        public let hasTestResult: Bool
        public let hasRPE: Bool
        public let hasNote: Bool

        public init(
            id: String,
            isDone: Bool,
            isSkipped: Bool = false,
            isMissed: Bool = false,
            isTrafficLight: Bool = false,
            doneOption: Option? = nil,
            isStrength: Bool = false,
            isRace: Bool = false,
            raceId: String? = nil,
            isTest: Bool = false,
            hasTestResult: Bool = false,
            hasRPE: Bool = false,
            hasNote: Bool = false
        ) {
            self.id = id
            self.isDone = isDone
            self.isSkipped = isSkipped
            self.isMissed = isMissed
            self.isTrafficLight = isTrafficLight
            self.doneOption = doneOption
            self.isStrength = isStrength
            self.isRace = isRace
            self.raceId = raceId
            self.isTest = isTest
            self.hasTestResult = hasTestResult
            self.hasRPE = hasRPE
            self.hasNote = hasNote
        }
    }

    public struct Day: Sendable, Equatable {
        /// `yyyy-MM-dd`.
        public let day: String
        /// The day belongs to a written week of the plan (a rest day is
        /// one); `false` for a date only the phone knows.
        public let isInPlan: Bool
        /// The light of that morning's check-in; `nil` without a check-in
        /// (a light inferred from the executed option is not one).
        public let light: Light?
        /// The check-in carried a pain answer ("nothing hurts" is one).
        public let painAnswered: Bool
        public let habitsExpected: [String]
        public let habitsDone: [String]
        public let sessions: [Session]
        /// An activity no planned session matched, and it was a run.
        public let hasUnplannedRun: Bool
        public let isCarbLoad: Bool

        public init(
            day: String,
            isInPlan: Bool = true,
            light: Light? = nil,
            painAnswered: Bool = false,
            habitsExpected: [String] = [],
            habitsDone: [String] = [],
            sessions: [Session] = [],
            hasUnplannedRun: Bool = false,
            isCarbLoad: Bool = false
        ) {
            self.day = day
            self.isInPlan = isInPlan
            self.light = light
            self.painAnswered = painAnswered
            self.habitsExpected = habitsExpected
            self.habitsDone = habitsDone
            self.sessions = sessions
            self.hasUnplannedRun = hasUnplannedRun
            self.isCarbLoad = isCarbLoad
        }

        public var isCheckedIn: Bool { light != nil }
    }

    public struct Week: Sendable, Equatable {
        /// `YYYY-Www`.
        public let week: String
        public let isClosed: Bool
        /// Approved or already closed.
        public let isApproved: Bool
        /// A deload, taper, recovery or transition week.
        public let isEasy: Bool
        public let runKmTarget: Double?
        public let runKm: Double?
        public let unplannedRunKm: Double?
        public let overPlanKm: Double?

        public init(
            week: String,
            isClosed: Bool = false,
            isApproved: Bool = false,
            isEasy: Bool = false,
            runKmTarget: Double? = nil,
            runKm: Double? = nil,
            unplannedRunKm: Double? = nil,
            overPlanKm: Double? = nil
        ) {
            self.week = week
            self.isClosed = isClosed
            self.isApproved = isApproved
            self.isEasy = isEasy
            self.runKmTarget = runKmTarget
            self.runKm = runKm
            self.unplannedRunKm = unplannedRunKm
            self.overPlanKm = overPlanKm
        }
    }

    public struct Race: Sendable, Equatable {
        public let id: String
        /// `yyyy-MM-dd`.
        public let day: String
        public let isPrepComplete: Bool
        public let hasReport: Bool
        /// `nil` until the plan publishes a result.
        public let outcome: RaceOutcome?
        public let goalReached: Bool?
        public let isPersonalRecord: Bool?
        /// A stop rule ended the race, or kept the athlete from starting.
        public let stoppedByRule: Bool?
        public let fuelPlanFollowed: Bool?

        public init(
            id: String,
            day: String,
            isPrepComplete: Bool = false,
            hasReport: Bool = false,
            outcome: RaceOutcome? = nil,
            goalReached: Bool? = nil,
            isPersonalRecord: Bool? = nil,
            stoppedByRule: Bool? = nil,
            fuelPlanFollowed: Bool? = nil
        ) {
            self.id = id
            self.day = day
            self.isPrepComplete = isPrepComplete
            self.hasReport = hasReport
            self.outcome = outcome
            self.goalReached = goalReached
            self.isPersonalRecord = isPersonalRecord
            self.stoppedByRule = stoppedByRule
            self.fuelPlanFollowed = fuelPlanFollowed
        }
    }

    public struct Phase: Sendable, Equatable {
        public let id: String
        public let isClosed: Bool
        public let hasRecap: Bool

        public init(id: String, isClosed: Bool, hasRecap: Bool) {
            self.id = id
            self.isClosed = isClosed
            self.hasRecap = hasRecap
        }
    }

    public struct Season: Sendable, Equatable {
        public let id: String
        /// The last day of its period, `yyyy-MM-dd`.
        public let endDay: String?

        public init(id: String, endDay: String?) {
            self.id = id
            self.endDay = endDay
        }
    }

    /// The plan's today (`yyyy-MM-dd`).
    public let today: String
    /// Oldest first, up to `today`.
    public let days: [Day]
    public let weeks: [Week]
    /// The habits that are active ladder steps.
    public let activeHabitIds: [String]
    /// The ladder's gate share in percent (80).
    public let habitGatePercent: Int
    public let races: [Race]
    public let phases: [Phase]
    public let season: Season?
    /// The day of the last gate test that is not stale.
    public let gateTestDay: String?
    /// Event ids of plan changes the plan applied.
    public let appliedPlanEditIds: [String]

    public init(
        today: String,
        days: [Day] = [],
        weeks: [Week] = [],
        activeHabitIds: [String] = [],
        habitGatePercent: Int = 80,
        races: [Race] = [],
        phases: [Phase] = [],
        season: Season? = nil,
        gateTestDay: String? = nil,
        appliedPlanEditIds: [String] = []
    ) {
        self.today = today
        self.days = days
        self.weeks = weeks
        self.activeHabitIds = activeHabitIds
        self.habitGatePercent = min(max(habitGatePercent, 1), 100)
        self.races = races
        self.phases = phases
        self.season = season
        self.gateTestDay = gateTestDay
        self.appliedPlanEditIds = appliedPlanEditIds
    }

    public func day(_ key: String) -> Day? {
        days.first { $0.day == key }
    }
}
