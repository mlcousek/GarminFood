// CollectionsView.swift
//
// add-food-collections design D5: the food album behind the Progress slot --
// one section per collection ("Czech Classics 6/24") with a grid of tiles.
// A discovered tile shows the emoji, the name, the date and the food that
// found it; an undiscovered tile shows a greyed silhouette, "???" and its
// riddle hint -- never the name (owner decision: riddles, not names). Tapping
// any tile opens a detail sheet with the hint (or the discovery) large.
// VoiceOver reads an undiscovered tile as "Undiscovered, hint: …".
//
// Thin: the overview comes from `FoodCollectionsFeature.overview()`
// (Gamification, unit-tested) and reloads whenever the feature host
// publishes a new collections summary. Every string is already localized
// by the package (`CollectionsText`, entry/collection names), hence
// `Text(verbatim:)`. Theme tokens only (dark mode + themes), system text
// styles only (Dynamic Type).
//
// Depends on: AppEnvironment, FeatureHost, FoodCollectionsFeature,
// FoodCollectionCatalog types, CollectionsText, SectionHeader, card().
// Depended on by: CollectionsSlotView.

import SwiftUI
import Gamification

@MainActor
struct CollectionsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var overview: CollectionsOverview = .empty
    @State private var selected: CollectionTileSelection?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                header
                ForEach(overview.collections) { progress in
                    CollectionSection(progress: progress) { entry in
                        selected = CollectionTileSelection(entry: entry, discovery: progress.discovery(for: entry))
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(Text(verbatim: CollectionsText.title))
        .task(id: featureHost?.summaries[FoodCollectionsFeature.id]) {
            await reload()
        }
        .sheet(item: $selected) { selection in
            CollectionEntryDetail(selection: selection)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(overview.discoveredCount)/\(overview.totalCount)")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: CollectionsText.a11yCollection(
                title: CollectionsText.title,
                found: overview.discoveredCount,
                total: overview.totalCount
            )))
            ProgressView(value: overview.fraction)
                .tint(Theme.accent)
                .accessibilityHidden(true)
            Text(verbatim: CollectionsText.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.md) {
                Label {
                    Text(verbatim: CollectionsText.brandsExplored(overview.brandsExplored))
                } icon: {
                    Image(systemName: "cart.fill")
                }
                Label {
                    Text(verbatim: CollectionsText.rainbowDays(overview.rainbowDays))
                } icon: {
                    Image(systemName: "rainbow")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .card()
    }

    private func reload() async {
        guard let feature = featureHost?.feature(FoodCollectionsFeature.self) else { return }
        overview = await feature.overview()
    }
}

/// The tile the detail sheet shows.
struct CollectionTileSelection: Identifiable {
    let entry: FoodCollectionEntry
    let discovery: CollectionDiscovery?

    var id: String { entry.id }
}

/// "12 September 2026" for a `yyyy-MM-dd` discovery day.
func collectionDayText(_ dayKey: String?) -> String? {
    guard let dayKey else { return nil }
    let parts = dayKey.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3,
          let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    else { return dayKey }
    return date.formatted(.dateTime.day().month(.wide).year())
}

private struct CollectionSection: View {
    let progress: FoodCollectionProgress
    let onSelect: (FoodCollectionEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: progress.collection.title,
                trailing: "\(progress.discoveredCount)/\(progress.totalCount)"
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: CollectionsText.a11yCollection(
                title: progress.collection.title,
                found: progress.discoveredCount,
                total: progress.totalCount
            )))
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(verbatim: progress.collection.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.Spacing.sm)],
                    spacing: Theme.Spacing.sm
                ) {
                    ForEach(progress.collection.entries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            CollectionTile(entry: entry, discovery: progress.discovery(for: entry))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .card()
        }
    }
}

private struct CollectionTile: View {
    let entry: FoodCollectionEntry
    let discovery: CollectionDiscovery?

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if discovery != nil {
                Text(verbatim: entry.emoji)
                    .font(.largeTitle)
                Text(verbatim: entry.name)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let day = collectionDayText(discovery?.day) {
                    Text(verbatim: day)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                CollectionSilhouette(size: 34)
                Text(verbatim: "???")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: entry.hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.groupedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(discovery != nil ? Theme.accent.opacity(0.35) : Theme.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: discovery != nil
            ? CollectionsText.a11yDiscovered(name: entry.name)
            : CollectionsText.a11yUndiscovered(hint: entry.hint)))
    }
}

/// A greyed plate with a question mark: an undiscovered entry.
private struct CollectionSilhouette: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "circle.dashed")
                .font(.system(size: size))
                .foregroundStyle(.tertiary)
            Image(systemName: "questionmark")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

private struct CollectionEntryDetail: View {
    let selection: CollectionTileSelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if let discovery = selection.discovery {
                        Text(verbatim: selection.entry.emoji)
                            .font(.system(size: 72))
                            .accessibilityHidden(true)
                        Text(verbatim: selection.entry.name)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        if let day = collectionDayText(discovery.day) {
                            Text(verbatim: CollectionsText.foundOn(day))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let food = discovery.foodName, !food.isEmpty {
                            Text(verbatim: CollectionsText.foundWith(food))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        CollectionSilhouette(size: 72)
                        Text(verbatim: CollectionsText.undiscovered)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(verbatim: CollectionsText.hint)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(verbatim: selection.entry.hint)
                            .font(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: CollectionsText.done)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
