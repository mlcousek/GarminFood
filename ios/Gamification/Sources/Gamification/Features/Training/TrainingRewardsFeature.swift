// TrainingRewardsFeature.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the "training" gamification
// feature -- rewards that SUPPORT the plan, in place of the ones that push
// against it in the training experience (TrainingExperienceAvailability).
// Five badge ladders over the plan's own facts (TrainingSignals, filled by
// the app's adapter from TrainingCore):
//   - morning check-ins: 7 / 30 / 100 days checked in;
//   - honest calls: an amber or red morning followed by its option -- 1 / 10;
//   - gym: weeks with at least `gymSessionsPerWeek` (2) strength sessions
//     done -- 1 / 4 / 12;
//   - habits: habit ticks -- 25 / 100 / 300;
//   - the week kept within plan (only when the projection closes it that
//     way) -- 1 / 4 / 12.
//
// Each run: record the window's facts in `TrainingRewardsStore` (so counts
// outlive the few weeks the projection carries), then request every badge
// a count reaches. The host unlocks each badge ONCE (AchievementStore) and
// pays the generic badge bonus scaled as an optional source
// (`XPBudget.isOptional`), with the standard achievement moment -- this
// feature emits no RewardLedger grants, so nothing can be paid twice.
//
// Only in the training experience with a plan (`context.training`):
// otherwise it does nothing and shows nothing, and its badges are hidden
// unless already earned (TrainingExperienceAvailability.visibleBadges).
//
// Depends on: GamificationFeature, TrainingSignals, TrainingRewardsStore.
// Depended on by: GamificationFeatureRegistry, XPBudget (its line).
// Tests: TrainingRewardsTests.

import Foundation
import FoodLogCore

public actor TrainingRewardsFeature: GamificationFeature {
    public static let id = "training"
    /// PM: strength twice a week (the Winter Arc's gym rule).
    public static let gymSessionsPerWeek = 2

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { TrainingRewardsCatalog.badges }

    let directory: URL
    let store: TrainingRewardsStore

    public init(directory: URL) {
        self.directory = directory
        self.store = TrainingRewardsStore(directory: directory)
    }

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        guard context.isTrainingExperience, let signals = context.training else { return .empty }
        guard await store.isReadable() else { return .empty }
        await store.record(signals, gymSessionsPerWeek: Self.gymSessionsPerWeek)
        try? await store.save()
        let counts = await store.counts()

        let reached = TrainingRewardsCatalog.reachedBadgeIds(counts)
            .filter { !context.unlockedBadgeIds.contains($0) }
        return FeatureUpdate(
            unlockBadgeIds: reached,
            summary: Self.summary(signals)
        )
    }

    /// The lifetime counts (for a detail screen).
    public func counts() async -> TrainingRewardCounts {
        await store.counts()
    }

    /// "This week: 4 check-ins · gym 1/2".
    static func summary(_ signals: TrainingSignals) -> FeatureSummary {
        let week = signals.currentWeek.flatMap { current in signals.weeks.first { $0.week == current } }
        let gym = min(week?.strengthSessionsDone ?? 0, gymSessionsPerWeek)
        let weekDays = signals.days.filter { day in
            guard let current = signals.currentWeek else { return false }
            return TrainingRewardsCatalog.isoWeek(ofDay: day.day) == current
        }
        let checkIns = weekDays.filter(\.checkedIn).count
        return FeatureSummary(
            title: String(localized: "Training rewards", bundle: .module, comment: "Hub card title of the training rewards (check-ins, gym, habits, weeks kept within plan)."),
            subtitle: String(
                format: String(localized: "This week: check-ins %lld · gym %lld/%lld", bundle: .module, comment: "Training rewards summary. First %lld = morning check-ins this week, then strength sessions done of the weekly two."),
                checkIns, gym, gymSessionsPerWeek
            ),
            fraction: Double(gym) / Double(gymSessionsPerWeek),
            symbol: "figure.run"
        )
    }
}

public enum TrainingRewardsCatalog {
    public static let checkInTiers: [SportBodyCatalog.Tier] = [
        .init(id: "training.checkin-7", threshold: 7),
        .init(id: "training.checkin-30", threshold: 30),
        .init(id: "training.checkin-100", threshold: 100),
    ]
    public static let honestTiers: [SportBodyCatalog.Tier] = [
        .init(id: "training.honest-1", threshold: 1),
        .init(id: "training.honest-10", threshold: 10),
    ]
    public static let gymTiers: [SportBodyCatalog.Tier] = [
        .init(id: "training.gym-week-1", threshold: 1),
        .init(id: "training.gym-week-4", threshold: 4),
        .init(id: "training.gym-week-12", threshold: 12),
    ]
    public static let habitTiers: [SportBodyCatalog.Tier] = [
        .init(id: "training.habits-25", threshold: 25),
        .init(id: "training.habits-100", threshold: 100),
        .init(id: "training.habits-300", threshold: 300),
    ]
    public static let keptWeekTiers: [SportBodyCatalog.Tier] = [
        .init(id: "training.week-kept-1", threshold: 1),
        .init(id: "training.week-kept-4", threshold: 4),
        .init(id: "training.week-kept-12", threshold: 12),
    ]

