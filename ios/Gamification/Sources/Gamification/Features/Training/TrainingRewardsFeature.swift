// TrainingRewardsFeature.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the "training" gamification
// feature -- rewards that SUPPORT the plan, in place of the ones that push
// against it in the training experience (TrainingExperienceAvailability).
// It started as five badge ladders over the plan's own facts
// (TrainingSignals): morning check-ins 7 / 30 / 100, honest calls 1 / 10,
// gym weeks 1 / 4 / 12, habit ticks 25 / 100 / 300, weeks kept within plan
// 1 / 4 / 12 (TrainingRewardsCatalog, below).
//
// add-training-gamification-and-150-levels (D7, D8): it now also pays XP.
// Each run with the plan's facts (`context.trainingPlan`,
// TrainingPlanSignals):
//   1. `TrainingXPRules.evaluate` judges sessions, days and weeks and
//      returns every reward as a `RewardGrant` with a stable key
//      (`training.checkin.<day>`, `training.session.<id>`,
//      `training.week-kept.<week>`, ...). They are re-emitted on every run;
//      `RewardLedger` pays each key once, so re-reading the plan adds
//      nothing and a failed ledger write heals itself;
//   2. the ids behind the ladders go into `TrainingRewardsStore`, so counts
//      and streaks outlive the few weeks the plan file carries;
//   3. the habit-streak milestones (7 / 30 / 100 / 365) are granted from the
//      store's own streak;
//   4. every badge a count reaches is requested (the 14 original ones and
//      the 41 of TrainingProgressCatalog); the host unlocks each ONCE and
//      pays the generic badge bonus in full -- the training rewards are a
//      budgeted line of XPBudget now, not a scaled optional source;
//   5. a kept week, a closed phase, a completed season and a finished race
//      get one moment each, the first time they are recorded (never on the
//      first run, which records the whole plan window at once); the secret
//      "wise call" badge gets its own reveal.
// With honest calls and kept weeks decided by TrainingXPRules, the two
// original ladders and the XP agree.
//
// An app that passes only `context.training` (the original signals) still
// gets the original five ladders and no XP.
//
// Only in the training experience with a plan: otherwise it does nothing
// and shows nothing, and its badges are hidden unless already earned
// (TrainingExperienceAvailability.visibleBadges).
//
// Depends on: GamificationFeature, TrainingSignals, TrainingPlanSignals,
// TrainingXPRules, TrainingRewardsStore, TrainingProgressCatalog.
// Depended on by: GamificationFeatureRegistry, XPBudget (its line), the
// app's training section on the Progress tab (`progressModel`).
// Tests: TrainingRewardsTests, TrainingProgressTests.

import Foundation
import FoodLogCore

