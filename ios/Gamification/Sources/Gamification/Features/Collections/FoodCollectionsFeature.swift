// FoodCollectionsFeature.swift
//
// add-food-collections: the "collections" gamification feature -- five food
// collections (FoodCollectionCatalog, 85 entries) filled by logging foods
// whose tags match. Replaces the empty stub registered by
// add-gamification-signals (design D7); `GamificationFeatureRegistry` still
// creates it with `init(directory:)`, so no shared file changes.
//
// Each run (FeatureHost, after every refresh/confirm; local reads only):
//   1. loads `CollectionsStore` -- an unreadable file (before first unlock)
//      skips the run entirely, so nothing is overwritten or re-announced;
//   2. `CollectionsEvaluator` discovers new entries from the 42-day
//      snapshot (the first run thereby back-fills the whole window);
//   3. grants `collections.found.<entryId>` (+5 XP) for EVERY discovered
//      entry, every run -- `RewardLedger` makes them idempotent, and a run
//      whose ledger write failed is retried for free -- and requests every
//      earned badge not yet unlocked;
//   4. emits at most ONE moment: the first run's back-fill summary ("found
//      so far: 17 of 85"), otherwise one combined moment for this run's new
//      discoveries -- a big back-fill or a multi-food day never floods the
//      overlay (design D4).
//
// The grant namespace is the feature id ("collections."), because
// FeatureHost drops grants outside `<featureId>.`; the design's sketch
// wrote `collection.found.<id>`.
//
// The UI reads `overview()`, computed from the store alone, so it works
// before this launch's first run.
//
// Depends on: GamificationFeature, FoodCollectionCatalog,
// CollectionsEvaluator, CollectionsStore, CollectionsBadges,
// XPAward+Features.
// Depended on by: GamificationFeatureRegistry, the app's
// CollectionsSlotView / CollectionsView.

import Foundation
import FoodLogCore

public actor FoodCollectionsFeature: GamificationFeature {
    public static let id = "collections"
    /// At most this many names are listed in a combined discovery moment.
    static let maxNamesInMoment = 4

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { CollectionsBadges.all() }

    let directory: URL
    let store: CollectionsStore

    public init(directory: URL) {
        self.directory = directory
        self.store = CollectionsStore(fileURL: directory.appendingPathComponent("collections.json"))
    }

    public static func discoveryGrantKey(entryId: String) -> String {
        "\(id).found.\(entryId)"
    }

    // MARK: - GamificationFeature

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        guard let state = await store.load() else { return .empty }
        let isFirstRun = state.backfilledAt == nil
        let result = CollectionsEvaluator.evaluate(snapshot: context.snapshot, state: state)
        var newState = result.state
        if isFirstRun {
            newState.backfilledAt = context.now
        }
        if newState != state {
            // A failed save costs at most a repeated moment next run: grants
            // are idempotent in RewardLedger and badges in AchievementStore.
            try? await store.save(newState)
        }

        var update = FeatureUpdate()
        let discovered = newState.discovered ?? [:]
        for entryId in discovered.keys.sorted() {
            update.grants.append(RewardGrant(
                key: Self.discoveryGrantKey(entryId: entryId),
                kind: .xp(XPAward.collectionDiscovery)
            ))
        }
        for badgeId in CollectionsEvaluator.earnedBadgeIds(state: newState)
        where !context.unlockedBadgeIds.contains(badgeId) && !update.unlockBadgeIds.contains(badgeId) {
            update.unlockBadgeIds.append(badgeId)
        }

        let overview = CollectionsEvaluator.overview(state: newState)
        if let moment = Self.moment(
            isFirstRun: isFirstRun,
            newlyDiscovered: result.newlyDiscovered,
            overview: overview
        ) {
            update.moments.append(moment)
        }
        update.summary = Self.summary(overview)
        return update
    }

    // MARK: - UI reads

    /// Every collection with its discoveries (empty while the store is
    /// unreadable).
    public func overview() async -> CollectionsOverview {
        guard let state = await store.load() else { return .empty }
        return CollectionsEvaluator.overview(state: state)
    }

    // MARK: - Helpers

    static func moment(
        isFirstRun: Bool,
        newlyDiscovered: [String],
        overview: CollectionsOverview
    ) -> FeatureMoment? {
        guard !newlyDiscovered.isEmpty else { return nil }
        let xp = newlyDiscovered.count * XPAward.collectionDiscovery
        if isFirstRun {
            return FeatureMoment(
                featureId: id,
                title: CollectionsL10n.string("moment.backfill.title"),
                message: CollectionsL10n.format("moment.backfill.message", overview.discoveredCount, overview.totalCount),
                symbol: "books.vertical.fill",
                style: .celebration,
                xpAwarded: xp
            )
        }
        let entries = newlyDiscovered.compactMap { FoodCollectionCatalog.entry(id: $0) }
        guard let first = entries.first else { return nil }
        if entries.count == 1 {
            let symbol = FoodCollectionCatalog.collection(id: first.collectionId)?.symbol ?? "sparkles"
            return FeatureMoment(
                featureId: id,
                title: CollectionsL10n.string("moment.single.title"),
                message: "\(first.emoji) \(first.name)",
                symbol: symbol,
                style: .celebration,
                xpAwarded: xp
            )
        }
        var names = entries.prefix(maxNamesInMoment).map(\.name)
        if entries.count > maxNamesInMoment {
            names.append("…")
        }
        return FeatureMoment(
            featureId: id,
            title: CollectionsL10n.format("moment.multi.title", entries.count),
            message: names.joined(separator: ", "),
            symbol: "sparkles",
            style: .celebration,
            xpAwarded: xp
        )
    }

    static func summary(_ overview: CollectionsOverview) -> FeatureSummary {
        FeatureSummary(
            title: CollectionsL10n.string("summary.title"),
            subtitle: CollectionsL10n.format("summary.subtitle", overview.discoveredCount, overview.totalCount),
            fraction: overview.fraction,
            symbol: "books.vertical.fill"
        )
    }
}
