// AppEnvironment+TrainingNutrition.swift
//
// add-winter-arc-nutrition-and-rewards: where the training plan reaches the
// food and reward sides -- ONLY in the training experience. Food-first (and
// standalone, which is always food-first) gets `nil` / `false` / `[]` from
// every accessor here, so nothing it shows or judges changes.
//
//   - `wireTrainingNutrition()` (end of AppEnvironment.init): the providers
//     GamificationEngine (goal status by the carb band) and FeatureHost
//     (training experience on, reward facts, paused fasting days) read;
//   - `trainingFuelTarget(for:)`: the Today summary's plan-day targets;
//     the weight fallback is the latest weigh-in when the plan has no
//     `athlete.weightKg`;
//   - `isFastingPausedByPlan(on:)` / `fastingPausedDaysByPlan(now:)`: the
//     fasting surfaces (home card note, confirm-screen note, history,
//     reminders) -- the owner's fasting settings are never changed, the
//     plan only pauses the judgement and the nags for its "off" days.
//
// The adapters themselves are TrainingNutritionBridge.swift.
//
// add-training-gamification-and-150-levels D6, D10: it also wires the plan's
// facts for the training XP into FeatureHost (TrainingPlanSignalsBridge,
// with the plan file's extra fields read from the cached bytes), and runs
// the gamification features right after a training event is recorded, so a
// check-in's XP shows at once.
//
// Depends on: AppEnvironment, TrainingModel (+TrainingNutritionBridge),
// WeightLoader. Depended on by: AppEnvironment.init/syncNotifications,
// TodayView, the fasting views.

import Foundation
import FoodLogCore
import AppearanceKit
import Gamification
import TrainingCore

extension AppEnvironment {
    /// Sets the plan providers; called once at the end of `init`.
    func wireTrainingNutrition() {
        gamificationEngine.fuelTargetProvider = { [weak self] day in
            guard let self, self.experience == .training else { return nil }
            return self.training.fuelTarget(forNutritionDay: day, fallbackWeightKg: self.weightLoader.latest?.weightKg)
        }
        guard let featureHost = gamificationEngine.featureHost else { return }
        featureHost.isTrainingExperienceProvider = { [weak self] in
            self?.experience == .training
        }
        featureHost.trainingSignalsProvider = { [weak self] now in
            self?.training.rewardSignals(now: now)
        }
        featureHost.fastingPausedDaysProvider = { [weak self] now in
            self?.fastingPausedDaysByPlan(now: now) ?? []
        }
        // add-training-gamification-and-150-levels D6: the plan's facts for
        // the training XP. FeatureHost asks only in the training experience.
        featureHost.trainingPlanSignalsProvider = { [weak self] now -> TrainingPlanSignals? in
            guard let self else { return nil }
            let extras = await VaultServices.shared.projectionStore.cachedRewardExtras()
            return self.training.planSignals(now: now, extras: extras)
        }
        // D10: after the plan reloads for a recorded event (TrainingModel's
        // own hook, kept), run the features so the XP shows at once.
        let events = TrainingEventsService.shared
        let reloadTraining = events.onChange
        events.onChange = { [weak self] in
            await reloadTraining?()
            await self?.gamificationEngine.runFeaturesAfterTrainingEvent()
        }
    }

    /// The plan day's food targets for the local day of `date`, in the
    /// training experience only.
    func trainingFuelTarget(for date: Date) -> FuelDayTarget? {
        guard experience == .training else { return nil }
        return training.fuelTarget(for: date, fallbackWeightKg: weightLoader.latest?.weightKg)
    }

    /// The plan paused fasting on the local day of `date` (training
    /// experience only).
    func isFastingPausedByPlan(on date: Date = Date()) -> Bool {
        guard experience == .training else { return false }
        return training.isFastingPaused(on: date)
    }

    /// The last 42 local days the plan paused fasting on (training
    /// experience only).
    func fastingPausedDaysByPlan(now: Date = Date()) -> Set<Date> {
        guard experience == .training else { return [] }
        return training.fastingPausedDays(days: 42, now: now)
    }

    /// The fasting window the reminders follow: none on a day the plan
    /// paused fasting (they come back on the next foreground of an
    /// "allowed" day, when notifications are re-planned).
    var fastingScheduleForReminders: FastingSchedule? {
        isFastingPausedByPlan() ? nil : preferences.activeFastingSchedule
    }
}
