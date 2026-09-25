// FoodTag+Sport.swift
//
// add-sport-and-body-achievements design D3: the one tag the sport & body
// badges need -- `sport.carbRich` (banán, ovesná kaše, energetický gel,
// rohlík, chléb, těstoviny, rýže, müsli, energy bar, iontový nápoj, datle,
// med). It is ONLY a fallback for "Fuelled Up": an entry whose carbohydrate
// grams are known is judged by the grams (>= 30 g), never by this tag; the
// tag decides only when an entry's carbs are unknown (a Garmin day-log line
// without macros, an OFF product without nutrition).
//
// Declared here rather than in the shared `FoodTag.swift`
// (add-gamification-signals D1: each wave-2 change owns its own tags); the
// phrases that assign it live in `FoodTagRules+Sport.swift`.
//
// Depends on: FoodTag. Depended on by: FoodTagRules+Sport, Gamification's
// SportRules (Features/SportBody/).

import Foundation

extension FoodTag {
    public static let sportPrefix = "sport."

    /// A food that is mostly quick carbohydrate -- a sensible pre-run snack.
    public static let sportCarbRich = FoodTag("sport.carbRich")

    /// Every sport tag, for tests and diagnostics.
    public static let allSport: [FoodTag] = [.sportCarbRich]
}
