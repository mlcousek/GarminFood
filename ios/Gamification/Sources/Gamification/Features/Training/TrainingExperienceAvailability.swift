// TrainingExperienceAvailability.swift
//
// add-winter-arc-nutrition-and-rewards (D1): in the training experience the
// plan decides how to eat -- "no diet, weight is an outcome, eat for the
// training" -- so gamification must not reward the opposite. This file is
// the one list of what goes quiet there (the food-first experience is
// untouched; every rule here is a no-op with `isTraining == false`):
//
//   - records: "Biggest active day" (`activeKcalDay`) and "Longest fast"
//     (`longestFast`) keep their values silently but announce no PR, pay
//     no XP and count toward no record badge (`quietRecords`);
//   - badges: the four fasting-streak tiers and the four weight-goal
//     milestones are not unlocked and are hidden unless already earned
//     (`hiddenBadgeIds`) -- earned ones stay: they were earned;
//   - challenges, daily challenges, bingo squares and the boss that judge
//     the FIXED calorie target ("hit your calorie goal", "all four goals",
//     the Calorie Kraken) are not offered. An already running one finishes
//     normally; goal status itself is judged by the carb band in this
//     experience (FoodLogCore's GoalStatusEvaluator), so it can't punish
//     eating inside the band either way.
//
// The training rewards that REPLACE them live in TrainingRewardsFeature.
// The inverse also holds: its badges are hidden outside the training
// experience unless earned (`visibleBadges`).
//
// Pure. Depended on by: PersonalRecordsFeature, SportAndBodyFeature,
// WeeklyBossFeature (BossPicker), WeeklyBingoFeature, ChallengeRotationPolicy,
// the app's GamificationEngine (daily challenges) and FeatureHost (visible
// badges). Tests: TrainingRewardsTests.

import Foundation
import FoodLogCore

public enum TrainingExperienceAvailability {
    /// Records that stay quiet in the training experience.
    public static let quietRecords: Set<PersonalRecordId> = [.activeKcalDay, .longestFast]

    /// Badge ids never unlocked (and hidden unless earned) in the training
    /// experience: fasting-streak tiers and weight-goal milestones.
    public static let hiddenBadgeIds: Set<String> = {
        var ids = Set(SportBodyCatalog.fastingTiers.map(\.id))
        ids.formUnion(SportBodyCatalog.weightMilestoneIds)
        return ids
    }()

    /// The boss archetype that fights for the fixed calorie target.
    public static let excludedBoss: BossKind = .calorieKraken

    // MARK: Badges

    /// The badges to list: in the training experience without the hidden
    /// fasting/weight ones not yet earned; outside it without the training
    /// badges not yet earned.
    public static func visibleBadges(
        _ catalog: [AchievementDefinition],
        isTraining: Bool,
        unlockedIds: Set<String>
    ) -> [AchievementDefinition] {
        catalog.filter { definition in
            if unlockedIds.contains(definition.id) { return true }
            if isTraining { return !hiddenBadgeIds.contains(definition.id) }
            return definition.featureId != TrainingRewardsFeature.id
        }
    }

    // MARK: The fixed calorie target

    /// Whether a day rule judges the fixed calorie goal.
    public static func judgesFixedCalorieTarget(_ predicate: DayPredicate) -> Bool {
        switch predicate {
        case .goalMet(.calories):
            return true
        case .all(let predicates), .any(let predicates):
            return predicates.contains { judgesFixedCalorieTarget($0) }
        default:
            return false
        }
    }

    public static func judgesFixedCalorieTarget(_ predicate: WeekPredicate) -> Bool {
        if case .daysSatisfying(let day, _) = predicate {
            return judgesFixedCalorieTarget(day)
        }
        return false
    }

    /// A long-running challenge judged by the fixed calorie target.
    public static func judgesFixedCalorieTarget(_ template: ChallengeTemplate) -> Bool {
        switch template.kind {
        case .goalHitDays(let macro, _):
            return macro == .calories
        case .goalHitStreak(let macro, _):
            // `nil` = any goal: a carb/protein day counts too, so it stays.
            return macro == .calories
        case .allGoalsHitDays:
            return true
        case .signalDays(let predicate, _):
            return judgesFixedCalorieTarget(predicate)
        case .signalWeek(let predicate):
            return judgesFixedCalorieTarget(predicate)
        default:
            return false
        }
    }

    /// A daily challenge judged by the fixed calorie target.
    public static func judgesFixedCalorieTarget(_ template: DailyChallengeTemplate) -> Bool {
        switch template.kind {
        case .hitCalorieGoal, .hitAllGoals:
            return true
        case .hitMacroGoal(let macro):
            return macro == .calories
        default:
            return false
        }
    }

    public static func judgesFixedCalorieTarget(_ task: BingoTask) -> Bool {
        switch task.scope {
        case .day(let predicate): return judgesFixedCalorieTarget(predicate)
        case .week(let predicate): return judgesFixedCalorieTarget(predicate)
        case .training: return false
        }
    }

    /// The daily-challenge catalog to pick from.
    public static func dailyCatalog(_ catalog: [DailyChallengeTemplate], isTraining: Bool) -> [DailyChallengeTemplate] {
        guard isTraining else { return catalog }
        return catalog.filter { !judgesFixedCalorieTarget($0) }
    }

    /// The bingo tasks a card may use.
    public static func bingoTasks(_ tasks: [BingoTask], isTraining: Bool) -> [BingoTask] {
        guard isTraining else { return tasks }
        return tasks.filter { !judgesFixedCalorieTarget($0) }
    }
}
