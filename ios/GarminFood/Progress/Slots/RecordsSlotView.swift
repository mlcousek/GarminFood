// RecordsSlotView.swift
//
// add-journeys-and-records design D9: the Progress-tab card for the
// personal records -- the newest PR (or how many records are tracked) and
// up to three record values -- linking to the Garmin-style `RecordsView`
// list. Replaces the add-gamification-signals stub; the host
// (`ProgressSlotHost`) is untouched.
//
// Thin: values come from `PersonalRecordsFeature.records()` (Gamification,
// unit-tested) and are reloaded whenever the feature host publishes a new
// records summary. A record without data is hidden, never shown as zero.
//
// Depends on: AppEnvironment, PersonalRecordsFeature, RecordsView.
// Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct RecordsSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var records: [PersonalRecordStatus] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }
    private var summary: FeatureSummary? { featureHost?.summaries[PersonalRecordsFeature.id] }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs (see SeasonalBannerSlot).
        VStack(spacing: 0) {
            if featureHost?.feature(PersonalRecordsFeature.self) != nil {
                NavigationLink {
                    RecordsView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: summary) {
            await reload()
        }
    }

    /// Recent PRs first, then catalog order; at most three.
    private var highlighted: [PersonalRecordStatus] {
        let visible = records.filter(\.isVisible)
        return Array((visible.filter(\.isRecentPR) + visible.filter { !$0.isRecentPR }).prefix(3))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.accent)
                Text("Personal records")
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

            if let summary {
                Text(verbatim: summary.subtitle)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if highlighted.isEmpty {
                Text("No records yet. Keep logging and they will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(highlighted) { record in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: record.definition.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(verbatim: record.definition.name)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: Theme.Spacing.xs)
                        Text(verbatim: record.valueText ?? "")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        if record.isRecentPR {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                                .accessibilityLabel(Text("Recent PR"))
                        }
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens personal records"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(PersonalRecordsFeature.self) else { return }
        records = await feature.records()
    }
}
