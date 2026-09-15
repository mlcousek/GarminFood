// TodaySummary.swift
//
// The one piece of data the home screen's hero is built around: today's
// consumed calories against today's goal, read from Garmin's daily food log
// (`GET /nutrition-service/food/logs/{date}`, confirmed live 2026-09-14 --
// its `dailyNutritionContent.calories` is the REAL consumed total; the
// legacy `usersummary-service` field is disconnected from nutrition and must
// never be used for this, per docs/garmin-food-log-contract.md).
//
// Deliberately a small value type plus an `@Observable` loader rather than
// more properties on `AppEnvironment`: the hero re-renders from this alone,
// and the loader owns the "last known good" semantics -- a failed refresh
// keeps showing the previous number (marked stale) instead of blanking the
// biggest element on the screen, per config.yaml's "states... designed on
// purpose" principle.

import Foundation
import Observation
import GarminKit
import FoodLogCore

struct TodaySummary: Equatable, Sendable {
    let consumedCalories: Double
    let goalCalories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fetchedAt: Date

    var remainingCalories: Double? {
        guard let goalCalories else { return nil }
        return goalCalories - consumedCalories
    }

    /// 0...1 (clamped) share of the goal consumed; `nil` when there is no goal
    /// to measure against, so the UI can show a plain count instead of a bar
    /// that would otherwise be lying.
    var goalFraction: Double? {
        guard let goalCalories, goalCalories > 0 else { return nil }
        return min(max(consumedCalories / goalCalories, 0), 1)
    }

    enum GoalState { case under, onTarget, over, noGoal }

    /// "On target" is +/-10% -- a narrower band than GamificationEngine's
    /// 15% goal-met tolerance on purpose: this is a visual cue on a live
    /// number, not an XP award, so it can afford to be stricter.
    var goalState: GoalState {
        guard let goalCalories, goalCalories > 0 else { return .noGoal }
        let ratio = consumedCalories / goalCalories
        if ratio > 1.10 { return .over }
        if ratio >= 0.90 { return .onTarget }
        return .under
    }
}

@MainActor
@Observable
final class TodaySummaryLoader {
    private let client: GarminClient

    private(set) var summary: TodaySummary?
    private(set) var isLoading = false
    /// True when the last refresh failed and `summary` is a previous value
    /// still being shown. Never blanks the hero; just annotates it.
    private(set) var isStale = false

    init(client: GarminClient) {
        self.client = client
    }

    func refresh(now: Date = Date()) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let dateString = NutritionDate.string(from: now)
        do {
            guard let log = try await client.dailyFoodLog(date: dateString) else {
                // A 200 with no log for today is "nothing logged yet", not an
                // error (GarminKit returns nil for that case) -- show zero
                // honestly rather than a stale yesterday.
                summary = TodaySummary(
                    consumedCalories: 0,
                    goalCalories: summary?.goalCalories,
                    protein: 0, carbs: 0, fat: 0,
                    fetchedAt: now
                )
                isStale = false
                return
            }
            let content = log.dailyNutritionContent
            let goals = log.dailyNutritionGoals
            summary = TodaySummary(
                consumedCalories: content?.calories ?? 0,
                goalCalories: goals?.adjustedCalories ?? goals?.calories,
                protein: content?.protein,
                carbs: content?.carbs,
                fat: content?.fat,
                fetchedAt: now
            )
            isStale = false
        } catch {
            // Auth failures are surfaced elsewhere (AuthBannerView, loudly);
            // here the only job is to not destroy the number already shown.
            isStale = summary != nil
        }
    }
}
