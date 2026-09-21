// GamificationEngine.swift
//
// The app-layer orchestrator for `add-gamification`: owns the Gamification
// package's stores, recomputes streak/level/challenge display state, and
// decides what counts as a "moment" (level-up, streak milestone, challenge
// completion -- design.md D5) worth surfacing to the UI. Lives here, not in
// `Gamification` itself, because it genuinely needs GarminKit (`GarminClient`,
// for the one network read this feature needs -- see `refreshGoalStatus`
// below) and FoodLogCore (`UsageHistoryStore`) together, which the
// `Gamification` package deliberately does not depend on (Package.swift's
// header) or does not depend on at all (GarminKit). Mirrors
// `AppEnvironment`'s own "composition root, thin views" rationale.
//
// WHY THIS ISN'T INSIDE `LogEntryCoordinator` (FoodLogCore): proposal.md is
// explicit that gamification has NO "Modified Capabilities" -- it reads
// `add-food-log-core`'s local log history without requiring that capability
// to change. `LogEntryCoordinator.confirm`/`confirmCustomFood` are
// therefore untouched; `LogEntryConfirmView` calls this engine as a
// deliberate SECOND step immediately after the coordinator's call succeeds
// (see that file), the same way it already treats `drainAndReconcile()` as
// a separate, later step.
import Foundation
import Observation
import GarminKit
import FoodLogCore
import Gamification

@MainActor
@Observable
final class GamificationEngine {
    private let usageHistory: UsageHistoryStore
    private let garminClient: GarminClient
    private let xpStore: XPStore
    private let goalStatusStore: GoalStatusStore
    private let challengeStore: ChallengeStore
    private let challengeHistoryStore: ChallengeHistoryStore
    private let dailyChallengeStore: DailyChallengeStore
    private let lifetimeStatsStore: LifetimeStatsStore
    private let achievementStore: AchievementStore

    /// Every day-keyed calculation uses the date entries are logged FOR
    /// (local midnight, the same date sent to Garmin), so streaks, XP bonuses
    /// and goal status agree with each other and with Garmin Connect even
    /// for a log made at 01:00. Goal status was stored under that date and
    /// looked up under a 04:00-shifted one before this.
    private let boundaryHour = NutritionDayBoundary.loggedDateBoundaryHour