    /// Every badge id a set of counts reaches, in ladder order.
    public static func reachedBadgeIds(_ counts: TrainingRewardCounts) -> [String] {
        func reached(_ tiers: [SportBodyCatalog.Tier], _ count: Int) -> [String] {
            tiers.filter { count >= $0.threshold }.map(\.id)
        }
        return reached(checkInTiers, counts.checkInDays)
            + reached(honestTiers, counts.honestCalls)
            + reached(gymTiers, counts.gymWeeks)
            + reached(habitTiers, counts.habitTicks)
            + reached(keptWeekTiers, counts.keptWeeks)
    }

    /// `YYYY-Www` of a `yyyy-MM-dd` day (ISO 8601 weeks), `nil` if unreadable.
    static func isoWeek(ofDay day: String) -> String? {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }

    public static var badges: [AchievementDefinition] {
        [
            define("training.checkin-7",
                   String(localized: "Morning Report", bundle: .module, comment: "Training badge title: 7 morning check-ins."),
                   checkInSubtitle(7), category: .streak, symbol: "sunrise.fill", rarity: .common),
            define("training.checkin-30",
                   String(localized: "Honest Mornings", bundle: .module, comment: "Training badge title: 30 morning check-ins."),
                   checkInSubtitle(30), category: .streak, symbol: "sun.max.fill", rarity: .rare),
            define("training.checkin-100",
                   String(localized: "Hundred Mornings", bundle: .module, comment: "Training badge title: 100 morning check-ins."),
                   checkInSubtitle(100), category: .streak, symbol: "sun.horizon.fill", rarity: .epic),
            define("training.honest-1",
                   String(localized: "Listened to the Body", bundle: .module, comment: "Training badge title: an amber or red morning followed by its easier option."),
                   String(localized: "Check in amber or red, then do that option instead of the full session.", bundle: .module, comment: "Training badge description."),
                   symbol: "ear.fill", rarity: .uncommon),
            define("training.honest-10",
                   String(localized: "Smart Athlete", bundle: .module, comment: "Training badge title: ten honest amber/red mornings followed."),
                   String(localized: "Follow an amber or red morning with its option 10 times.", bundle: .module, comment: "Training badge description."),
                   symbol: "brain.head.profile", rarity: .rare),
            define("training.gym-week-1",
                   String(localized: "Gym Twice", bundle: .module, comment: "Training badge title: a week with two strength sessions."),
                   gymSubtitle(1), symbol: "dumbbell.fill", rarity: .common),
            define("training.gym-week-4",
                   String(localized: "Strong Month", bundle: .module, comment: "Training badge title: four weeks with two strength sessions."),
                   gymSubtitle(4), symbol: "figure.strengthtraining.traditional", rarity: .uncommon),
            define("training.gym-week-12",
                   String(localized: "Built to Last", bundle: .module, comment: "Training badge title: twelve weeks with two strength sessions."),
                   gymSubtitle(12), symbol: "shield.lefthalf.filled", rarity: .epic),
            define("training.habits-25",
                   String(localized: "Habit Builder", bundle: .module, comment: "Training badge title: 25 habit ticks."),
                   habitSubtitle(25), symbol: "checklist", rarity: .common),
            define("training.habits-100",
                   String(localized: "Daily Details", bundle: .module, comment: "Training badge title: 100 habit ticks."),
                   habitSubtitle(100), symbol: "checklist.checked", rarity: .uncommon),
            define("training.habits-300",
                   String(localized: "Habit Machine", bundle: .module, comment: "Training badge title: 300 habit ticks."),
                   habitSubtitle(300), symbol: "gearshape.2.fill", rarity: .rare),
            define("training.week-kept-1",
                   String(localized: "By the Plan", bundle: .module, comment: "Training badge title: a week closed within plan."),
                   keptSubtitle(1), symbol: "calendar.badge.checkmark", rarity: .common),
            define("training.week-kept-4",
                   String(localized: "Patient Builder", bundle: .module, comment: "Training badge title: four weeks closed within plan."),
                   keptSubtitle(4), symbol: "calendar", rarity: .rare),
            define("training.week-kept-12",
                   String(localized: "Winter Arc", bundle: .module, comment: "Training badge title: twelve weeks closed within plan."),
                   keptSubtitle(12), symbol: "snowflake", rarity: .epic),
        ]
    }

    private static func define(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        category: AchievementCategory = .goalHitting,
        symbol: String,
        rarity: AchievementRarity
    ) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            title: title,
            subtitle: subtitle,
            category: category,
            badgeSymbol: symbol,
            condition: .featureEvaluated,
            rarityOverride: rarity,
            featureId: TrainingRewardsFeature.id
        )
    }

    // Count-first wording ("…: 30"), so no Czech plural form is needed.
    private static func checkInSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Days with a morning check-in: %lld", bundle: .module, comment: "Training badge description; %lld = days with a morning check-in needed (7, 30 or 100)."), count)
    }

    private static func gymSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Weeks with both strength sessions: %lld", bundle: .module, comment: "Training badge description; %lld = weeks with two strength sessions done needed (1, 4 or 12)."), count)
    }

    private static func habitSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Habit ticks: %lld", bundle: .module, comment: "Training badge description; %lld = habit ticks needed (25, 100 or 300)."), count)
    }

    private static func keptSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Weeks closed within the plan: %lld", bundle: .module, comment: "Training badge description; %lld = weeks the plan closed with no missed session and no volume overshoot (1, 4 or 12)."), count)
    }
}
