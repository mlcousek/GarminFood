// WeeklyBossFeature.swift
//
// add-weekly-boss-and-streak-freezes: the "boss" gamification feature
// (replaces the add-gamification-signals stub; the registry already creates
// it with `init(directory:)`). Two jobs, because both are this change's and
// the streak freeze is the boss's main reward:
//
// 1. THE WEEKLY BOSS (design D2/D3). Per run (`update`):
//    - settle every earlier week still marked active: recount its hits over
//      all seven (now complete) days, then defeated or escaped (no penalty);
//    - pick this ISO week's boss if none is stored yet (`BossPicker`, never
//      last week's) -> one intro moment;
//    - add today's hits (`BossFight`); hits >= target -> defeated -> one
//      defeat moment;
//    - save, THEN return: for every defeated week still kept,
//      `boss.defeat.<week>` (150-250 XP) and `boss.freeze.<week>` (a streak
//      freeze) -- re-emitted every run, applied once by `RewardLedger`, so a
//      failed ledger write heals itself. Keys use this feature's own id
//      namespace ("boss."); the host drops any other prefix.
//    - badges from the lifetime counters and from `StreakFreezeStore`
//      (the host skips already-unlocked ones), and the hub summary.
//    A boss store that exists but can't be read skips the run entirely.
//
// 2. STREAK FREEZES (design D4-D6). The app's `GamificationEngine` calls
//    `applyStreakFreezes` at the start of every refresh/confirm, BEFORE
//    computing the streak: it replays the balance, runs the pure
//    `StreakFreezePlanner`, records new consumptions in `StreakFreezeStore`
//    (owned here), and returns the frozen days plus one `.freeze` moment
//    per freeze just used. Local and fast; never the network.
//    add-supplements D9: with an active supplement digest the planner also
//    protects the supplement streak from the SAME pool (`planShared`).
//
// Depends on: BossCatalog, BossPicker, BossFight, BossStore,
// StreakFreezeStore, StreakFreezePlanner, FreezeBalance, WeekKey.
// Depended on by: GamificationFeatureRegistry, the app's GamificationEngine
// (freezes) and boss screens (`currentBoss()`, `history()`, `bestiary()`).

import Foundation
import FoodLogCore

/// This week's (or a past week's) boss, ready to display.
public struct BossWeekStatus: Sendable, Equatable, Identifiable {
    public let week: WeekKey
    public let archetype: BossArchetype
    public let target: Int
    public let hitDays: [String]
    public let adherence: Double
    public let outcome: BossOutcome
    /// Days of the week from today on (0 for a past week).
    public let daysLeft: Int

    public var id: String { week.rawValue }
    public var hits: Int { hitDays.count }
    public var remainingHP: Int { max(0, target - hits) }
    public var fraction: Double { target > 0 ? min(1, Double(hits) / Double(target)) : 0 }

