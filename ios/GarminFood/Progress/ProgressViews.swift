// ProgressViews.swift
//
// The Progress tab (progress-screens spec): level and XP, streak history,
// challenges and goal history, each with its own detail screen. Everything
// shown is computed locally by the Gamification package; nothing here waits
// on the network.
//
// add-weekly-boss-and-streak-freezes D7: the streak card and screen show
// the streak-freeze bank ("n/2" chip, `FreezeChip`), a frozen day is its
// own `StreakDot` style (ice fill + snowflake, "Missed, streak frozen"),
// and "How streaks work" explains freezes. The freeze data comes from
// `GamificationEngine.freezeBalance` / `.streakSummary` (already frozen-
// aware); nothing here computes a freeze.
//
// add-themes-and-layout (design.md D8, wave 4): `ProgressHomeView`'s cards
// follow the user's layout (LayoutStore, `.progress`), with each
// gamification slot view as its own card instead of one ProgressSlotHost.

import SwiftUI
import Gamification
import FoodLogCore
import AppearanceKit

// MARK: - Progress home

@MainActor
struct ProgressHomeView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let engine = environment.gamificationEngine

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                // add-themes-and-layout (design.md D8, wave 4): the user's
                // order from LayoutStore, one arm per card. Each gamification
                // slot (add-gamification-signals D12) is its own entry, so
                // Bingo can be hidden while Boss stays; the slots still
                // decide their own content (an empty slot renders nothing).
                // With nothing stored the order is the former fixed stack
                // (LayoutResolverTests golden).
                ForEach(renderedCards, id: \.self) { card in
                    progressCard(card)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Progress")
        .refreshable {
            await engine.refresh()
            await environment.refreshGarminHealth()
        }
    }

    /// The cards the user left visible, in their order. There's no
    /// availability rule on Progress: every card (and each slot, which
    /// decides its own content) always has a place.
    private var renderedCards: [ProgressCardID] {
        environment.layoutStore.resolved(.progress).compactMap { placement in
            placement.isVisible ? ProgressCardID(rawValue: placement.id) : nil
        }
    }

    /// One Progress card (the arms are the former fixed stack's entries,
    /// unchanged; the slot views are referenced individually instead of
    /// through `ProgressSlotHost`).
    @ViewBuilder
    private func progressCard(_ card: ProgressCardID) -> some View {
        let engine = environment.gamificationEngine
        switch card {
        case .streak:
            NavigationLink {
                StreakDetailView()
            } label: {
                StreakSummaryCard(summary: engine.streakSummary, status: engine.streakStatus, freezes: engine.freezeBalance)
            }
            .buttonStyle(.plain)
        case .level:
            NavigationLink {
                LevelDetailView()
            } label: {
                LevelSummaryCard(progress: engine.levelProgress)
            }
            .buttonStyle(.plain)
        case .boss:
            BossSlotView()
        case .bingo:
            BingoSlotView()
        case .seasonal:
            SeasonalSlotView()
        case .journeys:
            JourneysSlotView()
        case .records:
            RecordsSlotView()
        case .collections:
            CollectionsSlotView()
        case .sportBody:
            SportBodySlotView()
        case .secrets:
            SecretsSlotView()
        case .challenges:
            NavigationLink {
                ChallengesView()
            } label: {
                ChallengeSummaryCard(
                    template: engine.activeChallengeTemplate,
                    progress: engine.challengeProgress,
                    windowEnd: engine.challengeWindowEnd,
                    completedCount: engine.completedChallenges.count
                )
            }
            .buttonStyle(.plain)
        case .achievements:
            NavigationLink {
                AchievementsView()
            } label: {
                AchievementsSummaryCard(unlockedCount: engine.unlockedAchievements.count, totalCount: engine.achievementCatalog.count)
            }
            .buttonStyle(.plain)
        case .weight:
            NavigationLink {
                WeightView()
            } label: {
                WeightSummaryCard(latest: environment.weightLoader.latest, previous: environment.weightLoader.previous)
            }
            .buttonStyle(.plain)
        case .hydration:
            NavigationLink {
                HydrationView()
            } label: {
                HydrationSummaryCard(todayTotalML: environment.hydrationLoader.todayTotalML)
            }
            .buttonStyle(.plain)
        case .trends:
            NavigationLink {
                TrendsView()
            } label: {
                TrendsSummaryCard(
                    hydrationStreak: HydrationHistory.streak(for: environment.hydrationLoader.entries, goalML: environment.hydrationLoader.goalML)
                )
            }
            .buttonStyle(.plain)
        case .goalHistory:
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Goals, last 14 days", comment: "Progress tab section header."))
                GoalHistoryList(statuses: Array(engine.goalHistory.prefix(14)))
                    .card()
            }
        }
    }
}

