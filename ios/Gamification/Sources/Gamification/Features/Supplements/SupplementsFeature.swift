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
// Pauses (D10): `prepare` runs on every freshly built digest (before the
// shared freeze planner) and turns the days the feature was off or empty
// into neutral days, so the supplement streak is frozen in place.
//
// 6.3 (per run, while active): `SupplementsEvaluator` -> the badges that
// qualify (the host skips unlocked ones and scales their bonus), the
// vitamin-alphabet collection, the creatine journey (one scaled grant per
// milestone, `supplements.journey.<id>`, re-emitted like the day grants;
// one moment for the milestones reached this run), the state saved only
// when it changed, and the hub summary. Challenges are core templates
// (ChallengeTemplates+Supplements.swift) gated by ChallengeRotationPolicy.
//
// Depends on: FoodLogCore (SupplementSignals, PastDayLogging,
// SupplementDate), XPBudget, XPAward+Features, SupplementsStore,
// SupplementPause, SupplementsEvaluator, SupplementsCatalog.
// Depended on by: GamificationFeatureRegistry, XPBudget (its line), the
// app's FeatureHost / GamificationEngine / Supplements screen.

import Foundation
import FoodLogCore

public actor SupplementsFeature: GamificationFeature {
    public static let id = "supplements"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { SupplementsCatalog.badges }

    let directory: URL
    private let store: SupplementsStore
    /// What the last active run computed, for the Supplements screen.
    private var lastProgress: SupplementsProgress?

    public init(directory: URL) {
        self.directory = directory
        self.store = SupplementsStore(directory: directory)
    }

    // MARK: - Pauses (D10)

    /// Called by the host on every freshly built digest, BEFORE the shared
    /// freeze planner: records when the feature went inactive / active
    /// again (`SupplementPause`) and returns the digest with paused days
    /// read as neutral. `nil` when the state file can't be read or written
    /// -- the host then leaves supplements out of this run rather than
    /// reading a pause as missed days.
    public func prepare(_ raw: SupplementSignals) async -> SupplementSignals? {
        let loaded = await store.load()
        guard loaded.isReadable else { return nil }
        var state = loaded.state
        if SupplementPause.record(isActive: raw.isActive, today: raw.today, state: &state) {
            do {
                try await store.save(state)
            } catch {
                return nil
            }
        }
        return SupplementPause.apply(state, to: raw)
    }

    // MARK: - Keys and XP

    /// The one grant of a stack-complete day.
    public static func stackGrantKey(_ day: String) -> String {
        "\(id).stack.\(day)"
    }

    /// A creatine-journey milestone's grant.
    public static func journeyGrantKey(_ milestone: SupplementJourneyMilestone) -> String {
        "\(id).journey.\(milestone.id)"
    }

    /// `base` XP scaled for this optional source (never below 1 XP).
    public static func grantXP(_ base: Int) -> Int {
        XPBudget.optionalGrantXP(base, enabledOptionalSources: [id])
    }

    // MARK: - Run

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        guard let signals = context.supplements, signals.isActive else { return .empty }
        let loaded = await store.load()
        guard loaded.isReadable else { return .empty }

        let result = SupplementsEvaluator.evaluate(state: loaded.state, signals: signals)
        if result.state != loaded.state {
            do {
                try await store.save(result.state)
            } catch {
                // Not saved: announce nothing new, so the next run (from the
                // old state) announces it once instead of twice. The day
                // grants are keyed, so paying them now is still safe.
                return FeatureUpdate(grants: Self.stackGrants(signals), summary: Self.summary(result.progress))
            }
        }
        lastProgress = result.progress

        let milestoneXP = Self.grantXP(XPAward.journeyMilestone)
        let reached = SupplementsCatalog.journey.filter { (result.state.reachedMilestones ?? []).contains($0.id) }
        let grants = Self.stackGrants(signals)
            + reached.map { RewardGrant(key: Self.journeyGrantKey($0), kind: .xp(milestoneXP)) }
        var moments: [FeatureMoment] = []
        if let moment = Self.journeyMoment(result.newlyReached, xp: milestoneXP) {
            moments.append(moment)
        }
        return FeatureUpdate(
            grants: grants,
            unlockBadgeIds: result.badgeIds,
            moments: moments,
            summary: Self.summary(result.progress)
        )
    }

    /// What the last active run computed (`nil` before one ran in this
    /// process, or while the feature is off).
    public func progress() -> SupplementsProgress? {
        lastProgress
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

    // MARK: - Moments and summary

    /// One moment for every creatine-journey milestone reached this run.
    static func journeyMoment(_ reached: [SupplementJourneyMilestone], xp: Int) -> FeatureMoment? {
        guard let last = reached.last else { return nil }
        let amount = SupplementsCatalog.gramsText(last.grams)
        return FeatureMoment(
            featureId: id,
            title: String(localized: "Creatine milestone!", bundle: .module, comment: "Moment title: a creatine-journey milestone (cumulative grams) was reached."),
            message: String(localized: "\(amount) of creatine taken so far.", bundle: .module, comment: "Moment message: the cumulative creatine amount just reached. The value is an amount with its unit, e.g. '500 g' or '1 kg'."),
            symbol: "bolt.fill",
            style: .celebration,
            xpAwarded: xp * reached.count
        )
    }

    static func summary(_ progress: SupplementsProgress) -> FeatureSummary {
        let length = progress.streak.length
        return FeatureSummary(
            title: String(localized: "Supplements", bundle: .module, comment: "Hub card title of the supplements feature."),
            subtitle: String(localized: "Supplement streak: \(length)", bundle: .module, comment: "Supplements hub card: the current supplement streak. The value is a number of days."),
            fraction: nil,
            symbol: "pills.fill"
        )
    }
}
