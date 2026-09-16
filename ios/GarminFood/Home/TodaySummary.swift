// TodaySummary.swift
//
// The one piece of data the home screen's hero is built around: today's
// consumed calories against today's goal, read from Garmin's daily food log
// (`GET /nutrition-service/food/logs/{date}`, confirmed live 2026-09-14 --
// its `dailyNutritionContent.calories` is the REAL consumed total; the
// legacy `usersummary-service` field is disconnected from nutrition and must
// never be used for this, per docs/garmin-food-log-contract.md).
//
// The `TodaySummary` value type itself, and its goalFraction/goalState/
// remainingCalories logic, now live in FoodLogCore (TodaySummary.swift
// there) so they're covered by real unit tests (TodaySummaryTests.swift) --
// this file kept a duplicate struct only long enough to get the redesign
// building; that duplication is why it's gone now. What's left here is
// purely the @Observable, GarminClient-calling loader, which can't be
// unit-tested without a device/toolchain anyway.

import Foundation
import Observation
import GarminKit
import FoodLogCore

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
