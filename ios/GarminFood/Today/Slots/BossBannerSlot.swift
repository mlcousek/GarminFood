// BossBannerSlot.swift
//
// add-weekly-boss-and-streak-freezes design D7: the Today-tab banner for
// this week's boss -- name, flavour line, HP bar (target - hits) and days
// left; tapping it opens `BossDetailView`. After the boss is beaten it
// stays as a small "defeated" banner for the rest of the week; before the
// feature's first run of the week (no boss yet) it renders nothing.
// Replaces the add-gamification-signals stub; `TodaySlotHost` is untouched.
//
// Thin: the boss comes from `WeeklyBossFeature.currentBoss()`
// (Gamification, unit-tested) and is reloaded whenever the feature host
// publishes a new boss summary (after every refresh / log confirm). Names
// and lines arrive already localized from the package, hence
// `Text(verbatim:)`.
//
// Depends on: AppEnvironment, FeatureHost, WeeklyBossFeature,
// BossDetailView (+ BossHPBar/BossOutcomeBadge), Theme.
// Depended on by: TodaySlotHost.

import SwiftUI
import Gamification

@MainActor
struct BossBannerSlot: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var boss: BossWeekStatus?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs, so the first load would never happen.
        VStack(spacing: 0) {
            if let boss {
                NavigationLink {
                    BossDetailView()
                } label: {
                    BossBannerCard(boss: boss)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[WeeklyBossFeature.id]) {
            await reload()
        }
    }

    private func reload() async {
        guard let feature = featureHost?.feature(WeeklyBossFeature.self) else {
            boss = nil
            return
        }
        boss = await feature.currentBoss()
    }
}

private struct BossBannerCard: View {
    let boss: BossWeekStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: boss.archetype.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week's boss")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(verbatim: boss.archetype.name)
                        .font(.headline)
                }
                Spacer(minLength: 0)
                if boss.outcome == .active {
                    Text("Days left: \(boss.daysLeft)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } else {
                    BossOutcomeBadge(outcome: boss.outcome)
                }
            }

            if boss.outcome == .active {
                Text(verbatim: boss.archetype.flavour)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                BossHPBar(status: boss)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the weekly boss"))
    }
}
