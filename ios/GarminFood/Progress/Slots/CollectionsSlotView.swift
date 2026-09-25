// CollectionsSlotView.swift
//
// add-food-collections design D5: the Progress-tab card for the food
// collections -- "Collections 17/85" with one mini progress ring per
// collection -- linking to the album (`CollectionsView`). Replaces the
// add-gamification-signals stub; the host (`ProgressSlotHost`) is untouched.
//
// Thin: the overview comes from `FoodCollectionsFeature.overview()`
// (Gamification, unit-tested) and is reloaded whenever the feature host
// publishes a new collections summary. Every string is already localized
// by the package (`CollectionsText`, `FoodCollection.title`), hence
// `Text(verbatim:)`.
//
// Depends on: AppEnvironment, FeatureHost, FoodCollectionsFeature,
// CollectionsText, ProgressRing, CollectionsView.
// Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct CollectionsSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var overview: CollectionsOverview = .empty

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        Group {
            if featureHost?.feature(FoodCollectionsFeature.self) != nil {
                NavigationLink {
                    CollectionsView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[FoodCollectionsFeature.id]) {
            await reload()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(Theme.accent)
                Text(verbatim: CollectionsText.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Text(verbatim: "\(overview.discoveredCount)/\(overview.totalCount)")
                    .font(.headline.monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(overview.collections) { progress in
                    MiniCollectionRing(progress: progress)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityHint(Text(verbatim: CollectionsText.slotHint))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        let total = CollectionsText.a11yCollection(
            title: CollectionsText.title,
            found: overview.discoveredCount,
            total: overview.totalCount
        )
        let parts = overview.collections.map { progress in
            CollectionsText.a11yCollection(
                title: progress.collection.title,
                found: progress.discoveredCount,
                total: progress.totalCount
            )
        }
        return ([total] + parts).joined(separator: ". ")
    }

    private func reload() async {
        guard let feature = featureHost?.feature(FoodCollectionsFeature.self) else { return }
        overview = await feature.overview()
    }
}

/// One collection's ring with its symbol inside and "6/24" below.
private struct MiniCollectionRing: View {
    let progress: FoodCollectionProgress

    private var isComplete: Bool {
        progress.totalCount > 0 && progress.discoveredCount >= progress.totalCount
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ProgressRing(
                fraction: progress.fraction,
                lineWidth: 5,
                tint: isComplete ? Theme.success : Theme.accent
            ) {
                Image(systemName: progress.collection.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            Text(verbatim: "\(progress.discoveredCount)/\(progress.totalCount)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
