// SupplementProgressSection.swift
//
// add-supplements task 6.4 (design D9): the gamification part of the
// Supplements screen -- the supplement streak (and the longest one), the
// ten supplement badges as a strip of medallions (earned ones lit), the
// vitamin alphabet and the creatine journey, with a link to Achievements
// (where the badges have their own "Supplements" group).
//
// Thin: the streak is `GamificationEngine.supplementStreak` (shared freeze
// pool applied), badge unlocks are `unlockedAchievements`, and the
// collection/journey come from `SupplementsFeature.progress()` -- all
// computed and unit-tested in the Gamification package. Reloads whenever
// a gamification pass completes (`FeatureHost.completedRuns`), e.g. right
// after a tick. Names from the package arrive localized (`Text(verbatim:)`).
//
// Depends on: AppEnvironment (GamificationEngine, FeatureHost),
// Gamification (SupplementsFeature, SupplementsCatalog, SupplementStreak),
// FoodLogCore (EvidenceCatalog names), BadgeMedallion, Theme.
// Depended on by: SupplementsView.

import SwiftUI
import FoodLogCore
import Gamification

@MainActor
struct SupplementProgressSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var progress: SupplementsProgress?

    private var engine: GamificationEngine { environment.gamificationEngine }

    var body: some View {
        let streak = engine.supplementStreak
        let unlocked = engine.unlockedAchievements
        Section {
            HStack {
                Label {
                    Text("Supplement streak")
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.length > 0 ? Theme.ember : Color.secondary)
                }
                Spacer()
                Text("\(streak.length) days")
                    .font(.headline.monospacedDigit())
            }
            .accessibilityElement(children: .combine)

            LabeledContent("Longest streak") {
                Text("\(max(progress?.longestStreak ?? 0, streak.longest)) days")
                    .monospacedDigit()
            }

            badgeStrip(unlocked: unlocked)

            if let progress {
                collection(progress)
                journey(progress)
            }

            NavigationLink {
                AchievementsView()
            } label: {
                Label("Achievements", systemImage: "rosette")
            }
        } header: {
            Text("Streak and badges")
        }
        .task(id: engine.featureHost?.completedRuns) {
            progress = await engine.featureHost?.feature(SupplementsFeature.self)?.progress()
        }
    }

    // MARK: - Badges

    private func badgeStrip(unlocked: [String: Date]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(SupplementsCatalog.badges) { badge in
                    let isEarned = unlocked[badge.id] != nil
                    VStack(spacing: Theme.Spacing.xs) {
                        BadgeMedallion(symbol: badge.badgeSymbol, rarity: badge.rarity, isLocked: !isEarned, size: 44)
                        Text(verbatim: badge.title)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isEarned ? .primary : .secondary)
                            .lineLimit(2)
                    }
                    .frame(width: 72)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isEarned
                        ? Text("\(badge.title), earned", comment: "VoiceOver: a supplement badge already earned. The value is the badge name.")
                        : Text("\(badge.title), not earned yet. \(badge.subtitle)", comment: "VoiceOver: a supplement badge not earned yet. First value is the badge name, second how to earn it."))
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
    }

    // MARK: - Vitamin alphabet

    private func collection(_ progress: SupplementsProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(verbatim: SupplementsCatalog.collectionName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: "\(progress.collectedCount)/\(progress.collection.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.xs)], alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(progress.collection) { entry in
                    Text(verbatim: EvidenceCatalog.name(of: entry.ingredient))
                        .font(.caption.weight(entry.isCollected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(entry.isCollected ? Theme.accentDeep : Color.secondary)
                        .background(entry.isCollected ? Theme.accent.opacity(0.15) : Theme.stroke.opacity(0.3), in: Capsule())
                        .accessibilityLabel(entry.isCollected
                            ? Text("\(EvidenceCatalog.name(of: entry.ingredient)), collected", comment: "VoiceOver: a vitamin or mineral already in the vitamin alphabet collection.")
                            : Text("\(EvidenceCatalog.name(of: entry.ingredient)), not yet", comment: "VoiceOver: a vitamin or mineral not yet in the vitamin alphabet collection."))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Creatine journey

    private func journey(_ progress: SupplementsProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(verbatim: SupplementsCatalog.journeyName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Total: \(SupplementsCatalog.gramsText(progress.creatineGrams))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fractionToNext)
                .tint(Theme.accent)
            if let next = progress.nextMilestone {
                Text("Next: \(SupplementsCatalog.gramsText(next.grams))", comment: "Creatine journey: the next milestone. The value is an amount like '500 g' or '1 kg'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Every milestone reached", comment: "Creatine journey: all milestones are behind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, Theme.Spacing.xs)
    }
}
