// HomeView.swift
//
// The app's root screen. Before this file, the root was the search list
// (FoodCatalogView) -- functional, but it put a search field where the
// product's thesis should be. The thesis, per the owner's brief, is two
// things: the streak, and today's calorie intake. So the screen opens on
// exactly those (TodayHeroView), keeps level and the active challenge as
// quiet secondary rows, surfaces the quick-pick shelf for the fastest
// possible log, and pushes the full catalog only when the user wants to
// search. The catalog itself is untouched -- it just stops being the front
// door.
//
// Data refresh: the hero's number comes from Garmin on every foreground
// (AppEnvironment.refreshOnForeground), consistent with garmin-sync's rule
// that Garmin, not local aggregation, is the source of truth for totals.

import SwiftUI
import FoodLogCore
import Gamification

@MainActor
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var quickPickItems: [QuickPickItem] = []
    @State private var logTarget: LogTarget?
    @State private var isShowingCatalog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                TodayHeroView(
                    summary: environment.todaySummary.summary,
                    isStale: environment.todaySummary.isStale,
                    streak: environment.gamificationEngine.streakStatus
                )

                ProgressRow(
                    level: environment.gamificationEngine.levelProgress,
                    challenge: environment.gamificationEngine.activeChallengeTemplate,
                    challengeProgress: environment.gamificationEngine.challengeProgress
                )

                if !quickPickItems.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: "Log again")
                            .padding(.horizontal, Theme.Spacing.md)
                        QuickPickShelf(items: quickPickItems) { item in
                            logTarget = .catalog(food: item.food, initialServing: item.serving)
                        }
                    }
                    .padding(.horizontal, -Theme.Spacing.md) // shelf manages its own insets
                }

                logButton

                AppSignatureView()
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCatalog = true
                } label: {
                    Label("Search foods", systemImage: "magnifyingglass")
                }
            }
        }
        .navigationDestination(isPresented: $isShowingCatalog) {
            FoodCatalogView()
        }
        .navigationDestination(item: $logTarget) { target in
            LogEntryConfirmView(target: target)
        }
        .overlay { MomentOverlay() }
        .task { await loadQuickPicks() }
        .refreshable {
            await environment.refreshOnForeground()
            await loadQuickPicks()
        }
    }

    private var logButton: some View {
        Button {
            isShowingCatalog = true
        } label: {
            Label("Log a food", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm + 2)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .padding(.top, Theme.Spacing.xs)
    }

    private func loadQuickPicks() async {
        let events = await environment.usageHistory.all()
        let cache = await environment.foodCache.all()
        quickPickItems = QuickPick.rank(events: events).prefix(6).compactMap { entry in
            guard let food = cache[entry.foodId],
                  let serving = food.servings.first(where: { $0.id == entry.servingId })
            else { return nil }
            return QuickPickItem(food: food, serving: serving, numberOfUnits: entry.numberOfUnits)
        }
    }
}

// MARK: - Level + challenge

/// Two quiet cards side by side. Both are deliberately smaller and lower-
/// contrast than the hero: they are context for the streak, not competitors
/// to it. Progress is a thin capsule, not a ring, for the same reason the
/// hero has no ring -- one visual grammar for "progress toward a goal"
/// across the whole screen.
private struct ProgressRow: View {
    let level: LevelCurve.Progress
    let challenge: ChallengeTemplate?
    let challengeProgress: ChallengeProgress?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            card(
                eyebrow: "Level \(level.level)",
                title: level.xpNeededForNextLevel > 0
                    ? "\(level.xpIntoCurrentLevel) / \(level.xpNeededForNextLevel) XP"
                    : "Max level",
                fraction: level.fractionToNextLevel,
                symbol: "sparkles",
                accessibility: "Level \(level.level), \(Int((level.fractionToNextLevel * 100).rounded())) percent to the next level"
            )

            if let challenge, let challengeProgress {
                card(
                    eyebrow: "Challenge",
                    title: challenge.title,
                    fraction: challengeProgress.fraction,
                    symbol: "target",
                    accessibility: "Challenge: \(challenge.title), \(challengeProgress.current) of \(challengeProgress.target)"
                )
            } else {
                card(
                    eyebrow: "Challenge",
                    title: "Log a food to get one",
                    fraction: 0,
                    symbol: "target",
                    accessibility: "No active challenge yet. Log a food to get one."
                )
            }
        }
    }

    private func card(eyebrow: String, title: String, fraction: Double, symbol: String, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }
}
