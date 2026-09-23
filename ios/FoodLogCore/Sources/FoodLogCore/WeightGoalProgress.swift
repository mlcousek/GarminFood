// WeightGoalProgress.swift
//
// Goals for weight and water (sync-weight-hydration-with-garmin, design.md
// D5). WHY: the owner wants Garmin's own goals by default -- the water goal
// is Garmin's `goalInML` (hydration daily read), the weight goal is
// `targetWeightGoal`/`startingWeight` from nutrition settings (both
// live-verified 2026-09-23) -- with a local override in Settings that
// never writes back to Garmin (proposal non-goal). This file holds the two
// pure pieces of that:
//
//   - `GoalResolution`: override, else Garmin, else a fallback (2000 ml for
//     water; none for weight, so the card hides its goal bar).
//   - `WeightGoalProgress`: start -> current -> target as a fraction, kg to
//     go, and an ETA from the last 14 days' least-squares trend (>= 4
//     weigh-ins) or else Garmin's planned `weightChangeRate` -- shown only
//     when that trend actually points at the target.
//
// Pure and clock-free (`now` is passed in), unit-tested in
// FoodLogCoreTests/WeightGoalProgressTests.swift. Garmin's weight values are
// GRAMS (80400 = 80.4 kg); everything this file returns is kilograms. The
// app's `GoalPreferences` stores the overrides; `WeightLoader`/
// `HydrationLoader` call in here.

import Foundation

/// Where a goal's value comes from, per goal (D5).
public enum GoalSource: Sendable, Equatable {
    /// Use Garmin's value (the default).
    case garmin
    /// A local override, in the goal's own unit (ml for water, kg for
    /// weight).
    case override(Double)
}

/// Where an effective goal's value actually came from -- `fallback` when
/// Garmin had no value and there is no override.
public enum GoalOrigin: Sendable, Equatable {
    case garmin
    case override
    case fallback
}

public struct EffectiveWaterGoal: Sendable, Equatable {
    public let milliliters: Double
    public let origin: GoalOrigin

    public init(milliliters: Double, origin: GoalOrigin) {
        self.milliliters = milliliters
        self.origin = origin
    }
}

public struct EffectiveWeightGoal: Sendable, Equatable {
    public let targetKg: Double
    /// Where the journey started -- `nil` when neither Garmin nor an
    /// override knows it (progress then has no fraction to show).
    public let startKg: Double?
    /// Origin of `targetKg`.
    public let origin: GoalOrigin
    /// Garmin's planned rate, grams per week (magnitude), and its
    /// direction ("LOSS"/"GAIN"/...), for the ETA fallback.
    public let plannedRateGramsPerWeek: Double?
    public let plannedChangeType: String?

    public init(targetKg: Double, startKg: Double?, origin: GoalOrigin, plannedRateGramsPerWeek: Double? = nil, plannedChangeType: String? = nil) {
        self.targetKg = targetKg
        self.startKg = startKg
        self.origin = origin
        self.plannedRateGramsPerWeek = plannedRateGramsPerWeek
        self.plannedChangeType = plannedChangeType
    }
}

public enum GoalResolution {
    /// The water goal when there is neither an override nor a Garmin goal
    /// -- the app's old local default.
    public static let fallbackWaterGoalML: Double = 2000

    /// Override, else Garmin's `goalInML`, else `fallbackWaterGoalML`.
    /// Non-positive values count as "not set" on either side.
    public static func water(source: GoalSource, garminGoalML: Double?) -> EffectiveWaterGoal {
        if case .override(let value) = source, value > 0 {
            return EffectiveWaterGoal(milliliters: value, origin: .override)
        }
        if let garminGoalML, garminGoalML > 0 {
            return EffectiveWaterGoal(milliliters: garminGoalML, origin: .garmin)
        }
        return EffectiveWaterGoal(milliliters: fallbackWaterGoalML, origin: .fallback)
    }

    /// Target: override, else Garmin's `targetWeightGoal`; `nil` when
    /// neither exists (no fallback -- the card hides the goal bar). Start:
    /// `startOverrideKg`, else Garmin's `startingWeight`. Garmin's values
    /// are GRAMS; non-positive values count as "not set".
    public static func weight(
        targetSource: GoalSource,
        startOverrideKg: Double?,
        garminTargetGrams: Double?,
        garminStartGrams: Double?,
        garminRateGramsPerWeek: Double? = nil,
        garminChangeType: String? = nil
    ) -> EffectiveWeightGoal? {
        let garminTargetKg = garminTargetGrams.flatMap { $0 > 0 ? $0 / 1000 : nil }
        let garminStartKg = garminStartGrams.flatMap { $0 > 0 ? $0 / 1000 : nil }
        let startKg = startOverrideKg.flatMap { $0 > 0 ? $0 : nil } ?? garminStartKg

        let targetKg: Double
        let origin: GoalOrigin
        if case .override(let value) = targetSource, value > 0 {
            targetKg = value
            origin = .override
        } else if let garminTargetKg {
            targetKg = garminTargetKg
            origin = .garmin
        } else {
            return nil
        }
        return EffectiveWeightGoal(
            targetKg: targetKg,
            startKg: startKg,
            origin: origin,
            plannedRateGramsPerWeek: garminRateGramsPerWeek,
            plannedChangeType: garminChangeType
        )
    }
}

