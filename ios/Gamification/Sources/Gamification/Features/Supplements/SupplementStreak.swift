// SupplementStreak.swift
//
// add-supplements D9 / spec "A supplement streak counts consecutive
// stack-complete days": the supplement streak as a pure forward walk over
// the digest's days (FoodLogCore `SupplementSignals`, oldest first), the
// same shape as `StreakEngine.simulate` so the shared freeze planner can
// treat both streaks alike. Per day, up to today:
//
//   - complete: +1;
//   - neutral (nothing planned, or a day the feature was paused -- see
//     SupplementsFeature.prepare): no change, never a break;
//   - today, not complete yet: pending (in progress, never a miss);
//   - frozen (a streak freeze covered it, `frozenDays`): no change, never
//     a break;
//   - otherwise (partial or missed): the streak resets to 0.
//
// Unlike the food streak there is no weekly grace: the spec's "Missed day"
// scenario breaks the streak on the first incomplete planned day. The walk
// only sees the digest window (365 days), so a longer streak reads as the
// window length -- recorded as `longestStreak` by the feature.
//
// Pure: day keys in, lengths out.
//
// Depends on: FoodLogCore (SupplementDaySignal, SupplementSignals).
// Depended on by: StreakFreezePlanner.planShared, SupplementsEvaluator,
// the app's GamificationEngine (the streak shown on the Supplements
// screen). Tests: SupplementStreakTests.

import Foundation
import FoodLogCore

public enum SupplementStreak {
    public enum Outcome: String, Sendable, Equatable {
        case complete
        case neutral
        /// Today, not complete yet.
        case pending
        case frozen
        case missed
    }

    public struct Walk: Sendable, Equatable {
        public var outcomes: [String: Outcome] = [:]
        /// The running length immediately BEFORE each walked day (what a
        /// miss on that day destroys) -- freezes protect only 3+ days.
        public var lengthBefore: [String: Int] = [:]
        public var currentLength = 0
        public var longestLength = 0
    }

    public struct Status: Sendable, Equatable {
        public let length: Int
        /// The longest run inside the digest window.
        public let longest: Int
        public let isCompleteToday: Bool
        /// A running streak and today planned but not complete yet.
        public let isAtRiskToday: Bool

        public init(length: Int, longest: Int, isCompleteToday: Bool, isAtRiskToday: Bool) {
            self.length = length
            self.longest = longest
            self.isCompleteToday = isCompleteToday
            self.isAtRiskToday = isAtRiskToday
        }

        public static let zero = Status(length: 0, longest: 0, isCompleteToday: false, isAtRiskToday: false)
    }

    /// The forward walk described in this file's header. Days after
    /// `today` are ignored.
    public static func walk(days: [SupplementDaySignal], frozenDays: Set<String>, today: String) -> Walk {
        var result = Walk()
        for day in days.sorted(by: { $0.day < $1.day }) where day.day <= today {
            result.lengthBefore[day.day] = result.currentLength
            switch day.status {
            case .complete:
                result.currentLength += 1
                result.longestLength = max(result.longestLength, result.currentLength)
                result.outcomes[day.day] = .complete
            case .neutral:
                result.outcomes[day.day] = .neutral
            case .partial, .missed:
                if day.day == today {
                    result.outcomes[day.day] = .pending
                } else if frozenDays.contains(day.day) {
                    result.outcomes[day.day] = .frozen
                } else {
                    result.currentLength = 0
                    result.outcomes[day.day] = .missed
                }
            }
        }
        return result
    }

    /// The streak of a digest (its own `frozenDays`).
    public static func status(_ signals: SupplementSignals) -> Status {
        let result = Self.walk(days: signals.days, frozenDays: signals.frozenDays, today: signals.today)
        let todayOutcome = result.outcomes[signals.today]
        return Status(
            length: result.currentLength,
            longest: result.longestLength,
            isCompleteToday: todayOutcome == .complete,
            isAtRiskToday: todayOutcome == .pending && result.currentLength > 0
        )
    }
}
