// SupplementsFeature.swift
//
// add-supplements D9: the optional "supplements" gamification feature. It
// never touches the supplement stores itself: the app's FeatureHost builds
// FoodLogCore's `SupplementSignals` digest (plan + intake log, one pure
// pass) and hands it in through `FeatureContext.supplements`, after the
// shared freeze planner filled in `frozenDays`.
//
// While the digest is missing or not active (feature off, or no product
// in the stack -- `SupplementSignals.isActive`) `update` returns `.empty`:
// no grants, no badges, no moments. Badges already earned stay earned
// (AchievementStore keeps them), which is all "disabled" needs here.
//
// XP (rebalance-xp-economy D4, "few, larger grants"): supplements is an
// OPTIONAL source, so every grant is scaled with
// `XPBudget.optionalGrantXP(_:enabledOptionalSources:)` -- in practice
// 1 XP. At most ONE grant per stack-complete day (`supplements.stack.<day>`),
// never one per tick, and only for a day whose planned ticks were written
// within the 7-day grace (`SupplementDaySignal.grantsXP`, D14): history
// farming pays nothing. Grants are keyed by day and re-emitted for the
// grace window on every run; `RewardLedger` applies each key once, so
// re-entering a day never pays twice and a failed ledger write heals.
//
// Depends on: FoodLogCore (SupplementSignals, PastDayLogging,
// SupplementDate), XPBudget, XPAward+Features.
// Depended on by: GamificationFeatureRegistry, XPBudget (its line), the
// app's FeatureHost / GamificationEngine / Supplements screen.

import Foundation
import FoodLogCore

public actor SupplementsFeature: GamificationFeature {
    public static let id = "supplements"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { [] }

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Keys and XP

    /// The one grant of a stack-complete day.
    public static func stackGrantKey(_ day: String) -> String {
        "\(id).stack.\(day)"
    }

    /// `base` XP scaled for this optional source (never below 1 XP).
    public static func grantXP(_ base: Int) -> Int {
        XPBudget.optionalGrantXP(base, enabledOptionalSources: [id])
    }

    // MARK: - Run

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        guard let signals = context.supplements, signals.isActive else { return .empty }
        return FeatureUpdate(grants: Self.stackGrants(signals))
    }

    /// One grant per stack-complete day inside the XP grace window
    /// (today - 7 ... today) whose ticks were written on time.
    static func stackGrants(_ signals: SupplementSignals) -> [RewardGrant] {
        guard let earliest = SupplementDate.adding(-PastDayLogging.xpGraceDays, to: signals.today) else { return [] }
        let xp = grantXP(XPAward.supplementStackComplete)
        return signals.days
            .filter { $0.day >= earliest && $0.day <= signals.today && $0.status == .complete && $0.grantsXP }
            .map { RewardGrant(key: stackGrantKey($0.day), kind: .xp(xp)) }
    }
}
