// SportBodySlotView.swift
//
// add-sport-and-body-achievements design D6: the Progress-tab card for the
// sport & body badges -- this month's fuelled / recovered activities, the
// weight-goal milestone chips (✓ when unlocked, halfway with its percent)
// and the kept-fast streak -- linking to `SportBodyView`. Replaces the
// add-gamification-signals stub; the host (`ProgressSlotHost`) is
// untouched.
//
// Thin: every number comes from `SportAndBodyFeature` (Gamification,
// unit-tested) and is reloaded whenever the feature host publishes a new
// sport & body summary; unlock state is the engine's
// `unlockedAchievements`. Without any Garmin activity data (standalone mode,
// route broken) it says activities appear after a sync -- never "failed".
//
// Depends on: AppEnvironment, SportAndBodyFeature, SportBodyCatalog,
// BodyRules, SportBodyView. Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct SportBodySlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var month = SportMonthCounts(fuelled: 0, recovered: 0)
    @State private var progress: SportBodyProgress?
    @State private var activitiesAvailable = false

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }
    private var unlocked: [String: Date] { environment.gamificationEngine.unlockedAchievements }

    var body: some View {
        Group {
            if featureHost?.feature(SportAndBodyFeature.self) != nil {
                NavigationLink {
                    SportBodyView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[SportAndBodyFeature.id]) {
            await reload()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "figure.run")
                    .foregroundStyle(Theme.accent)
                Text("Sport & Body")
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

            if activitiesAvailable || month.fuelled > 0 || month.recovered > 0 {
                Text("This month: \(month.fuelled) fuelled · \(month.recovered) recovered")
                    .font(.headline)
            } else {
                Text("Activities appear here once Garmin has synced them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let weight = progress?.weight {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) { milestoneChips(weight) }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) { milestoneChips(weight) }
                }
            }

            if let streak = progress?.fastingStreak, streak > 0 {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.ember)
                        .accessibilityHidden(true)
                    Text("Fasting streak")
                        .font(.subheadline)
                    Text("\(streak) days")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens Sport & Body"))
    }

    @ViewBuilder
    private func milestoneChips(_ weight: WeightMilestoneProgress) -> some View {
        ForEach(BodyRules.applicableMilestoneIds(direction: weight.direction), id: \.self) { id in
            if let badge = SportBodyCatalog.badge(id: id) {
                MilestoneChip(
                    title: badge.title,
                    detail: detail(for: id, weight: weight),
                    isUnlocked: unlocked[id] != nil
                )
            }
        }
    }

    /// The halfway chip shows how far along the goal is until it unlocks.
    private func detail(for id: String, weight: WeightMilestoneProgress) -> String? {
        guard id == SportBodyCatalog.halfwayId, unlocked[id] == nil, let fraction = weight.fraction else { return nil }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(SportAndBodyFeature.self) else { return }
        month = await feature.monthCounts()
        progress = await feature.bodyProgress()
        activitiesAvailable = await feature.activitiesAvailable()
    }
}

/// A weight-milestone chip: a check once unlocked, else an open circle
/// (plus the halfway percent). Shared with SportBodyView.
struct MilestoneChip: View {
    let title: String
    let detail: String?
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isUnlocked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isUnlocked ? Theme.success : Color.secondary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(verbatim: detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Capsule().fill(Theme.groupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnlocked ? Text("Unlocked") : Text("Locked"))
    }
}