    private(set) var streakStatus = StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil)
    private(set) var levelProgress = LevelCurve.level(forTotalXP: 0)
    private(set) var activeChallengeTemplate: ChallengeTemplate?
    private(set) var challengeProgress: ChallengeProgress?

    // Read-only data for the Progress and Profile screens.
    private(set) var streakSummary = StreakHistory.summary(loggedDays: [], today: Date())
    private(set) var activeChallenge: ActiveChallenge?
    private(set) var goalHistory: [DailyGoalStatus] = []
    private(set) var completedChallenges: [CompletedChallenge] = []
    private(set) var totalLogCount = 0
    private(set) var todayDailyChallenges: [DailyChallengeDisplay] = []
    /// Achievement id -> unlock date, for the Achievements screen.
    private(set) var unlockedAchievements: [String: Date] = [:]

    var catalog: [ChallengeTemplate] { ChallengeCatalog.all }
    var achievementCatalog: [AchievementDefinition] { AchievementCatalog.all }

    /// The last nutrition day the active challenge can still be completed on.
    var challengeWindowEnd: Date? {
        guard let activeChallenge, let activeChallengeTemplate else { return nil }
        return ChallengeEngine.window(for: activeChallenge, template: activeChallengeTemplate, boundaryHour: boundaryHour).end
    }

    func template(id: String) -> ChallengeTemplate? {
        ChallengeCatalog.all.first { $0.id == id }
    }

    /// A small FIFO queue of celebration-worthy events (levels spec's
    /// "visible, animated moment" / challenges spec's "rewarded, visible
    /// moment" requirements) -- almost always 0 or 1 entries, but a single
    /// log can in principle both level up AND complete a challenge, and
    /// both deserve their own moment rather than one clobbering the other.
    /// The UI reads `pendingMoments.first` and calls `dismissCurrentMoment()`
    /// once it has been shown.
    private(set) var pendingMoments: [GamificationMoment] = []

    /// Kept in sync with the on-disk usage history so `handleLogConfirmed`
    /// can diff "streak before this log" against "streak after" even
    /// though `LogEntryCoordinator.confirm` has already appended the new
    /// event to that same file by the time this engine sees it.
    private var lastKnownEvents: [UsageEvent] = []
    private var lastKnownGoalStatuses: [DailyGoalStatus] = []

    init(
        usageHistory: UsageHistoryStore,
        garminClient: GarminClient,
        xpStore: XPStore = XPStore(),
        goalStatusStore: GoalStatusStore = GoalStatusStore(),
        challengeStore: ChallengeStore = ChallengeStore(),
        challengeHistoryStore: ChallengeHistoryStore = ChallengeHistoryStore(),
        dailyChallengeStore: DailyChallengeStore = DailyChallengeStore(),
        lifetimeStatsStore: LifetimeStatsStore = LifetimeStatsStore(),
        achievementStore: AchievementStore = AchievementStore()
    ) {
        self.usageHistory = usageHistory
        self.garminClient = garminClient
        self.xpStore = xpStore
        self.goalStatusStore = goalStatusStore
        self.challengeStore = challengeStore
        self.challengeHistoryStore = challengeHistoryStore
        self.dailyChallengeStore = dailyChallengeStore
        self.lifetimeStatsStore = lifetimeStatsStore
        self.achievementStore = achievementStore
    }

    /// Recomputes everything the UI displays, without awarding anything --
    /// call on launch and on every foreground, same cadence as
    /// `AppEnvironment.refreshOnForeground()`'s other work. Also rotates a
    /// challenge whose time window has quietly elapsed while the app was
    /// closed (challenges spec's "also rotates after a time window").
    func refresh(now: Date = Date()) async {
        let events = await usageHistory.all()
        let goalStatuses = await goalStatusStore.all()
        lastKnownEvents = events
        lastKnownGoalStatuses = goalStatuses

        streakStatus = StreakEngine.status(events: events, now: now, boundaryHour: boundaryHour)
        levelProgress = LevelCurve.level(forTotalXP: await xpStore.currentTotal())
        updateHistory(events: events, goalStatuses: goalStatuses, now: now)
        completedChallenges = await challengeHistoryStore.all()
        try? await lifetimeStatsStore.backfillIfEmpty(events: events, goalStatuses: goalStatuses)

        // `if let`, not `guard ... else { return }`: a transient failure
        // here (disk pressure, a first-launch directory race) used to bail
        // out of the whole function, silently skipping
        // `refreshChallengeDisplay` below and leaving the Progress tab
        // showing stale or missing challenge state with no error surfaced.
        // `refreshChallengeDisplay` reads via `challengeStore.current()`,
        // which never throws, so it always runs now -- a failed
        // `ensureActive` this cycle just means no NEW challenge activation
        // or rotation-check happened, not that the rest of `refresh()` is
        // skipped.
        if let active = try? await challengeStore.ensureActive(
            catalog: ChallengeCatalog.all,
            now: now,
            baselineStreakLength: streakStatus.length
        ), let template = ChallengeCatalog.all.first(where: { $0.id == active.templateId }),
           ChallengeEngine.isWindowElapsed(active: active, template: template, now: now, boundaryHour: boundaryHour) {
            _ = try? await challengeStore.rotateIfWindowElapsed(
                catalog: ChallengeCatalog.all,
                now: now,
                baselineStreakLength: streakStatus.length,
                boundaryHour: boundaryHour
            )
        }

        await refreshChallengeDisplay(events: events, goalStatuses: goalStatuses, now: now)
        await refreshDailyChallenges(events: events, goalStatuses: goalStatuses, now: now)
        await checkAchievements(events: events, now: now)
    }

    /// Called once, right after `LogEntryCoordinator.confirm` /
    /// `confirmCustomFood` returns successfully (see LogEntryConfirmView).
    /// Awards XP, detects a level-up / streak milestone / challenge
    /// completion, and enqueues whichever "moments" apply. Entirely local
    /// computation and disk I/O -- no network call, so awaiting this from
    /// the confirm flow does not reintroduce a network wait.
    /// `calories` is the confirm screen's already-computed value for the
    /// entry just logged (`LogEntryConfirmView.caloriesForQuantity`) --
    /// `nil` for anything without a known calorie value. Threaded straight
    /// through to `LifetimeStatsStore`, which is the only thing in this
    /// engine that needs it (achievements spec's lifetime-calories ledger,
    /// design.md D4); nothing else here reads it.
    func handleLogConfirmed(now: Date = Date(), calories: Double? = nil) async {
        let previousStreak = StreakEngine.status(events: lastKnownEvents, now: now, boundaryHour: boundaryHour)
        let events = await usageHistory.all() // already includes the entry that was just confirmed
        let newStreak = StreakEngine.status(events: events, now: now, boundaryHour: boundaryHour)
        let streakExtended = newStreak.length > previousStreak.length

        let goalStatuses = await goalStatusStore.all()
        let today = NutritionDayBoundary.dayString(for: now, boundaryHour: boundaryHour)
        let goalMetToday = goalStatuses.first(where: { $0.date == today })?.anyGoalMet ?? false
        try? await lifetimeStatsStore.recordLog(nutritionDay: today, calories: calories, now: now)

        streakStatus = newStreak
        lastKnownEvents = events
        lastKnownGoalStatuses = goalStatuses
        updateHistory(events: events, goalStatuses: goalStatuses, now: now)

        if let xpResult = try? await xpStore.recordLog(nutritionDay: today, streakExtendedToday: streakExtended, goalMetToday: goalMetToday) {
            levelProgress = xpResult.levelAfter
            if xpResult.didLevelUp {
                pendingMoments.append(.levelUp(newLevel: xpResult.levelAfter.level))
            }
        }
        if streakExtended, StreakMilestones.isMilestone(newStreak.length) {
            pendingMoments.append(.streakMilestone(days: newStreak.length))
        }

        await checkChallengeCompletion(events: events, goalStatuses: goalStatuses, now: now)
        await checkDailyChallengeCompletion(events: events, goalStatuses: goalStatuses, now: now)
        await checkAchievements(events: events, now: now)
    }

    /// The one network call this feature makes anywhere (design.md's
    /// Context: "no network calls of its own beyond reading nutrition
    /// goals already fetched... for the main display"). Best-effort and
    /// fire-and-forget from every call site (see AppEnvironment /
    /// LogEntryConfirmView) -- a failed or slow fetch here must never block
    /// anything else, and simply leaves `goalStatusStore` with whatever it
    /// already had cached (possibly nothing, possibly stale by a day).
    ///
    /// ASSUMPTION, stated plainly because nothing in the probed contract
    /// says this explicitly: "met" for calories is treated as landing
    /// within +/-15% of the goal (there is no local signal for whether the
    /// account is targeting a deficit, a surplus, or maintenance, so
    /// neither "at or under" nor "at or over" is defensible as the one
    /// true rule). "Met" for protein/carbs/fat is treated as "at or above"
    /// the goal, matching the common real-world framing of a macro target
    /// as a minimum to hit, protein especially.
    func refreshGoalStatus(for date: Date = Date()) async {
        let dateString = NutritionDate.string(from: date)
        guard let log = try? await garminClient.dailyFoodLog(date: dateString),
              let goals = log.dailyNutritionGoals,
              let content = log.dailyNutritionContent
        else { return }

        let status = DailyGoalStatus(
            date: dateString,
            metCalorieGoal: Self.metWithinTolerance(actual: content.calories, goal: goals.adjustedCalories ?? goals.calories),
            metProteinGoal: Self.metAtLeast(actual: content.protein, goal: goals.adjustedProtein ?? goals.protein),
            metCarbGoal: Self.metAtLeast(actual: content.carbs, goal: goals.adjustedCarbs ?? goals.carbs),
            metFatGoal: Self.metAtLeast(actual: content.fat, goal: goals.adjustedFat ?? goals.fat)
        )
        try? await goalStatusStore.record(status)
        try? await lifetimeStatsStore.recordGoalStatus(status)
    }

    /// The UI calls this once it has finished presenting
    /// `pendingMoments.first` (animation complete, or immediately if
    /// Reduce Motion is on and only a static confirmation was shown).
    func dismissCurrentMoment() {
        guard !pendingMoments.isEmpty else { return }
        pendingMoments.removeFirst()
    }

    // MARK: - Private

    private func updateHistory(events: [UsageEvent], goalStatuses: [DailyGoalStatus], now: Date) {
        streakSummary = StreakHistory.summary(events: events, now: now, weeks: 6, boundaryHour: boundaryHour)
        goalHistory = goalStatuses.sorted { $0.date > $1.date }
        totalLogCount = events.count
    }

    private func refreshChallengeDisplay(events: [UsageEvent], goalStatuses: [DailyGoalStatus], now: Date) async {
        guard let active = await challengeStore.current(),
              let template = ChallengeCatalog.all.first(where: { $0.id == active.templateId })
        else {
            activeChallenge = nil
            activeChallengeTemplate = nil
            challengeProgress = nil
            return
        }
        activeChallenge = active
        activeChallengeTemplate = template
        challengeProgress = ChallengeEngine.progress(
            for: template,
            active: active,
            events: events,
            goalStatuses: goalStatuses,
            now: now,
            boundaryHour: boundaryHour
        )
    }

    /// Challenges spec's "completing a challenge... awards XP, presents a
    /// completion moment, and replaces the completed challenge."
    private func checkChallengeCompletion(events: [UsageEvent], goalStatuses: [DailyGoalStatus], now: Date) async {
        guard let active = try? await challengeStore.ensureActive(catalog: ChallengeCatalog.all, now: now, baselineStreakLength: streakStatus.length),
              let template = ChallengeCatalog.all.first(where: { $0.id == active.templateId })
        else { return }

        let progress = ChallengeEngine.progress(
            for: template,
            active: active,
            events: events,
            goalStatuses: goalStatuses,
            now: now,
            boundaryHour: boundaryHour
        )
        guard progress.isComplete else {
            activeChallenge = active
            activeChallengeTemplate = template
            challengeProgress = progress
            return
        }

        let xpResult = try? await xpStore.recordChallengeCompletion(xp: template.xpReward)
        let awarded = xpResult?.xpAwarded ?? template.xpReward
        pendingMoments.append(.challengeCompleted(title: template.title, xpAwarded: awarded))
        if let xpResult { levelProgress = xpResult.levelAfter }
        try? await challengeHistoryStore.record(CompletedChallenge(templateId: template.id, completedAt: now, xpAwarded: awarded))
        completedChallenges = await challengeHistoryStore.all()

        let rotated = try? await challengeStore.completeAndRotate(catalog: ChallengeCatalog.all, now: now, baselineStreakLength: streakStatus.length)
        if let rotated, let newTemplate = ChallengeCatalog.all.first(where: { $0.id == rotated.templateId }) {
            activeChallenge = rotated
            activeChallengeTemplate = newTemplate
            challengeProgress = ChallengeEngine.progress(
                for: newTemplate,
                active: rotated,
                events: events,
                goalStatuses: goalStatuses,
                now: now,
                boundaryHour: boundaryHour
            )
        }
    }

    // MARK: - Daily challenges (expand-gamification-depth, daily-challenges spec)

    /// Splits `events` into today's (by nutrition-day) and everything
    /// strictly before today -- `tryNewFood` needs "never seen before
    /// today" from the prior half.
    private func eventsForToday(_ events: [UsageEvent], now: Date) -> (today: [UsageEvent], prior: [UsageEvent]) {
        let todayDay = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: boundaryHour)
        var today: [UsageEvent] = []
        var prior: [UsageEvent] = []
        for event in events {
            let day = NutritionDayBoundary.nutritionDay(for: event, boundaryHour: boundaryHour)
            if day == todayDay {
                today.append(event)
            } else if day < todayDay {
                prior.append(event)
            }
        }
        return (today, prior)
    }

    private func refreshDailyChallenges(events: [UsageEvent], goalStatuses: [DailyGoalStatus], now: Date) async {
        let dayString = NutritionDayBoundary.dayString(for: now, boundaryHour: boundaryHour)
        guard let templates = try? await dailyChallengeStore.templatesForDay(dayString, catalog: DailyChallengeCatalog.all) else {
            todayDailyChallenges = []
            return
        }
        let (todayEvents, priorEvents) = eventsForToday(events, now: now)
        let goalStatus = goalStatuses.first { $0.date == dayString }
        todayDailyChallenges = templates.map { template in
            let complete = DailyChallengeEngine.isComplete(kind: template.kind, dayEvents: todayEvents, priorEvents: priorEvents, goalStatus: goalStatus)
            return DailyChallengeDisplay(template: template, isComplete: complete)
        }
    }

    /// daily-challenges spec's "the first time a given day's daily
    /// challenge is detected as complete" -- awards XP and enqueues a
    /// moment exactly once per (day, template), via `DailyChallengeStore`'s
    /// own idempotent `markCompleted`.
    private func checkDailyChallengeCompletion(events: [UsageEvent], goalStatuses: [DailyGoalStatus], now: Date) async {
        let dayString = NutritionDayBoundary.dayString(for: now, boundaryHour: boundaryHour)
        guard let templates = try? await dailyChallengeStore.templatesForDay(dayString, catalog: DailyChallengeCatalog.all) else { return }
        let (todayEvents, priorEvents) = eventsForToday(events, now: now)
        let goalStatus = goalStatuses.first { $0.date == dayString }

        var display: [DailyChallengeDisplay] = []
        for template in templates {
            let complete = DailyChallengeEngine.isComplete(kind: template.kind, dayEvents: todayEvents, priorEvents: priorEvents, goalStatus: goalStatus)
            display.append(DailyChallengeDisplay(template: template, isComplete: complete))
            guard complete, let justCompleted = try? await dailyChallengeStore.markCompleted(templateId: template.id, day: dayString), justCompleted else { continue }

            let xpResult = try? await xpStore.recordChallengeCompletion(xp: XPAward.dailyChallengeBonus)
            let awarded = xpResult?.xpAwarded ?? XPAward.dailyChallengeBonus
            pendingMoments.append(.dailyChallengeCompleted(title: template.title, xpAwarded: awarded))
            if let xpResult { levelProgress = xpResult.levelAfter }
        }
        todayDailyChallenges = display
    }

    // MARK: - Achievements (expand-gamification-depth, achievements spec)

    private func buildAchievementContext(events: [UsageEvent], now: Date) async -> AchievementContext {
        let lifetime = await lifetimeStatsStore.current()
        let dailyCompletedEver = await dailyChallengeStore.totalCompletedEver()
        let loggedDays = Set(events.map { NutritionDayBoundary.nutritionDay(for: $0, boundaryHour: boundaryHour) })

        return AchievementContext(
            level: levelProgress.level,
            longestStreak: streakSummary.longestLength,
            totalLogsEver: lifetime.totalLogsEver,
            distinctFoodsInRetainedHistory: Set(events.map(\.foodId)).count,
            challengeCompletionCount: completedChallenges.count,
            distinctCompletedChallengeTemplateCount: Set(completedChallenges.map(\.templateId)).count,
            totalChallengeCatalogCount: ChallengeCatalog.all.count,
            dailyChallengeCompletionCount: dailyCompletedEver,
            goalHitDaysEver: lifetime.goalHitDaysEver,
            maxSingleDayCalories: lifetime.maxSingleDayCalories,
            totalCaloriesEver: lifetime.totalCaloriesEver,
            hasPerfectCalendarMonth: AchievementSignals.hasPerfectCalendarMonth(loggedDays: loggedDays, calendar: .current),
            hasLoggedOnLeapDay: AchievementSignals.loggedOnLeapDay(events: events, boundaryHour: boundaryHour, calendar: .current),
            hasLoggedOnNewYearsDay: AchievementSignals.loggedOnNewYearsDay(events: events, boundaryHour: boundaryHour, calendar: .current),
            hasLoggedAtMidnight: AchievementSignals.loggedAtMidnight(events: events, calendar: .current),
            yearsSinceFirstLog: AchievementSignals.yearsSince(lifetime.firstLogDate, now: now, calendar: .current)
        )
    }

    /// achievements spec's "unlocking an achievement is a rewarded, visible
    /// moment" -- always refreshes `unlockedAchievements` for display
    /// (achievements spec's "showing... unlocked ones" requirement), and
    /// separately awards XP + enqueues a moment for anything newly unlocked
    /// this cycle.
    private func checkAchievements(events: [UsageEvent], now: Date) async {
        let context = await buildAchievementContext(events: events, now: now)
        let alreadyUnlocked = await achievementStore.unlockedIds()
        let newlyUnlocked = AchievementEngine.evaluate(context: context, alreadyUnlocked: alreadyUnlocked)

        if !newlyUnlocked.isEmpty {
            let recorded = (try? await achievementStore.unlock(ids: newlyUnlocked.map(\.id), now: now)) ?? []
            for definition in newlyUnlocked where recorded.contains(definition.id) {
                let xpResult = try? await xpStore.recordChallengeCompletion(xp: XPAward.achievementBonus)
                if let xpResult { levelProgress = xpResult.levelAfter }
                pendingMoments.append(.achievementUnlocked(title: definition.title, badgeSymbol: definition.badgeSymbol))
            }
        }
        unlockedAchievements = await achievementStore.all()
    }

    private static func metAtLeast(actual: Double?, goal: Double?) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return actual >= goal
    }

    private static func metWithinTolerance(actual: Double?, goal: Double?, tolerance: Double = 0.15) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return abs(actual - goal) <= goal * tolerance
    }
}
