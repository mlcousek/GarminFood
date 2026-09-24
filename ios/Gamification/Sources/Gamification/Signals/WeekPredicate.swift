// WeekPredicate.swift
//
// The "over a span of days" half of the shared rule vocabulary (design D6):
// "fish on 2 days", "all six colours across the week", "3 different Czech
// brands". Evaluated by `SignalEvaluator` over any list of days -- an ISO
// week (`WeekKey.dayKeys`) for bingo/boss, or a challenge's own window for
// the creative long-running challenges.
//
// Depends on: DayPredicate, FoodLogCore (FoodTag).
// Depended on by: SignalEvaluator, ChallengeKind.signalWeek, wave-2 bingo
// and boss features.

import Foundation
import FoodLogCore

public enum WeekPredicate: Sendable, Equatable, Codable {
    /// At least `atLeast` days on which the day predicate holds.
    case daysSatisfying(DayPredicate, atLeast: Int)
    /// At least `atLeast` distinct tags with `prefix` across all the days.
    case distinctTagsAcrossWeek(prefix: String, atLeast: Int)
    /// At least `atLeast` distinct Czech brands (folded) across the days.
    case distinctCzechBrandsAtLeast(Int)
    /// At least `atLeast` distinct foods first seen on one of the days.
    case newFoodsAtLeast(Int)

    public var requirement: DataRequirement {
        switch self {
        case .daysSatisfying(let predicate, _): return predicate.requirement
        case .distinctTagsAcrossWeek, .distinctCzechBrandsAtLeast, .newFoodsAtLeast: return []
        }
    }

    /// The number `SignalEvaluator.progress` counts toward.
    public var target: Int {
        switch self {
        case .daysSatisfying(_, let atLeast): return atLeast
        case .distinctTagsAcrossWeek(_, let atLeast): return atLeast
        case .distinctCzechBrandsAtLeast(let atLeast): return atLeast
        case .newFoodsAtLeast(let atLeast): return atLeast
        }
    }
}