// MARK: - Summary cards

private struct CardHeader: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
            Text(title)
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
    }
}

private struct StreakSummaryCard: View {
    let summary: StreakHistory.Summary
    let status: StreakEngine.Status
    let freezes: FreezeBalance.Result

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Streak", systemImage: "flame.fill")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                // One plural string ("7 days" / "7 dní"), not a number plus a
                // `== 1 ?` unit word: the Czech noun has three forms.
                Text("\(summary.currentLength) days")
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                FreezeChip(available: freezes.available)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Best \(summary.longestLength)", comment: "Streak card: the longest streak ever, in days.")
                        .font(.subheadline.weight(.semibold))
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(status.isAtRiskToday ? Theme.ember : Color.secondary)
                }
            }
            StreakWeekStrip(days: Array(summary.days.suffix(7)))
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Streak \(summary.currentLength) days, best \(summary.longestLength)", comment: "VoiceOver: the streak card. Current streak, then the longest one, both in days."))
        .accessibilityValue(FreezeChip.accessibilityText(available: freezes.available))
        .accessibilityHint(Text("Opens streak history"))
    }

    private var statusText: LocalizedStringKey {
        if status.hasLoggedToday { return "Today counted" }
        return status.isAtRiskToday ? "Log today to keep it" : "Log today to start"
    }
}

private struct LevelSummaryCard: View {
    let progress: LevelCurve.Progress

