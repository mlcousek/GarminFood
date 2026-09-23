// CalorieBand.swift
//
// The home screen calorie ring's stepped colour scale (fix-testing-feedback-
// quick-wins, today-dashboard spec "The calorie ring colour reflects
// progress in steps"). The owner's 2026-09-23 test pass found the old
// single +/-10% band (`TodaySummary.GoalState`, still used by the macro
// bars and meal cards) too coarse for the ring: it stayed one colour right
// up to 90%, so it said nothing about how the day was actually going.
//
// Pure and SwiftUI-free, so the step boundaries -- the only part that can
// be wrong -- are unit-tested here (CalorieBandTests). The app target maps
// each case to a colour (`CalorieBand.tint` in Components.swift) and does
// nothing else with it. Depends on `MacroProgress` (MealDashboard.swift)
// only for the convenience accessor at the bottom.

import Foundation

public enum CalorieBand: String, Sendable, Equatable, CaseIterable {
    /// Under 50% of the Target -- early in the day. Cool grey-blue.
    case low
    /// 50% up to (not including) 80%. Orange.
    case building
    /// 80% up to (not including) 95%. Yellow.
    case approaching
    /// 95% to 105%, both inclusive -- the goal band. Green.
    case onTarget
    /// Over 105% up to and including 115%. Orange.
    case slightlyOver
    /// Over 115%. Red.
    case over

    /// The band for a percentage of the Target eaten (`100` = exactly on
    /// target). The boundaries are the spec's table verbatim: lower bounds
    /// inclusive for the under-target steps, and the goal band closed on
    /// both ends, so exactly 95 and exactly 105 are both green.
    public static func band(forPercent percent: Double) -> CalorieBand {
        if percent < 50 { return .low }
        if percent < 80 { return .building }
        if percent < 95 { return .approaching }
        if percent <= 105 { return .onTarget }
        if percent <= 115 { return .slightlyOver }
        return .over
    }
}

extension MacroProgress {
    /// This progress as a `CalorieBand`, or `nil` without a usable target
    /// (same `goal > 0` rule as `fraction`/`state`), in which case the ring
    /// keeps its neutral colour.
    ///
    /// The percentage is rounded to one decimal place first, so a value a
    /// floating-point hair off a boundary (2645 / 2300 * 100 evaluates to
    /// 114.99999999999999, not 115) lands in the band a person reading the
    /// same "115%" would expect, rather than depending on binary noise.
    public var calorieBand: CalorieBand? {
        guard let goal, goal > 0 else { return nil }
        let percent = (consumed / goal * 1000).rounded() / 10
        return CalorieBand.band(forPercent: percent)
    }
}
