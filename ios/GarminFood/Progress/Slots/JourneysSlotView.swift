// JourneysSlotView.swift
//
// add-journeys-and-records design D9: the Progress-tab card for the four
// real-world journeys (protein climb, Vodník, road trip, food passport) --
// one compact row each: icon, "Sněžka → Gerlachovský štít · 64 %" and a bar
// to the next milestone -- linking to `JourneysView`. Replaces the
// add-gamification-signals stub; the host (`ProgressSlotHost`) is untouched.
//
// Thin: progress comes from `JourneysFeature.journeys()` (Gamification,
// unit-tested) and is reloaded whenever the feature host publishes a new
// journeys summary. A journey whose data source is unavailable is hidden.
//
// Depends on: AppEnvironment, JourneysFeature, JourneyFormat, JourneysView.
// Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct JourneysSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var journeys: [JourneyProgress] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs (see SeasonalBannerSlot).
        VStack(spacing: 0) {
            if featureHost?.feature(JourneysFeature.self) != nil {
                NavigationLink {
                    JourneysView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[JourneysFeature.id]) {
            await reload()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "map.fill")
                    .foregroundStyle(Theme.accent)
                Text("Journeys")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)

            if journeys.isEmpty {
                Text("Your journeys start with your first log.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(journeys) { journey in
                    JourneyCompactRow(progress: journey)
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens journeys"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(JourneysFeature.self) else { return }
        journeys = await feature.journeys().filter(\.isAvailable)
    }
}

private struct JourneyCompactRow: View {
    let progress: JourneyProgress

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: progress.definition.symbol)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: progress.definition.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(verbatim: JourneyFormat.positionLine(progress))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: progress.fractionToNext)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
    }
}
