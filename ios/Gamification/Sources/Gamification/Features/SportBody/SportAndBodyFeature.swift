// SportAndBodyFeature.swift
//
// add-sport-and-body-achievements: the "sportBody" gamification feature --
// badges linking food to the owner's Garmin activities (fuel before,
// protein after, eating to match an active day, fuelling during long
// efforts), race days (the `race` day-note tag, the ONLY race source),
// weight-goal milestones and the kept-fast streak. Replaces the empty stub
// registered by add-gamification-signals (design D7);
// `GamificationFeatureRegistry` still creates it with `init(directory:)`.
//
// Each run (FeatureHost, after every refresh/confirm; local reads only --
// activities come from the cached READ-ONLY activities route, no request of
// its own):
//   1. evaluates every counted activity of the window (`SportRules`) and
//      records newly fuelled / recovered activity ids, Earned-It days and
//      race days in `SportBodyStore`, so tier counts outlive the 42-day
//      window;
//   2. requests every badge the counts / window reach (the host skips
//      already-unlocked ids and adds `XPAward.achievementBonus` + the
//      standard achievement moment -- `XPAward.sportBadge` is 0, so this
//      feature emits NO RewardLedger grants; if it ever does, keys must
//      start with "sportBody.");
//   3. emits a small 0-XP "fuelled right" / "recovered right" moment at most
//      once per activity -- the run that first counts it -- only for an
//      activity that ended within the last 36 h (no backlog flood on first
//      launch) and not when that family's badge unlocks in the same run (the
//      badge moment already celebrates it).
//
// Activities unavailable (standalone mode, route broken): activity badges
// simply do not progress; weight, fasting and race-day badges still work and
// nothing is shown as failed.
//
// UI reads (`recentActivities`, `bodyProgress`, `monthCounts`,
// `lifetimeCounts`, `activitiesAvailable`) come from the last run's window
// plus the store.
//
// Depends on: GamificationFeature, SportRules, BodyRules, SportBodyCatalog,
// SportBodyStore. Depended on by: GamificationFeatureRegistry, the app's
// SportBodySlotView / SportBodyView.

import Foundation
import FoodLogCore

/// Fuelled / recovered activities in one calendar month.
public struct SportMonthCounts: Sendable, Equatable {
    public let fuelled: Int
    public let recovered: Int

    public init(fuelled: Int, recovered: Int) {
        self.fuelled = fuelled
        self.recovered = recovered
    }
}

/// Lifetime counts behind the tiered badges.
public struct SportLifetimeCounts: Sendable, Equatable {
    public let fuelled: Int
    public let recovered: Int
    public let earnedDays: Int
    public let raceDays: Int

    public init(fuelled: Int, recovered: Int, earnedDays: Int, raceDays: Int) {
        self.fuelled = fuelled
        self.recovered = recovered
        self.earnedDays = earnedDays
        self.raceDays = raceDays
    }
}

/// Weight-goal and fasting picture for the Sport & Body screen.
public struct SportBodyProgress: Sendable, Equatable {
    /// `nil` without a weight target.
    public let weight: WeightMilestoneProgress?
    public let fastingStreak: Int
    /// The next fasting tier not reached yet, `nil` once all are.
    public let nextFastingTier: SportBodyCatalog.Tier?

    public init(weight: WeightMilestoneProgress?, fastingStreak: Int, nextFastingTier: SportBodyCatalog.Tier?) {
        self.weight = weight
        self.fastingStreak = fastingStreak
        self.nextFastingTier = nextFastingTier
    }
}

