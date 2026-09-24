// ChallengeRotationPolicy.swift
//
// Design D11: trim the challenge catalog by rotation WEIGHT, never by
// deletion. Before this, ~94 % of picks were number ladders ("log on 4
// days", "log on 5 days", ...). Now:
//   - the 13 hand-authored templates: weight 2;
//   - the 24 creative signal-based templates: weight 3;
//   - number ladders: two tiers per family on an explicit allowlist, weight 1
//     (a "medium" and a "hard" tier; 14 families -> 28 templates);
//   - every other ladder tier: weight 0 -- still in `ChallengeCatalog.all`
//     so an active one finishes normally and its history/badges keep working;
//   - any template whose `DataRequirement` is not met by at least one of the
//     last 14 days of signals: weight 0 for this pick (no water data -> no
//     Hydration Station).
// That makes creative templates ~57 % of picks, ladders ~22 %.
//
// "Complete every challenge" (`achv-all-challenges`) now counts only the
// templates with a static weight > 0 (`allChallengesProgress`), otherwise
// the trim would make it impossible.
//
// Depends on: ChallengeCatalog (ladder families, hand-authored ids),
// ChallengeKind.dataRequirement, DataRequirement, FoodLogCore (DaySignals).
// Depended on by: ChallengeRotation.pickNext, ChallengeStore, the app's
// GamificationEngine (achievement context).

import Foundation
import FoodLogCore

public struct ChallengeRotationPolicy: Sendable {
    public static let handAuthoredWeight = 2
    public static let signalWeight = 3
    public static let ladderWeight = 1
    /// How far back a template's data requirement is looked for.
    public static let requirementLookbackDays = 14

    /// The ladder tiers that stay in rotation (two per family).
    public static let ladderAllowlist: Set<String> = [
        "log-streak-10", "log-streak-21",
        "extend-streak-7", "extend-streak-14",
        "goal-days-protein-7", "goal-days-protein-12",
        "goal-any-streak-4", "goal-any-streak-7",
        "goal-calories-streak-3", "goal-calories-streak-5",
        "new-foods-4", "new-foods-8",
        "meal-breakfast-5", "meal-breakfast-9",
        "multi-meal-3-5", "multi-meal-4-3",
        "busy-days-2-7", "busy-days-4-5",
        "absent-snack-4", "absent-snack-7",
        "all-goals-3", "all-goals-7",
        "full-course-3", "full-course-7",
        "same-food-4", "same-food-7",
        "weekend-streak-2", "weekend-streak-3",
    ]

    private static let handAuthoredIds: Set<String> = ChallengeCatalog.handAuthoredIds
    private static let ladderIds: Set<String> = Set(ChallengeCatalog.ladderFamilies.values.flatMap { $0 })

    /// The last `requirementLookbackDays` days that had data.
    public let recentDays: [DaySignals]

    /// `recentDays` empty = no signal data known: templates with a data
    /// requirement are not offered.
    public init(recentDays: [DaySignals] = []) {
        self.recentDays = recentDays
    }

    public init(signals: SignalsSnapshot?) {
        if let signals {
            self.recentDays = signals.days(signals.recentDayKeys(Self.requirementLookbackDays))
        } else {
            self.recentDays = []
        }
    }

    /// The weight ignoring data availability.
    public static func staticWeight(for template: ChallengeTemplate) -> Int {
        if template.kind.isSignalBased { return signalWeight }
        if handAuthoredIds.contains(template.id) { return handAuthoredWeight }
        if ladderAllowlist.contains(template.id) { return ladderWeight }
        if ladderIds.contains(template.id) { return 0 }
        // Outside every known family (a future hand-authored template):
        // treat it as curated.
        return handAuthoredWeight
    }

    /// The weight for this pick: 0 when the template's data is missing.
    public func weight(for template: ChallengeTemplate) -> Int {
        let base = Self.staticWeight(for: template)
        guard base > 0 else { return 0 }
        return template.kind.dataRequirement.isSatisfied(byAnyOf: recentDays) ? base : 0
    }

    /// Ids of the templates in rotation under the static weights -- the
    /// denominator of "complete every challenge".
    public static func rotationTemplateIds(in catalog: [ChallengeTemplate] = ChallengeCatalog.all) -> Set<String> {
        Set(catalog.filter { staticWeight(for: $0) > 0 }.map(\.id))
    }

    /// For `AchievementContext`: completed rotation templates vs. all of
    /// them. Completed weight-0 templates stay in history but don't count.
    public static func allChallengesProgress(
        completedTemplateIds: Set<String>,
        catalog: [ChallengeTemplate] = ChallengeCatalog.all
    ) -> (completed: Int, total: Int) {
        let rotation = rotationTemplateIds(in: catalog)
        return (completedTemplateIds.intersection(rotation).count, rotation.count)
    }
}
