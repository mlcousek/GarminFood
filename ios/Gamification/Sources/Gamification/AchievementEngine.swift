import Foundation

// AchievementEngine.swift
//
// achievements spec's evaluation + permanence rules: a pure function of
// (catalog, context, already-unlocked ids) -> newly-unlocked definitions.
// Two-pass so meta/completionist achievements (design.md D5) see the
// CURRENT evaluation's own unlocks in their denominator, without any
// self-referential ordering bug (a meta achievement can never unlock
// itself into its own count, since `isMeta` definitions are excluded from
// the denominator entirely).
public enum AchievementEngine {
    public static func evaluate(
        context: AchievementContext,
        catalog: [AchievementDefinition] = AchievementCatalog.all,
        alreadyUnlocked: Set<String>
    ) -> [AchievementDefinition] {
        let nonMeta = catalog.filter { !$0.isMeta }
        let metaDefinitions = catalog.filter { $0.isMeta }

        var newlyUnlocked: [AchievementDefinition] = []
        for definition in nonMeta where !alreadyUnlocked.contains(definition.id) {
            if isMet(definition.condition, context: context) {
                newlyUnlocked.append(definition)
            }
        }

        guard !nonMeta.isEmpty else { return newlyUnlocked }
        let unlockedAfterFirstPass = alreadyUnlocked.union(newlyUnlocked.map(\.id)).intersection(nonMeta.map(\.id))
        let fractionUnlocked = Double(unlockedAfterFirstPass.count) / Double(nonMeta.count)
        for definition in metaDefinitions where !alreadyUnlocked.contains(definition.id) {
            guard case .unlockedFractionOfOthers(let fraction) = definition.condition else { continue }
            if fractionUnlocked >= fraction {
                newlyUnlocked.append(definition)
            }
        }

        return newlyUnlocked
    }

    private static func isMet(_ condition: AchievementCondition, context: AchievementContext) -> Bool {
        switch condition {
        case .streakAtLeast(let days):
            return context.longestStreak >= days
        case .levelAtLeast(let level):
            return context.level >= level
        case .totalLogsAtLeast(let count):
            return context.totalLogsEver >= count
        case .distinctFoodsAtLeast(let count):
            return context.distinctFoodsInRetainedHistory >= count
        case .challengesCompletedAtLeast(let count):
            return context.challengeCompletionCount >= count
        case .allChallengesCompleted:
            return context.totalChallengeCatalogCount > 0 && context.distinctCompletedChallengeTemplateCount >= context.totalChallengeCatalogCount
        case .dailyChallengesCompletedAtLeast(let count):
            return context.dailyChallengeCompletionCount >= count
        case .goalHitDaysAtLeast(let macro, let count):
            return (context.goalHitDaysEver[macro.rawValue] ?? 0) >= count
        case .singleDayCaloriesAtLeast(let calories):
            return context.maxSingleDayCalories >= calories
        case .totalCaloriesAtLeast(let calories):
            return context.totalCaloriesEver >= calories
        case .perfectCalendarMonth:
            return context.hasPerfectCalendarMonth
        case .loggedOnLeapDay:
            return context.hasLoggedOnLeapDay
        case .loggedOnNewYearsDay:
            return context.hasLoggedOnNewYearsDay
        case .loggedAtMidnight:
            return context.hasLoggedAtMidnight
        case .anniversaryYears(let years):
            return context.yearsSinceFirstLog >= years
        case .unlockedFractionOfOthers:
            // Only ever evaluated by the meta pass above, never here.
            return false
        }
    }
}