public actor TrainingRewardsFeature: GamificationFeature {
    public static let id = "training"
    /// PM: strength twice a week (the Winter Arc's gym rule).
    public static let gymSessionsPerWeek = 2

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] {
        TrainingRewardsCatalog.badges + TrainingProgressCatalog.badges
    }

    let directory: URL
    let store: TrainingRewardsStore
    /// The plan's today and week of the latest run, for the display APIs.
    private var lastToday: String?
    private var lastWeek: String?
    private var lastPlan: TrainingPlanSignals?

    public init(directory: URL) {
        self.directory = directory
        self.store = TrainingRewardsStore(directory: directory)
    }

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        guard context.isTrainingExperience else { return .empty }
        let plan = context.trainingPlan
        let signals = context.training
        guard plan != nil || signals != nil else { return .empty }
        guard await store.isReadable() else { return .empty }

        var grants: [RewardGrant] = []
        var moments: [FeatureMoment] = []
        var today = signals?.today
        var currentWeek = signals?.currentWeek
        if let plan {
            let seasonEnds = await store.seasonEnds()
            let evaluation = TrainingXPRules.evaluate(plan, snapshot: context.snapshot, knownSeasonEnds: seasonEnds)
            let recorded = await store.record(evaluation.facts)
            grants = evaluation.grants
            moments = Self.moments(for: recorded)
            today = plan.today
            currentWeek = TrainingRewardsCatalog.isoWeek(ofDay: plan.today)
        } else if let signals {
            await store.record(signals, gymSessionsPerWeek: Self.gymSessionsPerWeek)
        }
        try? await store.save()
        lastToday = today
        lastWeek = currentWeek
        lastPlan = plan

        let counts = await store.counts()
        let progress = await store.progress(today: today ?? "", currentWeek: currentWeek)
        if plan != nil {
            grants.append(contentsOf: TrainingXPRules.habitStreakGrants(best: progress.habitStreak.best))
        }

        let reached = (TrainingRewardsCatalog.reachedBadgeIds(counts)
            + TrainingProgressCatalog.reachedBadgeIds(counts: counts, progress: progress))
            .filter { !context.unlockedBadgeIds.contains($0) }
        if reached.contains(TrainingProgressCatalog.wiseCallBadgeId) {
            // Secret badges get no generic moment from the host: this is it.
            moments.append(Self.wiseCallMoment())
        }

        var summary: FeatureSummary?
        if let plan {
            summary = Self.summary(plan)
        } else if let signals {
            summary = Self.summary(signals)
        }
        return FeatureUpdate(grants: grants, unlockBadgeIds: reached, moments: moments, summary: summary)
    }

    /// The lifetime counts (for a detail screen).
    public func counts() async -> TrainingRewardCounts {
        await store.counts()
    }

    /// The counts and streaks behind every ladder, as of the latest run.
    public func progress() async -> TrainingProgress {
        await store.progress(today: lastToday ?? "", currentWeek: lastWeek)
    }

    /// The Progress tab's training section, as of the latest run.
    public func progressModel() async -> TrainingProgressModel {
        TrainingProgressModel.build(
            counts: await store.counts(),
            progress: await store.progress(today: lastToday ?? "", currentWeek: lastWeek),
            plan: lastPlan
        )
    }

    // MARK: - Summary

    /// "This week: 4 check-ins · gym 1/2".
    static func summary(_ signals: TrainingSignals) -> FeatureSummary {
        let week = signals.currentWeek.flatMap { current in signals.weeks.first { $0.week == current } }
        let weekDays = signals.days.filter { day in
            guard let current = signals.currentWeek else { return false }
            return TrainingRewardsCatalog.isoWeek(ofDay: day.day) == current
        }
        return summary(checkIns: weekDays.filter(\.checkedIn).count, strengthSessions: week?.strengthSessionsDone ?? 0)
    }

    /// The same card from the plan's facts.
    static func summary(_ plan: TrainingPlanSignals) -> FeatureSummary {
        let current = TrainingRewardsCatalog.isoWeek(ofDay: plan.today)
        let weekDays = plan.days.filter { current != nil && TrainingRewardsCatalog.isoWeek(ofDay: $0.day) == current }
        let strength = weekDays.reduce(0) { sum, day in
            sum + day.sessions.filter { $0.isDone && $0.isStrength }.count
        }
        return summary(checkIns: weekDays.filter(\.isCheckedIn).count, strengthSessions: strength)
    }

    private static func summary(checkIns: Int, strengthSessions: Int) -> FeatureSummary {
        let gym = min(strengthSessions, gymSessionsPerWeek)
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

    // MARK: - Moments

    /// One moment per kept week, closed phase, completed season and
    /// finished race that was recorded for the first time in this run.
    /// Nothing on the first recording: it takes in the whole plan window.
    static func moments(for recorded: TrainingRecordedFacts) -> [FeatureMoment] {
        guard !recorded.wasFirstRecording else { return [] }
        var moments: [FeatureMoment] = []
        let easyWeeks = Set(recorded.new(.easyWeek))
        for week in recorded.newKeptWeeks {
            if easyWeeks.contains(week) {
                moments.append(FeatureMoment(
                    featureId: id,
                    title: String(localized: "Easy week respected", bundle: .module, comment: "Moment title: a deload, taper or recovery week was kept at or under its target."),
                    message: String(localized: "You held back when the plan said so. That is the hard part.", bundle: .module, comment: "Moment message for a respected easy week."),
                    symbol: "tortoise.fill",
                    style: .celebration,
                    xpAwarded: XPAward.trainingWeekKept + XPAward.trainingEasyWeek
                ))
            } else {
                moments.append(FeatureMoment(
                    featureId: id,
                    title: String(localized: "Week kept within plan", bundle: .module, comment: "Moment title: a closed week with no missed session and no extra kilometres."),
                    message: String(localized: "Nothing missed, nothing extra.", bundle: .module, comment: "Moment message for a week kept within plan."),
                    symbol: "calendar.badge.checkmark",
                    style: .celebration,
                    xpAwarded: XPAward.trainingWeekKept
                ))
            }
        }
        for _ in recorded.new(.phase) {
            moments.append(FeatureMoment(
                featureId: id,
                title: String(localized: "Phase closed", bundle: .module, comment: "Moment title: a phase of the training plan was closed with its recap."),
                message: String(localized: "The recap is written. On to the next one.", bundle: .module, comment: "Moment message for a closed plan phase."),
                symbol: "book.closed.fill",
                style: .celebration,
                xpAwarded: XPAward.trainingPhaseCompleted
            ))
        }
        for _ in recorded.new(.season) {
            moments.append(FeatureMoment(
                featureId: id,
                title: String(localized: "Season completed", bundle: .module, comment: "Moment title: the training season's period has ended."),
                message: String(localized: "A whole season of showing up.", bundle: .module, comment: "Moment message for a completed season."),
                symbol: "trophy.fill",
                style: .celebration,
                xpAwarded: XPAward.trainingSeasonCompleted
            ))
        }
        for _ in recorded.new(.raceFinish) {
            moments.append(FeatureMoment(
                featureId: id,
                title: String(localized: "Race finished", bundle: .module, comment: "Moment title: a planned race was finished."),
                message: String(localized: "Prepared, raced, done. Write the report while it is fresh.", bundle: .module, comment: "Moment message for a finished race."),
                symbol: "flag.checkered",
                style: .celebration,
                xpAwarded: XPAward.trainingRaceFinished
            ))
        }
        return moments
    }

    /// The reveal of the secret badge for a race stopped, or not started,
    /// for a good reason.
    static func wiseCallMoment() -> FeatureMoment {
        FeatureMoment(
            featureId: id,
            title: String(localized: "Secret revealed!", bundle: .module, comment: "Reveal moment title when one secret achievement unlocks."),
            message: String(localized: "Lived to Run Another Day", bundle: .module, comment: "Secret training badge title: a race stopped, or not started, because a stop rule said so."),
            symbol: "hand.raised.fill",
            style: .secret,
            xpAwarded: XPAward.trainingWiseCall + XPAward.achievementBonus
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
