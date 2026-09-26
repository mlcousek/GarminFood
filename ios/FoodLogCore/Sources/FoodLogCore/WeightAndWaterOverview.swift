// WeightAndWaterOverview.swift
//
// The glue between the cached Garmin reads (`GarminHealthSnapshot`), the
// app's own stores/outboxes and the owner's goal overrides -- i.e. exactly
// what the Weight/Water cards and screens show (sync-weight-hydration-with-
// garmin, design.md D4 + D5). WHY a separate file: each piece is a small
// pure function over values the app's `WeightLoader`/`HydrationLoader`
// already hold, but deciding e.g. "which cached day's Garmin water goal
// applies today" or "which rows feed the ETA trend" is domain logic the
// untestable UI target shouldn't own (CLAUDE.md: keep UI thin). Unit-tested
// in FoodLogCoreTests/WeightAndWaterOverviewTests.swift.
//
// Builds on `WeightHistoryMerge` (rows), `WeightGoalProgress`/
// `GoalResolution` (goals) and `HydrationDayTotal` (water total); adds no
// rules of its own beyond "fall back to the newest earlier cached goal".

import Foundation
import GarminKit

public enum WeightAndWaterOverview {
    // MARK: - Weight

    /// The effective weight goal: the local override (D5) else Garmin's
    /// cached plan; `nil` when neither has a target (the card hides the bar).
    public static func weightGoal(
        snapshot: GarminHealthSnapshot,
        targetSource: GoalSource,
        startOverrideKg: Double?
    ) -> EffectiveWeightGoal? {
        GoalResolution.weight(
            targetSource: targetSource,
            startOverrideKg: startOverrideKg,
            garminTargetGrams: snapshot.weightGoal?.targetWeightGrams,
            garminStartGrams: snapshot.weightGoal?.startingWeightGrams,
            garminRateGramsPerWeek: snapshot.weightGoal?.weightChangeRateGramsPerWeek,
            garminChangeType: snapshot.weightGoal?.weightChangeType
        )
    }

    /// Progress toward `goal` from the merged history (newest first): the
    /// newest row is "current", and every row feeds the 14-day trend
    /// (`WeightGoalProgress` filters to the window itself). Pending local
    /// weigh-ins count -- the user did weigh that much.
    public static func weightProgress(
        rows: [WeighInDisplayEntry],
        goal: EffectiveWeightGoal?,
        now: Date
    ) -> WeightGoalProgress? {
        guard let goal, let current = rows.first else { return nil }
        let points = rows.map { WeightTrendPoint(date: $0.loggedAt, kg: $0.weightKg) }
        return WeightGoalProgress.compute(goal: goal, currentKg: current.weightKg, recentWeighIns: points, now: now)
    }

    // MARK: - Water

    /// Garmin's water goal for `day` (`yyyy-MM-dd`): that day's cached
    /// `goalInML`, else the newest earlier cached day's (Garmin's goal
    /// barely changes day to day, and right after midnight -- or offline --
    /// today hasn't been read yet). `nil` when nothing usable is cached.
    public static func garminWaterGoalML(snapshot: GarminHealthSnapshot, on day: String) -> Double? {
        if let goal = snapshot.hydrationDays[day]?.daily.goalInML, goal > 0 {
            return goal
        }
        return snapshot.hydrationDays
            .filter { $0.key < day }
            .sorted { $0.key > $1.key }
            .lazy
            .compactMap { entry -> Double? in
                guard let goal = entry.value.daily.goalInML, goal > 0 else { return nil }
                return goal
            }
            .first
    }

    /// The effective water goal for `day`: override, else Garmin's, else
    /// `GoalResolution.fallbackWaterGoalML`.
    public static func waterGoal(snapshot: GarminHealthSnapshot, source: GoalSource, on day: String) -> EffectiveWaterGoal {
        GoalResolution.water(source: source, garminGoalML: garminWaterGoalML(snapshot: snapshot, on: day))
    }

    /// The water total for the day containing `date` (D4): Garmin's cached
    /// `valueInML` for that day plus whatever the app logged that Garmin's
    /// read can't include yet.
    public static func waterTotalML(
        snapshot: GarminHealthSnapshot,
        outboxEntries: [HydrationOutboxEntry],
        on date: Date,
        calendar: Calendar = .current
    ) -> Double {
        let cached = snapshot.hydrationDays[NutritionDate.string(from: date, calendar: calendar)]
        return HydrationDayTotal.total(
            garminDaily: cached?.daily,
            garminFetchedAt: cached?.fetchedAt,
            outboxEntries: outboxEntries,
            on: date,
            calendar: calendar
        )
    }
}

// MARK: - Standalone mode (add-standalone-mode D7, task 4.4)
//
// No Garmin: every row and total comes from this phone's own stores. The
// cached Garmin reads and the outboxes are ignored on purpose -- after a
// switch from Garmin mode they may still hold old values, and standalone
// never shows a "not in Garmin yet" badge.

extension WeightAndWaterOverview {
    /// Local weigh-ins only, newest first, every row `.synced` (no badge).
    public static func standaloneWeightRows(localEntries: [WeightEntry], calendar: Calendar = .current) -> [WeighInDisplayEntry] {
        WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: [:],
            localEntries: localEntries,
            outboxEntries: [],
            calendar: calendar
        )
    }

    /// The weight goal from the local overrides only; the start defaults
    /// to the FIRST local weigh-in (design D6). `nil` without a target.
    public static func standaloneWeightGoal(
        targetOverrideKg: Double?,
        startOverrideKg: Double?,
        localEntries: [WeightEntry]
    ) -> EffectiveWeightGoal? {
        guard let targetOverrideKg else { return nil }
        let firstKg = localEntries.min { $0.loggedAt < $1.loggedAt }?.weightKg
        return GoalResolution.weight(
            targetSource: .override(targetOverrideKg),
            startOverrideKg: startOverrideKg ?? firstKg,
            garminTargetGrams: nil,
            garminStartGrams: nil,
            garminRateGramsPerWeek: nil,
            garminChangeType: nil
        )
    }

    /// The water total for the day containing `date`: the sum of this
    /// phone's drinks (no Garmin total, no outbox).
    public static func standaloneWaterTotalML(entries: [HydrationEntry], on date: Date, calendar: Calendar = .current) -> Double {
        HydrationHistory.total(for: entries, on: date, calendar: calendar)
    }

    /// The water goal: the local override, else 2000 ml.
    public static func standaloneWaterGoal(overrideML: Double?) -> EffectiveWaterGoal {
        GoalResolution.water(source: overrideML.map { GoalSource.override($0) } ?? .garmin, garminGoalML: nil)
    }
}
