// MealTypeDefaulting.swift
//
// Defaults `MealType` from time of day (food-log-entry spec's "Meal type
// and date default sensibly but remain editable" requirement, task 16.1).
// Deliberately a pure function of a `Date` + `Calendar` -- no network call,
// so it can run before the confirm screen even appears and never violates
// the flow's "zero network wait" requirement.
//
// Windows are fixed, generic local-time buckets, NOT read from Garmin's
// per-account `Meal.startTime`/`endTime` (that data only exists per already
// -logged day, via `dailyFoodLog`, which is itself a network call this
// default must not depend on). This is a deliberate simplification: the
// default only ever needs to be "usually right, always editable" per the
// spec, not authoritative.
//
// `.dinner` covers both the evening window and the overnight/very-early
// hours (documented in the file rather than left as an implicit "default"
// branch) since a log made at 2am is far more likely a late dinner/snack
// mislabelled by the clock than a "breakfast" by the literal hour.

import Foundation
import GarminKit

public enum MealTypeDefaulting {
    public static func defaultMealType(for date: Date = Date(), calendar: Calendar = .current) -> MealType {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snacks
        default: return .dinner // 18:00-23:59 and 0:00-3:59
        }
    }
}