/// One weigh-in, for the trend fit.
public struct WeightTrendPoint: Sendable, Equatable {
    public let date: Date
    public let kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct WeightGoalProgress: Sendable, Equatable {
    public enum Direction: Sendable, Equatable {
        case lose
        case gain
    }

    public enum ETASource: Sendable, Equatable {
        /// The least-squares slope of recent weigh-ins.
        case trend
        /// Garmin's planned `weightChangeRate`.
        case garminPlan
    }

    public let startKg: Double?
    public let currentKg: Double
    public let targetKg: Double
    public let direction: Direction
    /// 0 at the start weight, 1 at the target, clamped -- `nil` without a
    /// usable start weight.
    public let fraction: Double?
    /// How far the current weight still is from the target in the goal's
    /// direction; 0 once reached or passed.
    public let kgToGo: Double
    public let isReached: Bool
    public let eta: Date?
    public let etaSource: ETASource?

    /// Within this of the target counts as reached.
    public static let reachedToleranceKg = 0.05
    /// The trend window and the fewest weigh-ins it needs (D5).
    public static let trendWindowDays = 14
    public static let trendMinimumSamples = 4
    /// An ETA further out than this is noise, not a forecast.
    public static let maximumETADays: Double = 3 * 365

    public static func compute(
        goal: EffectiveWeightGoal,
        currentKg: Double,
        recentWeighIns: [WeightTrendPoint],
        now: Date
    ) -> WeightGoalProgress {
        let target = goal.targetKg
        let start = goal.startKg

        let direction: Direction
        if let start, abs(start - target) > reachedToleranceKg {
            direction = target < start ? .lose : .gain
        } else {
            direction = target <= currentKg ? .lose : .gain
        }

        let rawToGo = direction == .lose ? currentKg - target : target - currentKg
        let kgToGo = max(rawToGo, 0)
        let isReached = rawToGo <= reachedToleranceKg

        var fraction: Double?
        if let start, abs(start - target) > reachedToleranceKg {
            fraction = min(max((start - currentKg) / (start - target), 0), 1)
        } else if start != nil {
            fraction = isReached ? 1 : 0
        }

        var eta: Date?
        var etaSource: ETASource?
        if !isReached {
            let slopeKgPerDay: Double?
            let source: ETASource
            if let trend = trendSlopeKgPerDay(recentWeighIns, now: now) {
                slopeKgPerDay = trend
                source = .trend
            } else {
                slopeKgPerDay = plannedSlopeKgPerDay(goal)
                source = .garminPlan
            }
            if let slope = slopeKgPerDay {
                let towardTarget = (direction == .lose && slope < 0) || (direction == .gain && slope > 0)
                if towardTarget {
                    let days = kgToGo / abs(slope)
                    if days.isFinite, days <= maximumETADays {
                        eta = now.addingTimeInterval(days * 86_400)
                        etaSource = source
                    }
                }
            }
        }

        return WeightGoalProgress(
            startKg: start,
            currentKg: currentKg,
            targetKg: target,
            direction: direction,
            fraction: fraction,
            kgToGo: kgToGo,
            isReached: isReached,
            eta: eta,
            etaSource: etaSource
        )
    }

    /// Least-squares slope (kg/day) of the weigh-ins in the last
    /// `trendWindowDays` before `now` -- `nil` with fewer than
    /// `trendMinimumSamples` of them, or when they all sit at (nearly) the
    /// same moment, where a slope means nothing.
    public static func trendSlopeKgPerDay(_ points: [WeightTrendPoint], now: Date) -> Double? {
        let windowStart = now.addingTimeInterval(-Double(trendWindowDays) * 86_400)
        let window = points.filter { $0.date >= windowStart && $0.date <= now }
        guard window.count >= trendMinimumSamples,
              let earliest = window.map(\.date).min() else { return nil }

        let xs = window.map { $0.date.timeIntervalSince(earliest) / 86_400 }
        let ys = window.map(\.kg)
        let n = Double(window.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var covariance = 0.0
        var varianceX = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - meanX) * (y - meanY)
            varianceX += (x - meanX) * (x - meanX)
        }
        // Weigh-ins bunched within a few hours of each other (sum of
        // squared deviations under 1/24 day²): no meaningful daily trend.
        guard varianceX > 1.0 / 24.0 else { return nil }
        return covariance / varianceX
    }

    /// Garmin's planned rate as a signed kg/day slope: negative for
    /// "LOSS", positive for "GAIN", `nil` otherwise (e.g. "MAINTAIN") or
    /// without a positive rate. `weightChangeRate` is presumed grams per
    /// week (250 observed with a LOSS plan, docs/garmin-routes.json).
    static func plannedSlopeKgPerDay(_ goal: EffectiveWeightGoal) -> Double? {
        guard let rate = goal.plannedRateGramsPerWeek, rate > 0 else { return nil }
        let kgPerDay = rate / 1000 / 7
        switch goal.plannedChangeType?.uppercased() {
        case "LOSS": return -kgPerDay
        case "GAIN": return kgPerDay
        default: return nil
        }
    }
}
