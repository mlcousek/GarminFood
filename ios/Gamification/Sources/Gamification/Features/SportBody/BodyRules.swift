// BodyRules.swift
//
// add-sport-and-body-achievements design D2 (body rows): weight milestones
// against the effective weight goal (`ProfileSignals.weightGoal` -- the
// local override, else Garmin's nutrition-settings `startingWeight`/
// `targetWeight`) and the kept-fast streak tiers.
//
//   - direction: loss when target < start - 0.5 kg, gain when target >
//     start + 0.5 kg, else maintenance (only Steady applies);
//   - First Kilo: a weigh-in >= 1.0 kg from the start in the goal's
//     direction; Halfway: progress >= 50 %; Target: at or beyond the target
//     with 0.2 kg tolerance;
//   - without a start weight the direction is unknown, so only Target (then
//     read as "within 0.2 kg of the target") and Steady apply;
//   - Steady as Sněžka: some 30 consecutive days, all inside the window,
//     whose every weigh-in is within ±1.0 kg of the target, with >= 8
//     weigh-ins among them.
//
// Weigh-ins come from the 42-day signals window only; badges are permanent
// in `AchievementStore`, so a later goal change never re-arms or revokes
// them.
//
// Fasting: the kept streak is recomputed from the window's per-day
// `fasting` outcomes with `FastingDayEvaluator.keptStreak`'s rules -- a
// broken fast ends it; today's not-yet-judged fast is skipped; any earlier
// day without a verdict (not tracked / fasting off) ends it.
//
// Pure; tested in BodyRulesTests.
//
// Depends on: FoodLogCore (SignalsSnapshot, WeightGoalSignal),
// SportBodyCatalog (badge ids), SportRules.dayKey.
// Depended on by: SportAndBodyFeature.

import Foundation
import FoodLogCore

public enum WeightGoalDirection: String, Sendable, Equatable {
    case loss, gain, maintenance
}

/// The weight-goal picture the Sport & Body screen shows.
public struct WeightMilestoneProgress: Sendable, Equatable {
    public let startKg: Double?
    public let targetKg: Double
    /// `nil` without a start weight.
    public let direction: WeightGoalDirection?
    /// The newest weigh-in of the window.
    public let latestKg: Double?
    /// Start -> target progress of `latestKg`, clamped to 0...1; `nil` for
    /// maintenance, no start, or no weigh-in.
    public let fraction: Double?

    public init(startKg: Double?, targetKg: Double, direction: WeightGoalDirection?, latestKg: Double?, fraction: Double?) {
        self.startKg = startKg
        self.targetKg = targetKg
        self.direction = direction
        self.latestKg = latestKg
        self.fraction = fraction
    }
}

public enum BodyRules {
    static let epsilon = 1e-9

    public static let directionThresholdKg: Double = 0.5
    public static let firstKiloKg: Double = 1.0
    public static let halfwayFraction: Double = 0.5
    public static let targetToleranceKg: Double = 0.2
    public static let steadyToleranceKg: Double = 1.0
    public static let steadyDays = 30
    public static let steadyMinimumWeighIns = 8

    // MARK: Weight

    public static func direction(startKg: Double?, targetKg: Double) -> WeightGoalDirection? {
        guard let startKg else { return nil }
        if targetKg < startKg - directionThresholdKg { return .loss }
        if targetKg > startKg + directionThresholdKg { return .gain }
        return .maintenance
    }

    /// Start -> target progress (unclamped: > 1 beyond the target, < 0 the
    /// wrong way); `nil` for maintenance or without a start.
    public static func progress(weightKg: Double, startKg: Double?, targetKg: Double) -> Double? {
        guard let startKg else { return nil }
        switch direction(startKg: startKg, targetKg: targetKg) {
        case .loss?:
            return (startKg - weightKg) / (startKg - targetKg)
        case .gain?:
            return (weightKg - startKg) / (targetKg - startKg)
        case .maintenance?, nil:
            return nil
        }
    }

    public static func reachedFirstKilo(weightKg: Double, startKg: Double?, targetKg: Double) -> Bool {
        guard let startKg else { return false }
        switch direction(startKg: startKg, targetKg: targetKg) {
        case .loss?: return startKg - weightKg >= firstKiloKg - epsilon
        case .gain?: return weightKg - startKg >= firstKiloKg - epsilon
        case .maintenance?, nil: return false
        }
    }

    public static func reachedHalfway(weightKg: Double, startKg: Double?, targetKg: Double) -> Bool {
        guard let fraction = progress(weightKg: weightKg, startKg: startKg, targetKg: targetKg) else { return false }
        return fraction >= halfwayFraction - epsilon
    }

