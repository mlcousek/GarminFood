// StandaloneSignals.swift
//
// Gamification signals in standalone mode (add-standalone-mode D11, task
// 7.1). A standalone install has no activities and no active kcal, and its
// weight and water live only in this phone's stores. `SignalsInput.
// standalone(localWeighIns:calendar:)` removes every Garmin-derived source
// from the input BEFORE `DaySignalsBuilder` runs, so:
//   - `hasActivities` is false and `activeKcal` nil on every day -- even if
//     the activity cache still holds days from a time the phone was
//     Garmin-connected -- and rotation/eligibility therefore never offers a
//     challenge, bingo square, boss or journey whose `DataRequirement` is
//     `.activities` (they already filter on it);
//   - water is the phone's own total (no cached Garmin total), weight the
//     phone's own weigh-ins.
// Food, water, weight, fasting and note signals work unchanged.
//
// `SignalAvailability.hasFoodLog` is the mode-neutral name design D11 asks
// for: a day log was read for the day, from Garmin or from the local food
// log (`DayLogLoader` stores a digest of whichever reader answered).
//
// Depended on by: the app's FeatureHost (standalone snapshot).
// Tests: StandaloneSignalsTests; Gamification's StandaloneAvailabilityTests.

import Foundation

extension SignalAvailability {
    /// A day log (digest) exists for the day -- Garmin's or the local one.
    public var hasFoodLog: Bool { hasGarminLog }
}

extension SignalsInput {
    /// This input with every Garmin-only source removed and the weigh-ins
    /// taken from `localWeighIns` instead of Garmin's cache.
    public func standalone(localWeighIns: [WeightEntry], calendar: Calendar) -> SignalsInput {
        var copy = self
        copy.activityDays = []
        copy.garminWaterByDay = [:]
        copy.weighInKgByDay = Self.weighInKgByDay(localEntries: localWeighIns, calendar: calendar)
        return copy
    }

    /// The last local weigh-in (by time) of each calendar day, kilograms.
    public static func weighInKgByDay(localEntries: [WeightEntry], calendar: Calendar) -> [String: Double] {
        var latest: [String: WeightEntry] = [:]
        for entry in localEntries {
            let day = NutritionDate.string(from: entry.loggedAt, calendar: calendar)
            if let current = latest[day], current.loggedAt >= entry.loggedAt { continue }
            latest[day] = entry
        }
        return latest.mapValues(\.weightKg)
    }
}
