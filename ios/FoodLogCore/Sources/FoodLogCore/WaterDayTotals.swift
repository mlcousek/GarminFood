// WaterDayTotals.swift
//
// ONE answer to "how much water on day X" for every screen (review note 17).
// Before this, Today/Progress showed `HydrationLoader.todayTotalML` --
// Garmin's cached day total plus drinks Garmin can't include yet
// (`WeightAndWaterOverview.waterTotalML`, design D4) -- while Trends' chart,
// its water streak and the Progress Trends card summed only the drinks
// logged IN THIS APP (`HydrationHistory.total`). In Garmin mode water logged
// on the watch or in Connect counted on one screen and not the other.
//
// `total(on:)` is exactly the resolution Today uses, for any day:
//   - standalone: this phone's drinks (`standaloneWaterTotalML`);
//   - Garmin mode: `waterTotalML` -- Garmin's cached total for that day
//     (`GarminHealthCacheStore` keeps the last `hydrationDaysKept` days the
//     app read) plus undelivered drinks/corrections; a day Garmin was never
//     read for falls back to the app's own outbox entries, the same fallback
//     Today uses offline.
//
// `streak(goalML:today:)` counts over those same totals and treats an
// unfinished TODAY as in progress, like the food streak: it counts back from
// yesterday and adds today only once today's goal is already met, so it no
// longer reads 0 every morning.
//
// Pure value type; built by the app's `HydrationLoader` from what it already
// holds. Tested in FoodLogCoreTests/WaterDayTotalsTests.swift.

import Foundation
import GarminKit

public struct WaterDayTotals {
    public let isStandalone: Bool
    public let snapshot: GarminHealthSnapshot
    public let outboxEntries: [HydrationOutboxEntry]
    public let localEntries: [HydrationEntry]
    public let calendar: Calendar

    public init(
        isStandalone: Bool,
        snapshot: GarminHealthSnapshot,
        outboxEntries: [HydrationOutboxEntry],
        localEntries: [HydrationEntry],
        calendar: Calendar = .current
    ) {
        self.isStandalone = isStandalone
        self.snapshot = snapshot
        self.outboxEntries = outboxEntries
        self.localEntries = localEntries
        self.calendar = calendar
    }

    /// The water total (ml) for the calendar day containing `date` -- the
    /// number Today shows for today.
    public func total(on date: Date) -> Double {
        if isStandalone {
            return WeightAndWaterOverview.standaloneWaterTotalML(entries: localEntries, on: date, calendar: calendar)
        }
        return WeightAndWaterOverview.waterTotalML(snapshot: snapshot, outboxEntries: outboxEntries, on: date, calendar: calendar)
    }

    /// Consecutive days meeting `goalML`, over `total(on:)`, with today in
    /// progress (see the header and `HydrationHistory.streak(goalML:on:calendar:total:)`).
    public func streak(goalML: Double, today: Date = Date()) -> Int {
        HydrationHistory.streak(goalML: goalML, on: today, calendar: calendar, total: total(on:))
    }
}
