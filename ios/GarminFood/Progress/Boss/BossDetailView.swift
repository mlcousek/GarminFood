// BossDetailView.swift
//
// add-weekly-boss-and-streak-freezes design D7: the weekly-boss screen,
// reached from the Today banner (`BossBannerSlot`) and the Progress card
// (`BossSlotView`). It shows this week's boss with its HP bar, the
// "why this boss" line (the 28-day adherence that chose it), which days of
// the week landed a hit, what defeating it pays (XP + a streak freeze), the
// past 8 weeks' outcomes, and the bestiary (every archetype, the defeated
// ones lit).
//
// Thin: everything comes from `WeeklyBossFeature.currentBoss()` /
// `history()` / `bestiary()` (Gamification, unit-tested) and is reloaded
// whenever the feature host publishes a new boss summary; this screen never
// judges a day. Names, goals and lines arrive already localized from the
// package, hence `Text(verbatim:)` for them.
//
// Also holds `BossHPBar` and `BossOutcomeBadge`, shared with the banner and
// the Progress card.
//
// Depends on: AppEnvironment, FeatureHost, WeeklyBossFeature, BossFight,
// BingoFormat (week/weekday formatting), SectionHeader, Theme.
// Depended on by: BossBannerSlot, BossSlotView.

import SwiftUI
import FoodLogCore
import Gamification

@MainActor
struct BossDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var current: BossWeekStatus?
    @State private var history: [BossWeekStatus] = []
    @State private var bestiary: [BossBestiaryEntry] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    private let bestiaryColumns = [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if let current {
                    currentCard(current)
                    whyCard(current)
                    hitDaysCard(current)
                } else {
                    Text("This week's boss appears after your next log.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                }

                Text("Every Monday a boss is picked from your weakest habit of the last four weeks. Defeat it for \(XPAward.bossDefeatedBase)–\(BossFight.defeatXP(target: 7)) XP and a streak freeze. If it escapes, nothing is lost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: String(localized: "Past weeks"))
                        VStack(spacing: Theme.Spacing.sm) {
                            ForEach(history) { week in
                                historyRow(week)
                            }
                        }
                        .card()
                    }
                }

                if !bestiary.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: String(localized: "Bestiary"))
                        LazyVGrid(columns: bestiaryColumns, spacing: Theme.Spacing.sm) {
                            ForEach(bestiary) { entry in
                                bestiaryCell(entry)
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(Text("Weekly Boss"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: featureHost?.summaries[WeeklyBossFeature.id]) {
            await reload()
        }
    }

    // MARK: - Sections

    private func currentCard(_ boss: BossWeekStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: boss.archetype.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: boss.archetype.name)
                        .font(.title2.weight(.bold))
                    Text(verbatim: boss.archetype.flavour)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            BossHPBar(status: boss)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.md) { stats(boss) }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) { stats(boss) }
            }
            .font(.subheadline.monospacedDigit())
            .accessibilityElement(children: .combine)

            Text("\(boss.archetype.goal) on \(boss.target) of 7 days to defeat it.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            BossOutcomeBadge(outcome: boss.outcome)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func stats(_ boss: BossWeekStatus) -> some View {
        Text("Hits: \(boss.hits)/\(boss.target)")
        if boss.outcome == .active {
            Text("Days left: \(boss.daysLeft)")
        }
    }

    private func whyCard(_ boss: BossWeekStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: String(localized: "Why this boss"))
            Text(verbatim: boss.whyLine)
                .font(.subheadline.weight(.semibold))
            Text("Over the last four weeks this was your weakest habit, so the target is two days better than your recent average.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private func hitDaysCard(_ boss: BossWeekStatus) -> some View {
        let days = boss.week.dayKeys(calendar: .current)
        let hits = Set(boss.hitDays)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "This week"))
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(days, id: \.self) { day in
                    let isHit = hits.contains(day)
                    VStack(spacing: 2) {
                        Text(verbatim: BingoFormat.shortWeekday(day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: isHit ? "burst.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isHit ? Theme.accent : Theme.stroke)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: BingoFormat.weekday(day)))
                    .accessibilityValue(isHit ? Text("Hit") : Text("No hit"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func historyRow(_ week: BossWeekStatus) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: week.archetype.symbol)
                .foregroundStyle(week.outcome == .defeated ? Theme.accent : Color.secondary)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: week.archetype.name)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: BingoFormat.weekRange(week.week))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                BossOutcomeBadge(outcome: week.outcome)
                Text("Hits: \(week.hits)/\(week.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bestiaryCell(_ entry: BossBestiaryEntry) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: entry.archetype.symbol)
                .font(.title2)
                .foregroundStyle(entry.isDefeated ? Theme.accent : Theme.stroke)
            Text(verbatim: entry.archetype.name)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(entry.isDefeated ? Color.primary : Color.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(entry.isDefeated ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: entry.archetype.name))
        .accessibilityValue(entry.isDefeated ? Text("Defeated") : Text("Not defeated yet"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(WeeklyBossFeature.self) else { return }
        current = await feature.currentBoss()
        history = await feature.history(limit: 8)
        bestiary = await feature.bestiary()
    }
}

/// The boss's remaining HP (target - hits) as a shrinking bar. The change
/// animates only when Reduce Motion is off.
struct BossHPBar: View {
    let status: BossWeekStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 10

    private var remainingFraction: Double {
        status.target > 0 ? Double(status.remainingHP) / Double(status.target) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Theme.danger)
                        .frame(width: proxy.size.width * remainingFraction)
                }
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: remainingFraction)
            Text("HP \(status.remainingHP)/\(status.target)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Boss health"))
        .accessibilityValue(Text("\(status.remainingHP) of \(status.target)"))
    }
}

/// "Defeated" / "Escaped" / "In progress" as a small coloured label.
struct BossOutcomeBadge: View {
    let outcome: BossOutcome

    var body: some View {
        switch outcome {
        case .defeated:
            Label("Defeated", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
        case .escaped:
            Label("Escaped", systemImage: "figure.run")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        case .active:
            Label("In progress", systemImage: "hourglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}
