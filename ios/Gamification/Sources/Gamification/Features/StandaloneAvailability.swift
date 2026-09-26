// StandaloneAvailability.swift
//
// What gamification a standalone install (no Garmin account, so no
// activities and no active kcal) is shown and offered (add-standalone-mode
// D11, task 7.1; data-mode spec "Garmin-only gamification is unavailable,
// not locked").
//
// Offering: challenge rotation, bingo cards, bosses and journeys already
// skip anything whose `DataRequirement` no recent day satisfies. The app
// builds a standalone snapshot with every activity source removed
// (FoodLogCore's `SignalsInput.standalone`), so `.activities` is never
// satisfied there and none of those is ever offered -- this file doesn't
// duplicate that rule.
//
// Showing: achievements that can ONLY be earned from Garmin activity data
// are hidden in standalone mode instead of sitting "locked" forever --
// every `sport.*` badge (fuelled/recovered/earned/race-day tiers, double
// day, gel guru, long haul, carb loader), the dawn-patrol secret, and the
// road-trip journey's milestones (active kcal -> km). One already earned
// (e.g. before switching from Garmin mode) stays visible: it was earned.
// `body.*` (weight, fasting) and everything food-, water- and note-based
// stay.
//
// "Complete every challenge" counts only templates a standalone install
// can be offered (`ChallengeRotationPolicy.allChallengesProgress(...,
// excluding: .activities)`), otherwise it could never be completed.
//
// Depended on by: the app's FeatureHost/GamificationEngine (visible badge
// catalog, all-challenges progress). Tests: StandaloneAvailabilityTests.

import Foundation
import FoodLogCore

public enum StandaloneAvailability {
    /// Data a standalone install never has.
    public static let unavailableData: DataRequirement = .activities

    /// Badge ids that only Garmin activity data can unlock.
    public static let garminOnlyBadgeIds: Set<String> = {
        var ids = Set<String>()
        for tiers in [SportBodyCatalog.fuelTiers, SportBodyCatalog.recoveryTiers, SportBodyCatalog.earnedTiers, SportBodyCatalog.raceDayTiers] {
            ids.formUnion(tiers.map(\.id))
        }
        ids.formUnion([SportBodyCatalog.doubleDayId, SportBodyCatalog.gelGuruId, SportBodyCatalog.longHaulId, SportBodyCatalog.carbLoaderId])
        ids.insert(SecretAchievementId.dawnPatrol.badgeId)
        ids.formUnion(JourneyCatalog.definition(.road).milestones.compactMap(\.badgeId))
        return ids
    }()

    public static func isGarminOnly(_ badgeId: String) -> Bool {
        garminOnlyBadgeIds.contains(badgeId)
    }

    /// The badges to list: everything in Garmin mode; in standalone mode
    /// everything except Garmin-only badges not yet unlocked.
    public static func visibleBadges(
        _ catalog: [AchievementDefinition],
        isStandalone: Bool,
        unlockedIds: Set<String>
    ) -> [AchievementDefinition] {
        guard isStandalone else { return catalog }
        return catalog.filter { !isGarminOnly($0.id) || unlockedIds.contains($0.id) }
    }
}

extension ChallengeRotationPolicy {
    /// `allChallengesProgress` over the templates that can still be
    /// offered when `excluding` data is never available (standalone mode:
    /// `.activities`). `excluding == []` is exactly the original.
    public static func allChallengesProgress(
        completedTemplateIds: Set<String>,
        excluding: DataRequirement,
        catalog: [ChallengeTemplate] = ChallengeCatalog.all
    ) -> (completed: Int, total: Int) {
        let offerable = catalog.filter { $0.kind.dataRequirement.intersection(excluding).isEmpty }
        return allChallengesProgress(completedTemplateIds: completedTemplateIds, catalog: offerable)
    }
}