    private var tier: LevelTier { LevelTiers.tier(forLevel: progress.level) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Level", systemImage: "sparkles")
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                BadgeMedallion(symbol: tier.badgeSymbol, rarity: tier.rarity, isLocked: false, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Level \(progress.level)")
                        .font(.system(.title, design: .rounded).weight(.bold))
                    Text(tier.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(progress.totalXP) XP", comment: "Total XP earned.")
                    .font(.macroValue)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fractionToNextLevel)
                .tint(Theme.accent)
            Text(progress.xpNeededForNextLevel > 0
                 ? String(localized: "\(progress.xpNeededForNextLevel - progress.xpIntoCurrentLevel) XP to level \(progress.level + 1)", comment: "Level card: XP still needed, then the next level number.")
                 : String(localized: "Max level reached"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level \(progress.level), \(tier.title), \(tier.rarity.displayName) tier, \(progress.totalXP) XP", comment: "VoiceOver: the level card. Level number, tier name, tier grade (an adjective, Czech: agrees with \"stupeň\"), total XP."))
        .accessibilityHint(Text("Opens level details"))
    }
}

private struct ChallengeSummaryCard: View {
    let template: ChallengeTemplate?
    let progress: ChallengeProgress?
    let windowEnd: Date?
    let completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Challenge", systemImage: "target")
            if let template, let progress {
                Text(template.title)
                    .font(.headline)
                Text(template.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress.fraction)
                    .tint(Theme.accent)
                HStack {
                    Text("\(progress.current) of \(progress.target)")
                    Spacer()
                    if let windowEnd {
                        Text(timeLeftText(until: windowEnd))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Log a food to get your first challenge.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if completedCount > 0 {
                Text("\(completedCount) completed so far", comment: "Challenge card: how many challenges were ever completed.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens challenges"))
    }
}

private struct AchievementsSummaryCard: View {
    let unlockedCount: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Achievements", systemImage: "rosette")
            HStack(alignment: .firstTextBaseline) {
                Text("\(unlockedCount)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("/ \(totalCount) unlocked", comment: "Achievements card, after the big unlocked count: the total number of badges.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0)
                .tint(Theme.accent)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(unlockedCount) of \(totalCount) achievements unlocked", comment: "VoiceOver: the achievements card."))
        .accessibilityHint(Text("Opens achievements"))
    }
}

/// Progress tab entry point into `WeightView` (add-weight-tracking) --
/// same "card summarises, tap opens the detail screen" shape as every other
/// card on this tab. Deliberately its own compact layout rather than
/// reusing `WeightHeroCard` (WeightComponents.swift) as-is: that view's own
/// "Current weight" caption would duplicate this card's `CardHeader` title.
private struct WeightSummaryCard: View {
    /// Rows of the merged Garmin + local history (sync-weight-hydration-
    /// with-garmin), so a scale weigh-in shows here too.
    let latest: WeighInDisplayEntry?
    let previous: WeighInDisplayEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Weight", systemImage: "scalemass.fill")
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(latest.weightKg.formattedKg)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    Text("kg")
                        .font(.streakLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let delta = WeightHistory.delta(latest: latest, previous: previous) {
                        WeightDeltaBadge(delta: delta)
                    }
                }
                Text("Logged \(latest.loggedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log your weight to start tracking it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens weight tracking"))
    }
}

/// Progress tab entry point into `HydrationView` (add-hydration-tracking) --
/// same "card summarises, tap opens the detail screen" shape as
/// `WeightSummaryCard` directly above. Shows only today's total (no delta
/// badge, unlike weight): hydration resets every day, so "since last
/// entry" isn't a meaningful comparison the way it is for a weigh-in.
private struct HydrationSummaryCard: View {
    let todayTotalML: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Water", systemImage: "drop.fill")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(todayTotalML.formattedML)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                Text("ml today", comment: "Water card: unit label after today's total.")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens hydration tracking"))
    }
}

/// Progress tab entry point into `TrendsView` (add-trends-and-insights) --
/// same "card summarizes, tap opens the detail screen" shape as
/// `WeightSummaryCard`/`HydrationSummaryCard` above. Shows the hydration
/// streak, not a macro-trend preview: it's the one number this card can
/// show for free -- purely local, already computed from
/// `environment.hydrationLoader.entries`, which the Progress tab already
/// keeps fresh. The macro trend itself needs `environment.trendsLoader`'s
/// own Garmin read, which -- per that loader's header -- only happens once
/// `TrendsView` is actually opened, so this card doesn't fetch it just to
/// preview it.
private struct TrendsSummaryCard: View {
    let hydrationStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Trends", systemImage: "chart.line.uptrend.xyaxis")
            // One plural string, same reason as the streak card.
            Text("\(hydrationStreak)-day water streak", comment: "Trends card: consecutive days the water goal was met. Plural.")
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
            Text("Macro and hydration history over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens trends and insights"))
    }
}

/// "3 days left" / "Last day" for a challenge's final nutrition day.
/// Localized via Resources/Localizable.xcstrings; "%lld days left" is a
/// plural-variation entry there (Czech: Zbývá 1 den / Zbývají 3 dny /
/// Zbývá 5 dní -- the verb agrees too), so there is deliberately no
/// `case 1` special-case any more (add-localization design.md D5).
func timeLeftText(until end: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    switch days {
    case ..<0: return String(localized: "Ended", comment: "Challenge status: its time window is over.")
    case 0: return String(localized: "Last day", comment: "Challenge status: today is the final day of its window.")
    default: return String(localized: "\(days) days left", comment: "Challenge status: whole days remaining (1 or more). Plural.")
    }
}

// MARK: - Streak

