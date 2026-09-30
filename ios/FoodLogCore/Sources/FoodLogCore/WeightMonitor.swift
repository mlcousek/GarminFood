// WeightMonitor.swift
//
// add-winter-arc-nutrition-and-rewards (A4): in the training experience
// weight is a monitor, not a goal -- "weight is an outcome, not a target;
// track the weekly morning average". So instead of a target, a progress
// bar and an ETA, the weight card shows:
//
//   - the 7-day MORNING average: weigh-ins in the last 7 days logged before
//     `morningCutoffHour` (07:00 local) -- a morning weight is the
//     comparable one (the same body reads ~2 kg heavier by midday). When
//     the window has no morning weigh-in at all, every weigh-in in it is
//     averaged instead (`usedMorningOnly == false` says so);
//   - the change against the 7 days before, in % a week, computed the same
//     way -- and ONE quiet flag: `isFallingTooFast` when the average fell by
//     more than `maxWeeklyLossPercent` (0.7 %, the plan's PM-FUEL-4 cap on
//     any weight loss, and none at all in a build). No other judgement:
//     gaining, holding or falling slowly says nothing.
//
// Pure: takes plain (date, kg) samples, so it is independent of where the
// weigh-ins came from (Garmin, this phone). Depended on by: the app's
// WeightLoader (training experience). Tests: WeightMonitorTests.

import Foundation

public struct WeightSample: Sendable, Equatable {
    public let date: Date
    public let kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct WeightMonitorSummary: Sendable, Equatable {
    /// The last 7 days' average in kg.
    public let averageKg: Double
    /// How many weigh-ins went into it.
    public let sampleCount: Int
    /// `false` when no morning weigh-in was in the window (all were used).
    public let usedMorningOnly: Bool
    /// Change against the previous 7 days in % a week (negative = lower),
    /// `nil` without weigh-ins in that week.
    public let weeklyChangePercent: Double?
    /// The quiet flag: the average fell faster than the plan allows.
    public let isFallingTooFast: Bool
}

public enum WeightMonitor {
    public static let morningCutoffHour = 7
    public static let windowDays = 7
    /// PM-FUEL-4: any weight loss at most 0.7 % a week (and never in a build).
    public static let maxWeeklyLossPercent = 0.7

    /// The summary at `now`, or `nil` without any weigh-in in the last 7
    /// days.
    public static func summary(samples: [WeightSample], now: Date, calendar: Calendar = .current) -> WeightMonitorSummary? {
        let valid = samples.filter { $0.kg.isFinite && $0.kg > 0 && $0.date <= now }
        let dayLength = TimeInterval(windowDays * 24 * 3600)
        let currentStart = now.addingTimeInterval(-dayLength)
        let previousStart = now.addingTimeInterval(-2 * dayLength)
        let current = valid.filter { $0.date > currentStart }
        let previous = valid.filter { $0.date > previousStart && $0.date <= currentStart }
        guard let currentAverage = average(current, calendar: calendar) else { return nil }
        let previousAverage = average(previous, calendar: calendar)
        let change = previousAverage.map { ($0.kg > 0) ? (currentAverage.kg - $0.kg) / $0.kg * 100 : 0 }
        return WeightMonitorSummary(
            averageKg: currentAverage.kg,
            sampleCount: currentAverage.count,
            usedMorningOnly: currentAverage.morningOnly,
            weeklyChangePercent: change,
            isFallingTooFast: (change ?? 0) < -maxWeeklyLossPercent
        )
    }

    /// The morning weigh-ins' mean, else every weigh-in's mean.
    static func average(_ samples: [WeightSample], calendar: Calendar) -> (kg: Double, count: Int, morningOnly: Bool)? {
        guard !samples.isEmpty else { return nil }
        let morning = samples.filter { calendar.component(.hour, from: $0.date) < morningCutoffHour }
        let used = morning.isEmpty ? samples : morning
        let mean = used.reduce(0) { $0 + $1.kg } / Double(used.count)
        return (mean, used.count, !morning.isEmpty)
    }
}
