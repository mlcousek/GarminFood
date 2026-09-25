// BossSlotView.swift
//
// add-weekly-boss-and-streak-freezes design D7: the Progress-tab card for
// this week's boss -- symbol, name, HP bar, hits out of the target and
// days left -- linking to `BossDetailView` (why this boss, hit days,
// history, bestiary). Replaces the add-gamification-signals stub; the host
// (`ProgressSlotHost`) is untouched.
//
// Thin: the boss comes from `WeeklyBossFeature.currentBoss()`
// (Gamification, unit-tested) and is reloaded whenever the feature host
// publishes a new boss summary. Before the feature's first run this week
// the card shows a short "appears after your next log" line instead.
//
// Depends on: AppEnvironment, FeatureHost, WeeklyBossFeature,
// BossDetailView (+ its BossHPBar/BossOutcomeBadge), Theme.
// Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct BossSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var boss: BossWeekStatus?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs (see SeasonalBannerSlot).
        VStack(spacing: 0) {
            if featureHost?.feature(WeeklyBossFeature.self) != nil {
                NavigationLink {
                    BossDetailView()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[WeeklyBossFeature.id]) {
            await reload()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Weekly Boss")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if let boss {
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Image(systemName: boss.archetype.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: boss.archetype.name)
                            .font(.headline)
                        Text(verbatim: boss.archetype.goal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if boss.outcome == .active {
                        Text("Days left: \(boss.daysLeft)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        BossOutcomeBadge(outcome: boss.outcome)
                    }
                }
                BossHPBar(status: boss)
            } else {
                Text("This week's boss appears after your next log.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the weekly boss"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(WeeklyBossFeature.self) else { return }
        boss = await feature.currentBoss()
    }
}
