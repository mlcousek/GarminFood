// ProgressViews.swift
//
// The Progress tab (progress-screens spec): level and XP, streak history,
// challenges and goal history, each with its own detail screen. Everything
// shown is computed locally by the Gamification package; nothing here waits
// on the network.

import SwiftUI
import Gamification
import FoodLogCore

// MARK: - Progress home

@MainActor
struct ProgressHomeView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Same per-device preference `HydrationView`/`TrendsView` read -- only
    /// needed here to compute the streak number `TrendsSummaryCard` shows;
    /// see `HydrationComponents.swift`'s header for why this isn't
    /// Garmin-synced.
    @AppStorage("hydrationDailyGoalML") private var hydrationDailyGoalML: Double = 2000

    var body: some View {
        let engine = environment.gamificationEngine

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                NavigationLink {
                    StreakDetailView()
                } label: {
                    StreakSummaryCard(summary: engine.streakSummary, status: engine.streakStatus)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LevelDetailView()
                } label: {
                    LevelSummaryCard(progress: engine.levelProgress)
                }
                .buttonStyle(.plain)

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

                NavigationLink {
                    AchievementsView()
                } label: {
                    AchievementsSummaryCard(unlockedCount: engine.unlockedAchievements.count, totalCount: engine.achievementCatalog.count)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WeightView()
                } label: {
                    WeightSummaryCard(latest: environment.weightLoader.latest, previous: environment.weightLoader.previous)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    HydrationView()
                } label: {
                    HydrationSummaryCard(todayTotalML: environment.hydrationLoader.todayTotalML)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TrendsView()
                } label: {
                    TrendsSummaryCard(
                        hydrationStreak: HydrationHistory.streak(for: environment.hydrationLoader.entries, goalML: hydrationDailyGoalML)
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: "Goals, last 14 days")
                    GoalHistoryList(statuses: Array(engine.goalHistory.prefix(14)))
                        .card()
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Progress")
        .refreshable {
            await engine.refresh()
            await environment.weightLoader.refresh()
            await environment.hydrationLoader.refresh()
        }
    }
}

// MARK: - Summary cards

private struct CardHeader: View {
    let title: String
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            CardHeader(title: "Streak", systemImage: "flame.fill")
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(summary.currentLength)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                Text(summary.currentLength == 1 ? "day" : "days")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Best \(summary.longestLength)")
                        .font(.subheadline.weight(.semibold))
                    Text(status.hasLoggedToday ? "Today counted" : (status.isAtRiskToday ? "Log today to keep it" : "Log today to start"))
                        .font(.caption)
                        .foregroundStyle(status.isAtRiskToday ? Theme.ember : Color.secondary)
                }
            }
            StreakWeekStrip(days: Array(summary.days.suffix(7)))
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(summary.currentLength) days, best \(summary.longestLength)")
        .accessibilityHint("Opens streak history")
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
                Text("\(progress.totalXP) XP")
                    .font(.macroValue)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fractionToNextLevel)
                .tint(Theme.accent)
            Text(progress.xpNeededForNextLevel > 0
                 ? "\(progress.xpNeededForNextLevel - progress.xpIntoCurrentLevel) XP to level \(progress.level + 1)"
                 : "Max level reached")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(progress.level), \(tier.title), \(tier.rarity.displayName) tier, \(progress.totalXP) XP")
        .accessibilityHint("Opens level details")
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
                Text("\(completedCount) completed so far")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens challenges")
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
                Text("/ \(totalCount) unlocked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0)
                .tint(Theme.accent)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unlockedCount) of \(totalCount) achievements unlocked")
        .accessibilityHint("Opens achievements")
    }
}

/// Progress tab entry point into `WeightView` (add-weight-tracking) --
/// same "card summarises, tap opens the detail screen" shape as every other
/// card on this tab. Deliberately its own compact layout rather than
/// reusing `WeightHeroCard` (WeightComponents.swift) as-is: that view's own
/// "Current weight" caption would duplicate this card's `CardHeader` title.
private struct WeightSummaryCard: View {
    let latest: WeightEntry?
    let previous: WeightEntry?

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
        .accessibilityHint("Opens weight tracking")
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
                Text("ml today")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens hydration tracking")
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(hydrationStreak)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                Text("day water streak")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
            }
            Text("Macro and hydration history over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens trends and insights")
    }
}

