// JourneysFeature.swift
//
// add-journeys-and-records: the "journeys" gamification feature (replaces
// the add-gamification-signals stub; the registry already creates it with
// `init(directory:)`). Cumulative totals the owner already logs are mapped
// onto real places -- protein climbs mountains, water fills ever bigger
// containers, active kcal drive a road trip from Praha, distinct foods fill
// a passport (see `JourneyCatalog` for the conversions).
//
// Per run (`update`): load `JourneysStore`, run the pure
// `JourneysEvaluator`, save, then return
//   - one 40 XP grant per milestone ever reached, keyed
//     `journeys.<journey>.<milestone>` (re-emitted every run; the
//     `RewardLedger` applies each key once, so a failed write heals itself).
//     NOTE: design D7 wrote `journey.<id>.<milestone>`; the host drops any
//     grant outside the feature's own `journeys.` namespace, so the key uses
//     the feature id;
//   - the badges of reached milestones (the host skips unlocked ones);
//   - at most ONE moment: on the first run a single summary of the 42-day
//     back-fill, afterwards one combined "milestone reached" moment;
//   - the hub-card summary (protein climb position).
//
// A store that exists but can't be read (before first unlock) skips the run
// entirely -- back-filling over it would re-award and re-announce.
//
// Depends on: JourneysEvaluator, JourneysStore, JourneyCatalog, XPAward.
// Depended on by: GamificationFeatureRegistry, the app's Journeys screens
// (via `journeys()`).

import Foundation
import FoodLogCore

public actor JourneysFeature: GamificationFeature {
    public static let id = "journeys"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { JourneyCatalog.badges }

    let directory: URL
    private let store: JourneysStore
    /// Per journey: whether its data source exists in the latest snapshot.
    private var availability: [JourneyKind: Bool] = [:]

    public init(directory: URL) {
        self.directory = directory
        self.store = JourneysStore(directory: directory)
    }

    /// The grant key of a milestone (inside this feature's namespace).
    public static func grantKey(_ kind: JourneyKind, _ milestoneId: String) -> String {
        "\(id).\(kind.rawValue).\(milestoneId)"
    }

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let loaded = await store.load()
        guard loaded.isReadable else { return .empty }

        let result = JourneysEvaluator.evaluate(state: loaded.state, snapshot: context.snapshot)
        let days = context.snapshot.orderedDays
        for kind in JourneyKind.allCases {
            availability[kind] = JourneysEvaluator.isAvailable(kind, days: days)
        }
        do {
            try await store.save(result.state)
        } catch {
            // Not saved: nothing is announced, so the next run (which
            // re-evaluates from the old state) announces it instead of twice.
            return FeatureUpdate(summary: summary(state: loaded.state))
        }

        var grants: [RewardGrant] = []
        var badgeIds: [String] = []
        for kind in JourneyKind.allCases {
            let reached = result.state.reachedMilestones(kind)
            for milestone in JourneyCatalog.definition(kind).milestones where reached.contains(milestone.id) {
                grants.append(RewardGrant(key: Self.grantKey(kind, milestone.id), kind: .xp(XPAward.journeyMilestone)))
                if let badgeId = milestone.badgeId {
                    badgeIds.append(badgeId)
                }
            }
        }

        var moments: [FeatureMoment] = []
        if let moment = Self.moment(for: result, availability: availability) {
            moments.append(moment)
        }
        return FeatureUpdate(
            grants: grants,
            unlockBadgeIds: badgeIds,
            moments: moments,
            summary: summary(state: result.state)
        )
    }

    /// Every journey's current progress, in catalog order. Hidden journeys
    /// (data source unavailable) are included with `isAvailable == false`.
    public func journeys() async -> [JourneyProgress] {
        let state = await store.load().state
        return JourneyKind.allCases.map { kind in
            JourneysEvaluator.progress(state: state, kind: kind, isAvailable: isAvailable(kind, state: state))
        }
    }

    private func isAvailable(_ kind: JourneyKind, state: JourneysState) -> Bool {
        if let known = availability[kind] { return known }
        // Before the first run in this process: show what already moved.
        return JourneyCatalog.definition(kind).requirement.isEmpty || state.total(kind) > 0
    }

    // MARK: - Moments and summary

    static func moment(for result: JourneysEvaluator.Result, availability: [JourneyKind: Bool]) -> FeatureMoment? {
        let reached = result.newlyReached
        let xp = reached.count * XPAward.journeyMilestone
        if result.wasFirstRun {
            // Design D1: one summary moment for the whole back-fill.
            let lines = JourneyKind.allCases.compactMap { kind -> String? in
                guard availability[kind] ?? true else { return nil }
                let total = result.state.total(kind)
                guard total > 0 else { return nil }
                let definition = JourneyCatalog.definition(kind)
                return "\(definition.name): \(JourneyFormat.amount(total, unit: definition.unit))"
            }
            guard !lines.isEmpty || !reached.isEmpty else { return nil }
            var message = lines.joined(separator: " · ")
            if !reached.isEmpty {
                let count = String(reached.count)
                let suffix = String(localized: "Milestones reached from your recent history: \(count)", bundle: .module, comment: "First-run journeys summary; the value is a number.")
                message = message.isEmpty ? suffix : message + "\n" + suffix
            }
            return FeatureMoment(
                featureId: JourneysFeature.id,
                title: String(localized: "Your journeys have begun", bundle: .module, comment: "Moment title: journeys computed for the first time from recent history."),
                message: message,
                symbol: "map.fill",
                style: .celebration,
                xpAwarded: xp
            )
        }
        guard let first = reached.first else { return nil }
        let items = reached.map { item -> String in
            let definition = JourneyCatalog.definition(item.kind)
            let position = JourneyFormat.milestoneAmount(item.milestone, in: definition)
            return "\(definition.name): \(item.milestone.name) (\(position))"
        }
        let title = reached.count == 1
            ? String(localized: "Milestone reached!", bundle: .module, comment: "Moment title: one journey milestone reached.")
            : String(localized: "Milestones reached!", bundle: .module, comment: "Moment title: several journey milestones reached at once.")
        return FeatureMoment(
            featureId: JourneysFeature.id,
            title: title,
            message: items.joined(separator: "\n"),
            symbol: JourneyCatalog.definition(first.kind).symbol,
            style: .celebration,
            xpAwarded: xp
        )
    }

    private func summary(state: JourneysState) -> FeatureSummary {
        let progress = JourneyKind.allCases.map { kind in
            JourneysEvaluator.progress(state: state, kind: kind, isAvailable: isAvailable(kind, state: state))
        }
        let lead = progress.first { $0.isAvailable } ?? progress[0]
        return FeatureSummary(
            title: String(localized: "Journeys", bundle: .module, comment: "Hub card title for the real-world journeys."),
            subtitle: JourneyFormat.positionLine(lead),
            fraction: lead.fractionToNext,
            symbol: lead.definition.symbol
        )
    }
}