private struct StreakWeekStrip: View {
    let days: [StreakHistory.Day]

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    StreakDot(mark: day.mark, isToday: day.isToday)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct StreakDot: View {
    let mark: StreakHistory.Mark
    let isToday: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            if mark == .logged {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            } else if mark == .grace {
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            } else if mark == .frozen {
                Image(systemName: "snowflake")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if isToday {
                Circle().stroke(Theme.accent, lineWidth: 2)
                    .padding(-3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var fill: AnyShapeStyle {
        switch mark {
        case .logged: return AnyShapeStyle(Theme.flameGradient)
        case .grace: return AnyShapeStyle(Theme.grace)
        case .frozen: return AnyShapeStyle(Theme.water)
        case .missed: return AnyShapeStyle(Color.primary.opacity(0.12))
        case .pending: return AnyShapeStyle(Theme.ember.opacity(0.18))
        case .future, .beforeHistory: return AnyShapeStyle(Color.primary.opacity(0.04))
        }
    }

    private var label: String {
        switch mark {
        case .logged: return String(localized: "Logged", comment: "Streak day: something was logged.")
        case .grace: return String(localized: "Missed, forgiven", comment: "Streak day: missed, but forgiven by the grace rule.")
        case .frozen: return String(localized: "Missed, streak frozen")
        case .missed: return String(localized: "Missed")
        case .pending: return String(localized: "Today, nothing logged yet", comment: "Streak day: today, still open.")
        case .future: return String(localized: "Upcoming")
        case .beforeHistory: return String(localized: "Before your first log", comment: "Streak day: before the first entry ever.")
        }
    }
}

@MainActor
struct StreakDetailView: View {
    @Environment(AppEnvironment.self) private var environment

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 7)

    var body: some View {
        let summary = environment.gamificationEngine.streakSummary
        let status = environment.gamificationEngine.streakStatus
        let freezes = environment.gamificationEngine.freezeBalance

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.sm) {
                    StatTile(value: "\(summary.currentLength)", label: String(localized: "Current streak"), systemImage: "flame.fill", tint: Theme.ember)
                    StatTile(value: "\(summary.longestLength)", label: String(localized: "Longest streak"), systemImage: "trophy.fill")
                    StatTile(value: "\(summary.loggedDayCount)", label: String(localized: "Days logged"), systemImage: "calendar")
                }

                freezeBank(freezes)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Last 6 weeks", comment: "Streak screen: the calendar grid's header."))
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(summary.days) { day in
                            VStack(spacing: 2) {
                                StreakDot(mark: day.mark, isToday: day.isToday, size: 30)
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(day.mark == .future ? .tertiary : .secondary)
                            }
                        }
                    }
                    .card()
                    legend
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    SectionHeader(title: String(localized: "How streaks work"))
                    Text("Log at least one food on a day to count it. One missed day in any 7 is forgiven, shown with a shield. A second miss in the same 7 days starts the streak over.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("A streak freeze covers a second missed day that would otherwise end a streak of 3 days or more, and is used automatically. Earn one by defeating the weekly boss or completing a full bingo card; you can hold up to \(FreezeBalance.cap).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if status.isAtRiskToday {
                        Label(String(localized: "Log something today to keep your \(status.length)-day streak.", comment: "Streak screen warning; %lld = the streak length in days. Plural."), systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ember)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
                .card()
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Weekday initials starting from the calendar's first weekday, matching
    /// the grid's columns.
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            legendItem(.logged, "Logged")
            legendItem(.grace, "Forgiven")
            legendItem(.frozen, "Frozen")
            legendItem(.missed, "Missed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// The freeze bank: available / cap, and the spec's "bank was full"
    /// note when a grant arrived while two were already held.
    private func freezeBank(_ freezes: FreezeBalance.Result) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "snowflake")
                    .font(.title3)
                    .foregroundStyle(Theme.water)
                Text("Streak freezes")
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(freezes.available)/\(FreezeBalance.cap)")
                    .font(.macroValue.monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FreezeChip.accessibilityText(available: freezes.available))
            if freezes.used > 0 {
                Text("Used so far: \(freezes.used)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let day = freezes.lastWastedDay {
                Label(bankFullText(day), systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func bankFullText(_ dayKey: String) -> String {
        let date = FreezeDayKey.date(for: dayKey, calendar: .current)
        let day = date.map { $0.formatted(.dateTime.day().month(.wide)) } ?? dayKey
        return String(localized: "Bank full: the freeze earned on \(day) was not added (you can hold \(FreezeBalance.cap)).")
    }

    private func legendItem(_ mark: StreakHistory.Mark, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            StreakDot(mark: mark, isToday: false, size: 14)
            Text(title)
        }
    }
}

/// The streak-freeze bank ("snowflake 1/2") on the streak card.
struct FreezeChip: View {
    let available: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "snowflake")
            Text(verbatim: "\(available)/\(FreezeBalance.cap)")
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.water)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(Theme.water.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(available: available))
    }

    static func accessibilityText(available: Int) -> Text {
        Text("Streak freezes: \(available) of \(FreezeBalance.cap)")
    }
}

// MARK: - Level

@MainActor
struct LevelDetailView: View {
    @Environment(AppEnvironment.self) private var environment

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 160
    @ScaledMetric(relativeTo: .largeTitle) private var levelNumberSize: CGFloat = 48

    var body: some View {
        let progress = environment.gamificationEngine.levelProgress
        let tier = LevelTiers.tier(forLevel: progress.level)

        List {
            Section {
                VStack(spacing: Theme.Spacing.md) {
                    BadgeMedallion(symbol: tier.badgeSymbol, rarity: tier.rarity, isLocked: false, size: 64)
                        .accessibilityHidden(true)

                    ProgressRing(fraction: progress.fractionToNextLevel, lineWidth: 14) {
                        VStack(spacing: 0) {
                            Text("Level")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(progress.level)")
                                .font(.system(size: levelNumberSize, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(width: ringSize, height: ringSize)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Level \(progress.level), \(tier.title), \(tier.rarity.displayName) tier", comment: "VoiceOver: the level ring. Level number, tier name, tier grade (adjective; Czech agrees with \"stupeň\")."))
                    .accessibilityValue(Text("\(Int((progress.fractionToNextLevel * 100).rounded())) percent to the next level", comment: "VoiceOver: progress through the current level, in percent."))

                    VStack(spacing: 2) {
                        Text(tier.title)
                            .font(.headline)
                        Text(tier.flavor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(progress.totalXP) XP total", comment: "Level screen: all XP ever earned.")
                        .font(.headline)
                    if progress.xpNeededForNextLevel > 0 {
                        Text("\(progress.xpIntoCurrentLevel) of \(progress.xpNeededForNextLevel) XP into this level", comment: "Level screen: XP earned inside the current level, out of what it takes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
            }

            Section("Coming up") {
                ForEach(upcomingLevels(from: progress)) { upcoming in
                    HStack {
                        Label("Level \(upcoming.level)", systemImage: "lock.fill")
                        Spacer()
                        Text("at \(upcoming.totalXP) XP", comment: "Level screen, upcoming levels: the total XP a level is reached at.")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                awardRow("Log a food", XPAward.flatPerLog, "fork.knife")
                awardRow("Extend your streak", XPAward.streakExtensionBonus, "flame.fill")
                awardRow("Hit a nutrition goal", XPAward.goalHitBonus, "checkmark.circle.fill")
                awardRow("Complete a challenge", XPAward.challengeCompletionBonus, "target")
            } header: {
                Text("How to earn XP")
            } footer: {
                Text("Streak and goal bonuses are awarded at most once a day. Each level takes a little more XP than the last.")
            }
        }
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func awardRow(_ title: LocalizedStringKey, _ xp: Int, _ symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("+\(xp) XP")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    private struct UpcomingLevel: Identifiable {
        let level: Int
        let totalXP: Int
        var id: Int { level }
    }

    /// The next few levels and the total XP each is reached at.
    private func upcomingLevels(from progress: LevelCurve.Progress, count: Int = 5) -> [UpcomingLevel] {
        guard progress.xpNeededForNextLevel > 0 else { return [] }
        var result: [UpcomingLevel] = []
        // Absolute thresholds (not totalXP + remaining): correct also when
        // the displayed level is a held peak above the curve (design D10).
        var total = LevelCurve.threshold(forLevel: progress.level + 1)
        var level = progress.level + 1
        while result.count < count, level <= LevelCurve.maxLevel {
            result.append(UpcomingLevel(level: level, totalXP: total))
            total += LevelCurve.xpRequired(afterLevel: level)
            level += 1
        }
        return result
    }
}

// MARK: - Challenges

@MainActor
struct ChallengesView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let engine = environment.gamificationEngine

        List {
            Section("Today") {
                if engine.todayDailyChallenges.isEmpty {
                    Text("Today's daily challenges will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engine.todayDailyChallenges) { display in
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: display.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(display.isComplete ? Theme.success : Color.secondary.opacity(0.4))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(display.template.title)
                                    .strikethrough(display.isComplete)
                                Text(display.template.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(display.isComplete
                            ? String(localized: "\(display.template.title), \(display.template.subtitle), completed", comment: "VoiceOver: a daily challenge row. Title, description, done.")
                            : String(localized: "\(display.template.title), \(display.template.subtitle), not yet completed", comment: "VoiceOver: a daily challenge row. Title, description, still open."))
                    }
                }
            }

            Section("Active") {
                if let template = engine.activeChallengeTemplate, let progress = engine.challengeProgress {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text(template.title)
                                .font(.headline)
                            Spacer()
                            Text("+\(template.xpReward) XP")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text(template.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress.fraction)
                            .tint(Theme.accent)
                        HStack {
                            Text("\(progress.current) of \(progress.target)")
                            Spacer()
                            if let end = engine.challengeWindowEnd {
                                Text(timeLeftText(until: end))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Log a food to get your first challenge.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Completed") {
                if engine.completedChallenges.isEmpty {
                    Text("Completed challenges will show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(engine.completedChallenges) { completed in
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.success)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(engine.template(id: completed.templateId)?.title ?? completed.templateId)
                                Text(completed.completedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(completed.xpAwarded) XP")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                ForEach(engine.catalog) { template in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: symbol(for: template.category))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.title)
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(template.windowDays)d", comment: "Challenge list: the time window, abbreviated days (\"7d\"). Czech: \"7 d\".")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel(Text("\(template.windowDays) days"))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("All challenges")
            } footer: {
                Text("One challenge is active at a time. A new one starts when it's completed or its time runs out.")
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbol(for category: ChallengeCategory) -> String {
        switch category {
        case .streakExtension: return "flame"
        case .goalHitting: return "checkmark.circle"
        case .varietySeeking: return "sparkles"
        }
    }
}

// MARK: - Goal history

struct GoalHistoryList: View {
    let statuses: [DailyGoalStatus]

    var body: some View {
        if statuses.isEmpty {
            Text("Goal results appear here once days are loaded from Garmin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text("Day")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(GoalMacro.allCases, id: \.self) { macro in
                        Text(shortName(macro))
                            .frame(width: 36)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

                ForEach(statuses, id: \.date) { status in
                    HStack {
                        Text(dayLabel(status.date))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(GoalMacro.allCases, id: \.self) { macro in
                            Image(systemName: status.met(macro) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(status.met(macro) ? Theme.success : Color.secondary.opacity(0.4))
                                .frame(width: 36)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibility(status))
                }
            }
        }
    }

    private func shortName(_ macro: GoalMacro) -> String {
        switch macro {
        case .calories: return String(localized: "goal.short.calories", defaultValue: "kcal", comment: "Goals history column header for calories, max ~4 characters.")
        case .protein: return String(localized: "goal.short.protein", defaultValue: "P", comment: "Goals history column header: one-letter abbreviation of Protein (Czech: B, bílkoviny).")
        case .carbs: return String(localized: "goal.short.carbs", defaultValue: "C", comment: "Goals history column header: one-letter abbreviation of Carbs (Czech: S, sacharidy).")
        case .fat: return String(localized: "goal.short.fat", defaultValue: "F", comment: "Goals history column header: one-letter abbreviation of Fat (Czech: T, tuky).")
        }
    }

    private func dayLabel(_ date: String) -> String {
        guard let parsed = NutritionDayBoundary.date(fromDayString: date) else { return date }
        return parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func accessibility(_ status: DailyGoalStatus) -> String {
        let met = GoalMacro.allCases.filter { status.met($0) }.map(\.displayName)
        let label = dayLabel(status.date)
        if met.isEmpty {
            return String(localized: "\(label): no goals met", comment: "VoiceOver: a Goals history row with no goal met. %@ = the day.")
        }
        return String(localized: "\(label): met \(met.formatted(.list(type: .and)))", comment: "VoiceOver: a Goals history row. First %@ = the day, second = the goals met (\"Calories and Protein\").")
    }
}