/// "3 days left" / "Last day" for a challenge's final nutrition day.
func timeLeftText(until end: Date, now: Date = Date()) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    switch days {
    case ..<0: return "Ended"
    case 0: return "Last day"
    case 1: return "1 day left"
    default: return "\(days) days left"
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
        case .missed: return AnyShapeStyle(Color.primary.opacity(0.12))
        case .pending: return AnyShapeStyle(Theme.ember.opacity(0.18))
        case .future, .beforeHistory: return AnyShapeStyle(Color.primary.opacity(0.04))
        }
    }

    private var label: String {
        switch mark {
        case .logged: return "Logged"
        case .grace: return "Missed, forgiven"
        case .missed: return "Missed"
        case .pending: return "Today, nothing logged yet"
        case .future: return "Upcoming"
        case .beforeHistory: return "Before your first log"
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

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.sm) {
                    StatTile(value: "\(summary.currentLength)", label: "Current streak", systemImage: "flame.fill", tint: Theme.ember)
                    StatTile(value: "\(summary.longestLength)", label: "Longest streak", systemImage: "trophy.fill")
                    StatTile(value: "\(summary.loggedDayCount)", label: "Days logged", systemImage: "calendar")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: "Last 6 weeks")
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
                    SectionHeader(title: "How streaks work")
                    Text("Log at least one food on a day to count it. One missed day in any 7 is forgiven, shown with a shield. A second miss in the same 7 days starts the streak over.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if status.isAtRiskToday {
                        Label("Log something today to keep your \(status.length)-day streak.", systemImage: "exclamationmark.circle")
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
            legendItem(.missed, "Missed")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ mark: StreakHistory.Mark, _ title: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            StreakDot(mark: mark, isToday: false, size: 14)
            Text(title)
        }
    }
}

// MARK: - Level

@MainActor
struct LevelDetailView: View {
    @Environment(AppEnvironment.self) private var environment

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 160

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
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.5)
                        }
                    }
                    .frame(width: ringSize, height: ringSize)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Level \(progress.level), \(tier.title), \(tier.rarity.displayName) tier")
                    .accessibilityValue("\(Int((progress.fractionToNextLevel * 100).rounded())) percent to the next level")

                    VStack(spacing: 2) {
                        Text(tier.title)
                            .font(.headline)
                        Text(tier.flavor)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(progress.totalXP) XP total")
                        .font(.headline)
                    if progress.xpNeededForNextLevel > 0 {
                        Text("\(progress.xpIntoCurrentLevel) of \(progress.xpNeededForNextLevel) XP into this level")
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
                        Text("at \(upcoming.totalXP) XP")
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

    private func awardRow(_ title: String, _ xp: Int, _ symbol: String) -> some View {
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
        var total = progress.totalXP + (progress.xpNeededForNextLevel - progress.xpIntoCurrentLevel)
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
                        .accessibilityLabel("\(display.template.title), \(display.template.subtitle), \(display.isComplete ? "completed" : "not yet completed")")
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
                        Text("\(template.windowDays)d")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("\(template.windowDays) days")
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
        case .calories: return "kcal"
        case .protein: return "P"
        case .carbs: return "C"
        case .fat: return "F"
        }
    }

    private func dayLabel(_ date: String) -> String {
        guard let parsed = NutritionDayBoundary.date(fromDayString: date) else { return date }
        return parsed.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func accessibility(_ status: DailyGoalStatus) -> String {
        let met = GoalMacro.allCases.filter { status.met($0) }.map(\.rawValue)
        let label = dayLabel(status.date)
        return met.isEmpty ? "\(label): no goals met" : "\(label): met \(met.joined(separator: ", "))"
    }
}
