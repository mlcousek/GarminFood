// TrainingNutritionBridge.swift
//
// add-winter-arc-nutrition-and-rewards: the app's one small adapter between
// the training plan (TrainingCore) and the food and reward sides
// (FoodLogCore, Gamification), which never import TrainingCore. Each
// accessor only copies values across -- every rule lives in a package and
// is tested there:
//   - `fuelTarget(...)`: TrainingCore's `DayFuelTargets` for a nutrition
//     day -> FoodLogCore's `FuelDayTarget` (the Today summary, goal status);
//   - `fastingPausedDays(...)` / `isFastingPaused(on:)`: the plan days with
//     `fuel.fasting == "off"`, as the local start-of-day dates fasting is
//     judged by (FastingDayEvaluator's `pausedDays`);
//   - `rewardSignals(...)`: TrainingCore's `TrainingRewardFacts` ->
//     Gamification's `TrainingSignals`.
// All return nothing without a loaded projection. The CALLERS decide whether
// the training experience is on (`AppEnvironment.experience`); food-first
// never asks, so it never changes.
//
// add-daily-checkin-and-pain-mode: the projection carries `fuel` on EVERY
// day now, and a day outside the written weeks (or with no plan at all) is
// a day skeleton -- so each accessor looks the day up with
// `TrainingSnapshot.day` / `fuelTargets(on:)` and none of them asks for a
// plan any more.
//
// Nutrition days are the phone's local `yyyy-MM-dd` (NutritionDate), the
// same calendar day the plan names in its own time zone for every day the
// owner actually lives in one zone -- a plan day is matched by its date
// string, never by an instant.
//
// Depends on: TrainingModel, TrainingCore, FoodLogCore, Gamification.
// Depended on by: AppEnvironment (providers for GamificationEngine and
// FeatureHost), TodayView (fuel summary), the fasting surfaces.

import Foundation
import TrainingCore
import FoodLogCore
import Gamification

extension TrainingModel {
    /// The plan day's food targets for a nutrition day (`yyyy-MM-dd`).
    func fuelTarget(forNutritionDay day: String, fallbackWeightKg: Double? = nil) -> FuelDayTarget? {
        guard let date = LocalDate(day),
              let targets = source.snapshot?.fuelTargets(on: date, fallbackWeightKg: fallbackWeightKg)
        else { return nil }
        return FuelDayTarget(
            carbsMinG: targets.carbsMinG,
            carbsMaxG: targets.carbsMaxG,
            proteinG: targets.proteinG,
            isCarbLoad: targets.isCarbLoad,
            hasTrainingSessions: targets.hasTrainingSessions,
            isFastingPaused: targets.isFastingPaused
        )
    }

    /// The plan day's food targets for the local calendar day of `date`.
    func fuelTarget(for date: Date, fallbackWeightKg: Double? = nil) -> FuelDayTarget? {
        fuelTarget(forNutritionDay: NutritionDate.string(from: date), fallbackWeightKg: fallbackWeightKg)
    }

    /// Whether the plan paused fasting on the local day of `date`.
    func isFastingPaused(on date: Date) -> Bool {
        fuelTarget(for: date)?.isFastingPaused ?? false
    }

    /// The last `days` local days (today first) the plan paused fasting
    /// on, as start-of-day dates.
    func fastingPausedDays(days: Int = 42, now: Date = Date(), calendar: Calendar = .current) -> Set<Date> {
        guard let snapshot = source.snapshot else { return [] }
        let today = calendar.startOfDay(for: now)
        var paused = Set<Date>()
        for offset in 0..<max(0, days) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let date = LocalDate(NutritionDate.string(from: day, calendar: calendar)),
                  snapshot.day(date)?.fuel?.isFastingOff == true
            else { continue }
            paused.insert(calendar.startOfDay(for: day))
        }
        return paused
    }

    /// The plan's reward facts in Gamification's shape.
    func rewardSignals(now: Date = Date()) -> TrainingSignals? {
        guard let snapshot = source.snapshot else { return nil }
        let today = self.today(now: now)
        let facts = TrainingRewardFacts.build(snapshot: snapshot, today: today)
        return TrainingSignals(
            today: today.description,
            currentWeek: ISOWeek(containing: today).description,
            days: facts.days.map {
                TrainingSignals.Day(
                    day: $0.date.description,
                    checkedIn: $0.checkedIn,
                    honestLightFollowed: $0.honestLightFollowed,
                    strengthSessionsDone: $0.strengthSessionsDone,
                    habitTicks: $0.habitTicks
                )
            },
            weeks: facts.weeks.map {
                TrainingSignals.Week(
                    week: $0.week.description,
                    isClosed: $0.isClosed,
                    keptWithinPlan: $0.keptWithinPlan,
                    strengthSessionsDone: $0.strengthSessionsDone
                )
            }
        )
    }
}