/// Number formatting shared by the journeys' moments and the app's screens.
public enum JourneyFormat {
    /// "1,603 m", "150 L", "205 km", "25" (locale-aware grouping).
    public static func amount(_ value: Double, unit: JourneyUnit) -> String {
        let digits = value < 100 && unit != .stamps ? 1 : 0
        let number = value.formatted(.number.precision(.fractionLength(0...digits)))
        switch unit {
        case .metres: return "\(number) m"
        case .litres: return "\(number) L"
        case .kilometres: return "\(number) km"
        case .stamps: return number
        }
    }

    /// Where a milestone sits: the climb shows the height within its stage
    /// (stage 2 restarts at 0 m), the others the distance from the start.
    public static func milestoneAmount(_ milestone: JourneyMilestone, in definition: JourneyDefinition) -> String {
        let value = definition.kind == .protein ? milestone.stageValue : milestone.threshold
        return amount(value, unit: definition.unit)
    }

    /// "64 %" for 0.64; small endless shares keep two decimals ("0.14 %").
    public static func percent(fraction: Double) -> String {
        percent(value: fraction * 100)
    }

    public static func percent(value: Double) -> String {
        let digits = value < 1 ? 2 : 0
        return value.formatted(.number.precision(.fractionLength(0...digits))) + " %"
    }

    /// "Sněžka → Gerlachovský štít · 64 %", or the endless-goal share once
    /// every milestone is behind.
    public static func positionLine(_ progress: JourneyProgress) -> String {
        if let next = progress.next {
            let from = progress.lastReached?.name
                ?? String(localized: "Start", bundle: .module, comment: "Journey position before the first milestone.")
            return "\(from) → \(next.name) · \(percent(fraction: progress.fractionToNext))"
        }
        if let endless = progress.definition.endless, let share = progress.endlessPercent {
            return "\(endless.name) · \(percent(value: share))"
        }
        return progress.lastReached?.name ?? progress.definition.name
    }
}