public actor SportAndBodyFeature: GamificationFeature {
    public static let id = "sportBody"

    /// Only an activity that ended this recently gets a small moment.
    static let momentRecency: TimeInterval = 36 * 3600
    /// The detail screen lists activities of this many recent days.
    public static let recentDays = 14

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { SportBodyCatalog.badges }

    let directory: URL
    let store: SportBodyStore

    private var lastEvaluations: [SportActivityEvaluation] = []
    private var lastProgress = SportBodyProgress(weight: nil, fastingStreak: 0, nextFastingTier: SportBodyCatalog.fastingTiers.first)
    private var lastActivitiesAvailable = false
    private var lastToday: String?
    private var lastCalendar = Calendar.current

    public init(directory: URL) {
        self.directory = directory
        self.store = SportBodyStore(directory: directory)
    }

    // MARK: - GamificationFeature

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let snapshot = context.snapshot
        let evaluations = SportRules.evaluations(in: snapshot)
        var update = FeatureUpdate()

        // 1. Record what counts (sticky beyond the window).
        var newlyFuelled: [SportActivityEvaluation] = []
        var newlyRecovered: [SportActivityEvaluation] = []
        for evaluation in evaluations {
            if evaluation.isFuelled {
                let isNew = await store.addFuelled(activityId: evaluation.id, day: evaluation.activity.day)
                if isNew { newlyFuelled.append(evaluation) }
            }
            if evaluation.isRecovered {
                let isNew = await store.addRecovered(activityId: evaluation.id, day: evaluation.activity.day)
                if isNew { newlyRecovered.append(evaluation) }
            }
        }
        for day in snapshot.orderedDays {
            if SportRules.isEarnedDay(day, today: snapshot.today) {
                await store.addEarnedDay(day.day)
            }
            if SportRules.isRaceDay(day, today: snapshot.today) {
                await store.addRaceDay(day.day)
            }
        }
        let counts = await lifetimeCounts()

        // 2. Badges.
        var requested: [String] = []
        func request(_ ids: [String]) {
            for id in ids where !context.unlockedBadgeIds.contains(id) && !requested.contains(id) {
                requested.append(id)
            }
        }
        request(SportBodyCatalog.reached(SportBodyCatalog.fuelTiers, count: counts.fuelled))
        request(SportBodyCatalog.reached(SportBodyCatalog.recoveryTiers, count: counts.recovered))
        request(SportBodyCatalog.reached(SportBodyCatalog.earnedTiers, count: counts.earnedDays))
        request(SportBodyCatalog.reached(SportBodyCatalog.raceDayTiers, count: counts.raceDays))
        if snapshot.orderedDays.contains(where: SportRules.isDoubleDay) {
            request([SportBodyCatalog.doubleDayId])
        }
        if evaluations.contains(where: { $0.isGelGuru }) {
            request([SportBodyCatalog.gelGuruId])
        }
        if evaluations.contains(where: { $0.isLongHaul }) {
            request([SportBodyCatalog.longHaulId])
        }
        if !SportRules.carbLoadedRaceDays(in: snapshot, calendar: context.calendar).isEmpty {
            request([SportBodyCatalog.carbLoaderId])
        }
        request(BodyRules.weightBadgeIds(in: snapshot, calendar: context.calendar))
        let fastingStreak = BodyRules.keptFastingStreak(in: snapshot)
        request(BodyRules.fastingBadgeIds(streak: fastingStreak))
        update.unlockBadgeIds = requested

        // 3. Small moments, once per activity.
        let fuelBadgeNow = requested.contains { id in SportBodyCatalog.fuelTiers.contains { $0.id == id } }
        let recoveryBadgeNow = requested.contains { id in SportBodyCatalog.recoveryTiers.contains { $0.id == id } }
        if !fuelBadgeNow, let latest = mostRecent(newlyFuelled, now: context.now) {
            update.moments.append(Self.fuelMoment(latest))
        }
        if !recoveryBadgeNow, let latest = mostRecent(newlyRecovered, now: context.now) {
            update.moments.append(Self.recoveryMoment(latest))
        }

        // A failed save costs at most a repeated small moment next run;
        // badges are idempotent in AchievementStore.
        try? await store.save()

        lastEvaluations = evaluations
        lastProgress = SportBodyProgress(
            weight: BodyRules.milestoneProgress(in: snapshot),
            fastingStreak: fastingStreak,
            nextFastingTier: SportBodyCatalog.nextTier(SportBodyCatalog.fastingTiers, count: fastingStreak)
        )
        lastActivitiesAvailable = SportRules.activitiesAvailable(in: snapshot)
        lastToday = snapshot.today.isEmpty ? nil : snapshot.today
        lastCalendar = context.calendar

        let month = await store.counts(monthPrefix: Self.monthPrefix(today: snapshot.today, now: context.now, calendar: context.calendar))
        update.summary = FeatureSummary(
            title: String(localized: "Sport & Body", bundle: .module, comment: "Sport & body hub card title."),
            subtitle: String(
                format: String(localized: "This month: %1$lld fuelled · %2$lld recovered", bundle: .module, comment: "Sport & body hub card: activities fuelled before / recovered after this month."),
                month.fuelled,
                month.recovered
            ),
            fraction: nil,
            symbol: "figure.run"
        )
        return update
    }

    // MARK: - UI reads

    /// Counted activities of the last `recentDays` days, newest first, with
    /// the entries that made them count. Empty before the first run.
    public func recentActivities() -> [SportActivityEvaluation] {
        guard let today = lastToday,
              let cutoff = SportRules.dayKey(today, offsetBy: -(Self.recentDays - 1), calendar: lastCalendar)
        else { return lastEvaluations.reversed() }
        return lastEvaluations
            .filter { $0.activity.day >= cutoff && $0.activity.day <= today }
            .reversed()
    }

    public func bodyProgress() -> SportBodyProgress {
        lastProgress
    }

    /// Whether the last run saw any Garmin activity data at all.
    public func activitiesAvailable() -> Bool {
        lastActivitiesAvailable
    }

    public func monthCounts(now: Date = Date(), calendar: Calendar = .current) async -> SportMonthCounts {
        let prefix = Self.monthPrefix(today: lastToday ?? "", now: now, calendar: calendar)
        let counts = await store.counts(monthPrefix: prefix)
        return SportMonthCounts(fuelled: counts.fuelled, recovered: counts.recovered)
    }

    public func lifetimeCounts() async -> SportLifetimeCounts {
        let fuelled = await store.fuelledActivityIds().count
        let recovered = await store.recoveredActivityIds().count
        let earnedDays = await store.earnedDays().count
        let raceDays = await store.raceDays().count
        return SportLifetimeCounts(fuelled: fuelled, recovered: recovered, earnedDays: earnedDays, raceDays: raceDays)
    }

    // MARK: - Helpers

    /// "2026-09" from the snapshot's today, else from `now`.
    static func monthPrefix(today: String, now: Date, calendar: Calendar) -> String {
        let key = today.count >= 7 ? today : NutritionDate.string(from: now, calendar: calendar)
        return String(key.prefix(7))
    }

    private func mostRecent(_ evaluations: [SportActivityEvaluation], now: Date) -> SportActivityEvaluation? {
        evaluations
            .filter { now.timeIntervalSince($0.activity.end) <= Self.momentRecency }
            .max { $0.activity.start < $1.activity.start }
    }

    static func fuelMoment(_ evaluation: SportActivityEvaluation) -> FeatureMoment {
        let entry = evaluation.headlineFuelEntry
        let lead = entry.map { Int((evaluation.activity.start.timeIntervalSince($0.timestamp) / 60).rounded()) } ?? 0
        let message: String
        if let carbs = entry?.carbs {
            message = String(
                format: String(localized: "%1$lld g carbs %2$lld min before the start.", bundle: .module, comment: "Fuel moment: grams of carbs logged, minutes before the activity started."),
                Int(carbs.rounded()),
                lead
            )
        } else {
            message = String(
                format: String(localized: "A carb-rich snack %lld min before the start.", bundle: .module, comment: "Fuel moment when the carbs are unknown: minutes before the activity started."),
                lead
            )
        }
        return FeatureMoment(
            featureId: id,
            title: String(localized: "Fuelled right", bundle: .module, comment: "Moment title: an activity was fuelled with carbs beforehand."),
            message: message,
            symbol: "fuelpump.fill",
            style: .celebration,
            xpAwarded: 0
        )
    }

    static func recoveryMoment(_ evaluation: SportActivityEvaluation) -> FeatureMoment {
        FeatureMoment(
            featureId: id,
            title: String(localized: "Recovered right", bundle: .module, comment: "Moment title: protein eaten soon after an activity."),
            message: String(
                format: String(localized: "%lld g protein within an hour after the finish.", bundle: .module, comment: "Recovery moment: grams of protein logged within 60 min after the activity."),
                Int(evaluation.recoveryProteinGrams.rounded())
            ),
            symbol: "timer",
            style: .celebration,
            xpAwarded: 0
        )
    }
}
