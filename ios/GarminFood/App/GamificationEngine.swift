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

    var catalog: [ChallengeTemplate] { ChallengeCatalog.all }

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
        challengeHistoryStore: ChallengeHistoryStore = ChallengeHistoryStore()
    ) {
        self.usageHistory = usageHistory
        self.garminClient = garminClient
        self.xpStore = xpStore
        self.goalStatusStore = goalStatusStore
        self.challengeStore = challengeStore
        self.challengeHistoryStore = challengeHistoryStore
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
    }

    /// Called once, right after `LogEntryCoordinator.confirm` /
    /// `confirmCustomFood` returns successfully (see LogEntryConfirmView).
    /// Awards XP, detects a level-up / streak milestone / challenge
    /// completion, and enqueues whichever "moments" apply. Entirely local
    /// computation and disk I/O -- no network call, so awaiting this from
    /// the confirm flow does not reintroduce a network wait.
    func handleLogConfirmed(now: Date = Date()) async {
        let previousStreak = StreakEngine.status(events: lastKnownEvents, now: now, boundaryHour: boundaryHour)
        let events = await usageHistory.all() // already includes the entry that was just confirmed
        let newStreak = StreakEngine.status(events: events, now: now, boundaryHour: boundaryHour)
        let streakExtended = newStreak.length > previousStreak.length

        let goalStatuses = await goalStatusStore.all()
        let today = NutritionDayBoundary.dayString(for: now, boundaryHour: boundaryHour)
        let goalMetToday = goalStatuses.first(where: { $0.date == today })?.anyGoalMet ?? false

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

    private static func metAtLeast(actual: Double?, goal: Double?) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return actual >= goal
    }

    private static func metWithinTolerance(actual: Double?, goal: Double?, tolerance: Double = 0.15) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return abs(actual - goal) <= goal * tolerance
    }
}
