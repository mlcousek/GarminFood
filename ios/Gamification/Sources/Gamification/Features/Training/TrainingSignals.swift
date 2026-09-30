// TrainingSignals.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the training plan's facts as
// Gamification reads them -- plain values, so this package never imports
// TrainingCore (it depends only on FoodLogCore). The app's one small
// adapter (GarminFood/Training/TrainingRewardsAdapter.swift) copies
// TrainingCore's `TrainingRewardFacts` into this shape; the facts' meaning
// (what counts as a check-in, an honest light followed, a strength session
// done, a week kept within plan) is defined and tested in TrainingCore.
//
// Days are `yyyy-MM-dd` and weeks `YYYY-Www`, the strings both sides
// already use, so the store can keep them as ids.
//
// Depended on by: FeatureContext, TrainingRewardsFeature. Tests:
// TrainingRewardsTests.

import Foundation

public struct TrainingSignals: Sendable, Equatable {
    public struct Day: Sendable, Equatable {
        /// `yyyy-MM-dd`.
        public let day: String
        public let checkedIn: Bool
        public let honestLightFollowed: Bool
        public let strengthSessionsDone: Int
        public let habitTicks: Int

        public init(day: String, checkedIn: Bool, honestLightFollowed: Bool, strengthSessionsDone: Int, habitTicks: Int) {
            self.day = day
            self.checkedIn = checkedIn
            self.honestLightFollowed = honestLightFollowed
            self.strengthSessionsDone = max(0, strengthSessionsDone)
            self.habitTicks = max(0, habitTicks)
        }
    }

    public struct Week: Sendable, Equatable {
        /// `YYYY-Www`.
        public let week: String
        public let isClosed: Bool
        public let keptWithinPlan: Bool
        public let strengthSessionsDone: Int

        public init(week: String, isClosed: Bool, keptWithinPlan: Bool, strengthSessionsDone: Int) {
            self.week = week
            self.isClosed = isClosed
            self.keptWithinPlan = keptWithinPlan
            self.strengthSessionsDone = max(0, strengthSessionsDone)
        }
    }

    /// The plan's today (`yyyy-MM-dd`).
    public let today: String
    /// The plan's current week (`YYYY-Www`), for the summary.
    public let currentWeek: String?
    public let days: [Day]
    public let weeks: [Week]

    public init(today: String, currentWeek: String?, days: [Day], weeks: [Week]) {
        self.today = today
        self.currentWeek = currentWeek
        self.days = days
        self.weeks = weeks
    }
}