    public static func reachedTarget(weightKg: Double, startKg: Double?, targetKg: Double) -> Bool {
        switch direction(startKg: startKg, targetKg: targetKg) {
        case .loss?: return weightKg <= targetKg + targetToleranceKg + epsilon
        case .gain?: return weightKg >= targetKg - targetToleranceKg - epsilon
        case .maintenance?: return false
        case nil: return abs(weightKg - targetKg) <= targetToleranceKg + epsilon
        }
    }

    /// Whether some run of 30 consecutive days, entirely inside the window
    /// and ending no later than today, has >= 8 weigh-ins, all within
    /// ±1.0 kg of `targetKg`.
    public static func steadyMet(in snapshot: SignalsSnapshot, targetKg: Double, calendar: Calendar) -> Bool {
        guard let windowStart = snapshot.windowDays.first else { return false }
        let weighIns: [(day: String, kg: Double)] = snapshot.orderedDays.compactMap { day -> (day: String, kg: Double)? in
            guard let kg = day.weighInKg else { return nil }
            return (day: day.day, kg: kg)
        }
        guard weighIns.count >= steadyMinimumWeighIns else { return false }
        for end in snapshot.windowDays where end <= snapshot.today {
            guard let start = SportRules.dayKey(end, offsetBy: -(steadyDays - 1), calendar: calendar),
                  start >= windowStart
            else { continue }
            let inRun = weighIns.filter { $0.day >= start && $0.day <= end }
            if inRun.count >= steadyMinimumWeighIns,
               inRun.allSatisfy({ abs($0.kg - targetKg) <= steadyToleranceKg + epsilon }) {
                return true
            }
        }
        return false
    }

    /// The weight-goal overview; `nil` without a target.
    public static func milestoneProgress(in snapshot: SignalsSnapshot) -> WeightMilestoneProgress? {
        guard let goal = snapshot.profile.weightGoal, let targetKg = goal.targetKg, targetKg > 0 else { return nil }
        let startKg = goal.startKg.flatMap { $0 > 0 ? $0 : nil }
        let latest = snapshot.orderedDays.last(where: { $0.weighInKg != nil })?.weighInKg
        let fraction = latest
            .flatMap { progress(weightKg: $0, startKg: startKg, targetKg: targetKg) }
            .map { min(max($0, 0), 1) }
        return WeightMilestoneProgress(
            startKg: startKg,
            targetKg: targetKg,
            direction: direction(startKg: startKg, targetKg: targetKg),
            latestKg: latest,
            fraction: fraction
        )
    }

    /// The weight milestones that can still apply to a goal of `direction`
    /// (`nil` = no start weight), in display order.
    public static func applicableMilestoneIds(direction: WeightGoalDirection?) -> [String] {
        switch direction {
        case .loss?, .gain?:
            return SportBodyCatalog.weightMilestoneIds
        case .maintenance?:
            return [SportBodyCatalog.steadyId]
        case nil:
            return [SportBodyCatalog.targetId, SportBodyCatalog.steadyId]
        }
    }

    /// Every weight badge the window's weigh-ins earn, in catalog order.
    public static func weightBadgeIds(in snapshot: SignalsSnapshot, calendar: Calendar) -> [String] {
        guard let goal = snapshot.profile.weightGoal, let targetKg = goal.targetKg, targetKg > 0 else { return [] }
        let startKg = goal.startKg.flatMap { $0 > 0 ? $0 : nil }
        let weights = snapshot.orderedDays.filter { $0.day <= snapshot.today }.compactMap(\.weighInKg)
        var result: [String] = []
        if weights.contains(where: { reachedFirstKilo(weightKg: $0, startKg: startKg, targetKg: targetKg) }) {
            result.append(SportBodyCatalog.firstKiloId)
        }
        if weights.contains(where: { reachedHalfway(weightKg: $0, startKg: startKg, targetKg: targetKg) }) {
            result.append(SportBodyCatalog.halfwayId)
        }
        if weights.contains(where: { reachedTarget(weightKg: $0, startKg: startKg, targetKg: targetKg) }) {
            result.append(SportBodyCatalog.targetId)
        }
        if steadyMet(in: snapshot, targetKg: targetKg, calendar: calendar) {
            result.append(SportBodyCatalog.steadyId)
        }
        return result
    }

    // MARK: Fasting

    /// Consecutive kept fasts counting back from today.
    public static func keptFastingStreak(in snapshot: SignalsSnapshot) -> Int {
        var streak = 0
        for key in snapshot.windowDays.reversed() where key <= snapshot.today {
            switch snapshot.days[key]?.fasting {
            case .kept?:
                streak += 1
            case .broken?:
                return streak
            case nil:
                if key == snapshot.today { continue }
                return streak
            }
        }
        return streak
    }

    /// Fasting badge ids the streak has reached, in tier order.
    public static func fastingBadgeIds(streak: Int) -> [String] {
        SportBodyCatalog.fastingTiers.filter { streak >= $0.threshold }.map(\.id)
    }
}
