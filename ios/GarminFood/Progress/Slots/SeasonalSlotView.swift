// SeasonalSlotView.swift
//
// add-seasonal-events design D5: the Progress-tab card for the Czech
// seasonal events -- every event active today with its required-quest
// progress, otherwise the next event and when it starts -- linking to the
// full year view (`SeasonalEventsView`: timeline + limited-edition badge
// showcase). Replaces the add-gamification-signals stub; the host
// (`ProgressSlotHost`) is untouched.
//
// Thin: statuses come from `SeasonalEventsFeature` (Gamification,
// unit-tested) and are reloaded whenever the feature host publishes a new
// seasonal summary.
//
// Depends on: AppEnvironment, SeasonalEventsFeature, SeasonalEventsView.
// Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct SeasonalSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var active: [SeasonalEventStatus] = []
    @State private var next: SeasonalEventStatus?
    @State private var earnedCount = 0

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        Group {
            if featureHost?.feature(SeasonalEventsFeature.self) != nil {
                NavigationLink {
                    SeasonalEventsView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[SeasonalEventsFeature.id]) {
            await reload()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(Theme.accent)
                Text("Seasonal events")
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

            if active.isEmpty {
                if let next {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: next.symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: next.title)
                                .font(.headline)
                            Text("Starts \(seasonalDayText(next.start))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No seasonal event right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(active) { status in
                    ActiveEventLine(status: status)
                }
            }

            Text("Limited badges earned: \(earnedCount) of \(SeasonalEventCatalog.all.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(earnedCount > 0 ? Theme.success : Color.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens seasonal events")
    }

    private func reload() async {
        guard let feature = featureHost?.feature(SeasonalEventsFeature.self) else { return }
        active = await feature.activeEvents()
        next = await feature.nextEvent()
        let overview = await feature.yearOverview()
        earnedCount = overview.filter { !$0.completedYears.isEmpty }.count
    }

}

/// "8 November" in the device locale (shared with SeasonalEventsView).
func seasonalDayText(_ date: SeasonalDate) -> String {
    guard let value = date.date(in: .current) else { return date.dayKey }
    return value.formatted(.dateTime.day().month(.wide))
}

private struct ActiveEventLine: View {
    let status: SeasonalEventStatus

    private var required: [SeasonalQuestStatus] { status.requiredQuests }
    private var progress: Int { required.reduce(0) { $0 + $1.progress } }
    private var target: Int { required.reduce(0) { $0 + $1.target } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: status.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: status.title)
                        .font(.headline)
                    Text("Until \(seasonalDayText(status.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if status.isCompleted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success)
                        .accessibilityLabel(Text("Event complete!"))
                }
            }
            if target > 0 {
                ProgressView(value: Double(progress), total: Double(target))
                    .tint(Theme.accent)
            }
        }
    }
}