    /// "Breakfast: 42 % of logged days".
    public var whyLine: String {
        archetype.adherenceLine(percent: adherence.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// One bestiary cell: an archetype and whether it was ever defeated.
public struct BossBestiaryEntry: Sendable, Equatable, Identifiable {
    public let archetype: BossArchetype
    public let isDefeated: Bool
    public var id: String { archetype.id }
}

/// The outcome of `applyStreakFreezes`.
public struct StreakFreezeRun: Sendable, Equatable {
    /// Every frozen FOOD day (midnights), to pass into `StreakEngine`/`StreakHistory`.
    public let frozenDays: Set<Date>
    public let balance: FreezeBalance.Result
    /// One `.freeze` moment per freeze consumed in this run.
    public let moments: [FeatureMoment]
    /// False while the freeze file exists but can't be read (no planning).
    public let isReadable: Bool
    /// add-supplements D9: every frozen SUPPLEMENT day (`yyyy-MM-dd`), for
    /// `SupplementSignals.frozenDays`.
    public var supplementFrozenDays: Set<String> = []

    public static let none = StreakFreezeRun(frozenDays: [], balance: .zero, moments: [], isReadable: true)
}

public actor WeeklyBossFeature: GamificationFeature {
    public static let id = "boss"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { BossCatalog.badges }

    let directory: URL
    private let store: BossStore
    private let freezeStore: StreakFreezeStore
    /// The calendar/today of the latest run, for the display APIs.
    private var lastCalendar: Calendar = .current
    private var lastTodayKey: String?

    public init(directory: URL) {
        self.directory = directory
        self.store = BossStore(directory: directory)
        self.freezeStore = StreakFreezeStore(directory: directory)
    }

    public static func defeatGrantKey(_ week: WeekKey) -> String { "\(id).defeat.\(week.rawValue)" }
    public static func freezeGrantKey(_ week: WeekKey) -> String { "\(id).freeze.\(week.rawValue)" }

    // MARK: - Weekly boss

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        let calendar = context.calendar
        let todayKey = context.snapshot.today
        lastCalendar = calendar
        lastTodayKey = todayKey
        guard let week = WeekKey(dayKey: todayKey, calendar: calendar) else { return .empty }

        let loaded = await store.load()
        guard loaded.isReadable else { return .empty }
        var state = loaded.state
        var weeks = state.weeks ?? [:]
        var newlyDefeated: [BossWeekRecord] = []

        // 1. Settle earlier weeks still running (all their days are complete).
        for (key, record) in weeks where key < week.rawValue && record.resolvedOutcome == .active {
            var settled = record
            guard let pastWeek = WeekKey(rawValue: key), let kind = record.kind else {
                settled.outcome = BossOutcome.escaped.rawValue
                weeks[key] = settled
                continue
            }
            let hits = Set(record.hits ?? []).union(BossFight.hitDays(kind, week: pastWeek, snapshot: context.snapshot, calendar: calendar))
            settled.hits = hits.sorted()
            if hits.count >= record.resolvedTarget {
                settled.outcome = BossOutcome.defeated.rawValue
                settled.defeatedOn = todayKey
                newlyDefeated.append(settled)
            } else {
                settled.outcome = BossOutcome.escaped.rawValue
            }
            weeks[key] = settled
        }

        // 2. This week's boss, chosen once and never re-rolled.
        var introduced = false
        if weeks[week.rawValue] == nil {
            let previous = week.adding(weeks: -1, calendar: calendar).flatMap { weeks[$0.rawValue]?.kind }
            let pick = BossPicker.pick(week: week, previous: previous, snapshot: context.snapshot, calendar: calendar)
            weeks[week.rawValue] = BossWeekRecord(
                bossId: pick.kind.rawValue,
                target: pick.target,
                adherence: pick.adherence,
                goodDays: pick.goodDays,
                consideredDays: pick.consideredDays,
                hits: [],
                outcome: BossOutcome.active.rawValue
            )
            introduced = true
        }

        // 3. This week's hits.
        if var current = weeks[week.rawValue], let kind = current.kind, current.resolvedOutcome == .active {
            let hits = Set(current.hits ?? []).union(BossFight.hitDays(kind, week: week, snapshot: context.snapshot, calendar: calendar))
            current.hits = hits.sorted()
            if hits.count >= current.resolvedTarget {
                current.outcome = BossOutcome.defeated.rawValue
                current.defeatedOn = todayKey
                newlyDefeated.append(current)
            }
            weeks[week.rawValue] = current
        }

        // Lifetime counters (they survive the 26-week pruning).
        var defeatedIds = state.defeatedIds ?? []
        for record in newlyDefeated {
            state.defeatCount = (state.defeatCount ?? 0) + 1
            if !defeatedIds.contains(record.bossId) { defeatedIds.append(record.bossId) }
            if record.resolvedTarget >= 7 { state.perfectDefeat = true }
        }
        state.defeatedIds = defeatedIds
        state.weeks = weeks
        state.prune()

        do {
            try await store.save(state)
        } catch {
            // Not saved: announce nothing, so the next run (starting from
            // the old state) announces it once instead of twice.
            return FeatureUpdate(summary: summary(state: loaded.state, week: week, todayKey: todayKey, calendar: calendar))
        }

        var moments: [FeatureMoment] = []
        if introduced, let record = state.weeks?[week.rawValue], let kind = record.kind {
            moments.append(Self.introMoment(kind: kind, target: record.resolvedTarget))
        }
        for record in newlyDefeated {
            guard let kind = record.kind else { continue }
            moments.append(Self.defeatMoment(kind: kind, target: record.resolvedTarget))
        }

        var grants: [RewardGrant] = []
        for entry in (state.weeks ?? [:]).sorted(by: { $0.key < $1.key }) where entry.value.resolvedOutcome == .defeated {
            guard let defeatedWeek = WeekKey(rawValue: entry.key) else { continue }
            grants.append(RewardGrant(key: Self.defeatGrantKey(defeatedWeek), kind: .xp(BossFight.defeatXP(target: entry.value.resolvedTarget))))
            grants.append(RewardGrant(key: Self.freezeGrantKey(defeatedWeek), kind: .streakFreeze))
        }

        let consumptions = await freezeStore.consumptions()
        return FeatureUpdate(
            grants: grants,
            unlockBadgeIds: Self.badgeIds(state: state, consumptions: consumptions),
            moments: moments,
            summary: summary(state: state, week: week, todayKey: todayKey, calendar: calendar)
        )
    }

    static func badgeIds(state: BossState, consumptions: [StreakFreezeStore.Consumption]) -> [String] {
        var ids: [String] = []
        let count = state.defeatCount ?? 0
        if count >= 1 { ids.append(BossCatalog.firstDefeatBadge) }
        if count >= 10 { ids.append(BossCatalog.tenDefeatsBadge) }
        if count >= 25 { ids.append(BossCatalog.twentyFiveDefeatsBadge) }
        if state.perfectDefeat == true { ids.append(BossCatalog.perfectBadge) }
        let defeated = Set(state.defeatedIds ?? [])
        if BossKind.allCases.allSatisfy({ defeated.contains($0.rawValue) }) { ids.append(BossCatalog.bestiaryBadge) }
        if !consumptions.isEmpty { ids.append(BossCatalog.firstFreezeBadge) }
        if consumptions.contains(where: { ($0.protectedLength ?? 0) >= 100 }) { ids.append(BossCatalog.freezeSaved100Badge) }
        return ids
    }

    // MARK: - Display API

    /// This week's boss, or nil before the first run of the week.
    public func currentBoss() async -> BossWeekStatus? {
        let state = await store.load().state
        let calendar = lastCalendar
        guard let todayKey = lastTodayKey,
              let week = WeekKey(dayKey: todayKey, calendar: calendar),
              let record = state.weeks?[week.rawValue]
        else { return nil }
        return Self.status(week: week, record: record, todayKey: todayKey, calendar: calendar)
    }

    /// Up to `limit` earlier weeks, newest first.
    public func history(limit: Int = 8) async -> [BossWeekStatus] {
        let state = await store.load().state
        let calendar = lastCalendar
        let todayKey = lastTodayKey ?? ""
        let currentWeek = WeekKey(dayKey: todayKey, calendar: calendar)?.rawValue ?? "~"
        let past = (state.weeks ?? [:])
            .filter { $0.key < currentWeek }
            .sorted { $0.key > $1.key }
            .prefix(max(0, limit))
        return past.compactMap { entry -> BossWeekStatus? in
            guard let week = WeekKey(rawValue: entry.key) else { return nil }
            return Self.status(week: week, record: entry.value, todayKey: todayKey, calendar: calendar)
        }
    }

    /// Every archetype, defeated ones lit.
    public func bestiary() async -> [BossBestiaryEntry] {
        let defeated = Set(await store.load().state.defeatedIds ?? [])
        return BossCatalog.all.map { BossBestiaryEntry(archetype: $0, isDefeated: defeated.contains($0.id)) }
    }

    static func status(week: WeekKey, record: BossWeekRecord, todayKey: String, calendar: Calendar) -> BossWeekStatus? {
        guard let kind = record.kind else { return nil }
        return BossWeekStatus(
            week: week,
            archetype: BossCatalog.archetype(kind),
            target: record.resolvedTarget,
            hitDays: (record.hits ?? []).sorted(),
            adherence: record.adherence ?? 0,
            outcome: record.resolvedOutcome,
            daysLeft: BossFight.daysLeft(in: week, todayKey: todayKey, calendar: calendar)
        )
    }

    private func summary(state: BossState, week: WeekKey, todayKey: String, calendar: Calendar) -> FeatureSummary? {
        guard let record = state.weeks?[week.rawValue],
              let status = Self.status(week: week, record: record, todayKey: todayKey, calendar: calendar)
        else { return nil }
        let hits = String(status.hits)
        let target = String(status.target)
        return FeatureSummary(
            title: status.archetype.name,
            subtitle: String(localized: "Hits: \(hits)/\(target)", bundle: .module, comment: "Weekly boss hub card: hits so far out of the target. Both values are numbers."),
            fraction: status.fraction,
            symbol: status.archetype.symbol
        )
    }

    // MARK: - Moments

    static func introMoment(kind: BossKind, target: Int) -> FeatureMoment {
        let archetype = BossCatalog.archetype(kind)
        let name = archetype.name
        let goal = archetype.goal
        return FeatureMoment(
            featureId: id,
            title: String(localized: "This week: \(name)", bundle: .module, comment: "Moment title: the week's boss is revealed. The value is the boss name."),
            message: String(localized: "\(goal) on \(target) of 7 days to defeat it.", bundle: .module, comment: "Moment message: the boss's habit and target. First value is the habit (e.g. 'Log breakfast'), second the number of days."),
            symbol: archetype.symbol,
            style: .boss
        )
    }

    static func defeatMoment(kind: BossKind, target: Int) -> FeatureMoment {
        let name = BossCatalog.archetype(kind).name
        return FeatureMoment(
            featureId: id,
            title: String(localized: "\(name) defeated!", bundle: .module, comment: "Moment title: the weekly boss was beaten. The value is the boss name."),
            message: String(localized: "You earned a streak freeze.", bundle: .module, comment: "Moment message: defeating the boss grants one streak freeze."),
            symbol: "shield.lefthalf.filled",
            style: .boss,
            xpAwarded: BossFight.defeatXP(target: target)
        )
    }

    // MARK: - Streak freezes

    /// The current balance without planning (for display before any run).
    public func freezeBalance(grants: [RewardLedger.FreezeGrant]) async -> FreezeBalance.Result {
        FreezeBalance.compute(grants: grants, consumptions: await freezeStore.consumptions())
    }

    /// Design D6, run by the app before every streak computation. With no
    /// grant ever recorded this never freezes anything (streak unchanged).
    ///
    /// add-supplements D9: `supplements` (an ACTIVE digest, else `nil`) adds
    /// the supplement streak to the same pool (`StreakFreezePlanner.
    /// planShared`); its frozen days come back in `supplementFrozenDays`.
    public func applyStreakFreezes(
        loggedDays: Set<Date>,
        grants: [RewardLedger.FreezeGrant],
        today: Date,
        calendar: Calendar,
        supplements: SupplementSignals? = nil
    ) async -> StreakFreezeRun {
        let loaded = await freezeStore.load()
        guard loaded.isReadable else {
            return StreakFreezeRun(frozenDays: [], balance: .zero, moments: [], isReadable: false)
        }
        let existing = StreakFreezePlanner.frozenDays(from: loaded.consumptions, calendar: calendar)
        let existingSupplement = StreakFreezePlanner.supplementFrozenDays(from: loaded.consumptions)
        let unchanged = StreakFreezeRun(
            frozenDays: existing,
            balance: FreezeBalance.compute(grants: grants, consumptions: loaded.consumptions),
            moments: [],
            isReadable: true,
            supplementFrozenDays: existingSupplement
        )
        let supplementInput = supplements.flatMap { signals -> StreakFreezePlanner.SupplementStreakInput? in
            guard signals.isActive else { return nil }
            return StreakFreezePlanner.SupplementStreakInput(days: signals.days, frozenDays: existingSupplement)
        }
        let plan = StreakFreezePlanner.planShared(
            loggedDays: loggedDays,
            frozenDays: existing,
            supplements: supplementInput,
            grants: grants,
            consumptions: loaded.consumptions,
            today: today,
            calendar: calendar
        )
        guard !plan.newConsumptions.isEmpty else { return unchanged }
        let recorded: [StreakFreezeStore.Consumption]
        do {
            recorded = try await freezeStore.record(plan.newConsumptions)
        } catch {
            // Not persisted: don't show (or announce) a freeze; the next run
            // re-plans from the stored list.
            return unchanged
        }
        // Announce only what THIS run recorded: an overlapping run (refresh
        // vs. log confirm, interleaved at the awaits above) may have planned
        // and recorded the same freeze first, and it already announced it.
        let moments = recorded.compactMap { consumption -> FeatureMoment? in
            guard let day = FreezeDayKey.date(for: consumption.frozenDay, calendar: calendar) else { return nil }
            let length = consumption.protectedLength ?? 0
            if consumption.streakKind == .supplements {
                return Self.supplementFreezeMoment(day: day, protectedLength: length, calendar: calendar)
            }
            return Self.freezeMoment(day: day, protectedLength: length, calendar: calendar)
        }
        return StreakFreezeRun(
            frozenDays: plan.frozenDays,
            balance: FreezeBalance.compute(grants: grants, consumptions: loaded.consumptions + plan.newConsumptions),
            moments: moments,
            isReadable: true,
            supplementFrozenDays: plan.supplementFrozenDays
        )
    }

    static func freezeMoment(day: Date, protectedLength: Int, calendar: Calendar) -> FeatureMoment {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let weekday = day.formatted(style)
        let length = protectedLength
        return FeatureMoment(
            featureId: id,
            title: String(localized: "Streak frozen", bundle: .module, comment: "Moment title: a streak freeze was used automatically."),
            message: String(localized: "A freeze covered \(weekday) — your \(length)-day streak lives on.", bundle: .module, comment: "Moment message: which missed day a freeze covered and the streak it saved. First value is a weekday name, second a number of days (always 3 or more)."),
            symbol: "snowflake",
            style: .freeze
        )
    }

    /// add-supplements D9: the same moment for the supplement streak.
    static func supplementFreezeMoment(day: Date, protectedLength: Int, calendar: Calendar) -> FeatureMoment {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        let weekday = day.formatted(style)
        let length = protectedLength
        return FeatureMoment(
            featureId: id,
            title: String(localized: "Supplement streak frozen", bundle: .module, comment: "Moment title: a streak freeze was used automatically for the supplement streak."),
            message: String(localized: "A freeze covered \(weekday) — your \(length)-day supplement streak lives on.", bundle: .module, comment: "Moment message: which missed supplement day a freeze covered and the supplement streak it saved. First value is a weekday name, second a number of days (always 3 or more)."),
            symbol: "snowflake",
            style: .freeze
        )
    }
}
