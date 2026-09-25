// SpokenUnits.swift
//
// Weights, volumes and energy as VoiceOver should READ them: the unit spelled out
// and agreeing with the number ("1 kilogram", "2 kilogramy", "83,9
// kilogramu", "250 mililitrů"). Exists because the on-screen symbols
// ("kg", "ml") are fine to look at but VoiceOver reads a bare symbol
// oddly, and Czech needs the unit's case to follow the count -- one/few/
// many/other for whole numbers, and the genitive singular for any decimal
// ("83,9 kilogramu") -- which a single "%@ kilograms" string can't express
// (add-localization task 6.4, glossary "Units").
//
// Whole numbers go through catalog plural variations (`%lld`); a value
// with a decimal part uses its own "%@ ..." key whose Czech form is the
// decimal one. The number itself comes from `NumberDisplay` (FoodLogCore),
// so it carries the locale's decimal separator and never traps. Used by
// the weight and water accessibility labels and chart summaries, and by
// `MacroBadge.calories` (every "290 kcal" pill). Screen text keeps the
// symbols.

import Foundation
import FoodLogCore

enum SpokenUnits {
    /// "83.9 kilograms" / "83,9 kilogramu"; "80 kilograms" / "80 kilogramů".
    static func kilograms(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if let whole = wholeCount(rounded) {
            return String(localized: "\(whole) kilograms", comment: "VoiceOver: a weight in whole kilograms. Plural.")
        }
        let number = NumberDisplay.quantity(rounded, fractionDigits: 1)
        return String(localized: "\(number) kilograms", comment: "VoiceOver: a weight with a decimal part, e.g. 83.9 (Czech: genitive singular, 83,9 kilogramu).")
    }

    /// "250 milliliters" / "250 mililitrů" -- water is always logged in
    /// whole milliliters.
    static func milliliters(_ value: Double) -> String {
        if let whole = wholeCount(value.rounded()) {
            return String(localized: "\(whole) milliliters", comment: "VoiceOver: a water amount in whole milliliters. Plural.")
        }
        return String(localized: "\(NumberDisplay.whole(value)) milliliters", comment: "VoiceOver: a water amount too large for a whole-number count (practically never).")
    }

    /// "290 kilocalories" / "290 kilokalorií", "1 kilokalorie" -- energy is
    /// always shown rounded to a whole number (`wholeNumberText`), and so
    /// is read that way.
    static func kilocalories(_ value: Double) -> String {
        if let whole = wholeCount(value.rounded()) {
            return String(localized: "\(whole) kilocalories", comment: "VoiceOver: an energy amount in whole kilocalories. Plural.")
        }
        return String(localized: "\(NumberDisplay.whole(value)) kilocalories", comment: "VoiceOver: an energy amount, e.g. 290 (Czech: 290 kilokalorií).")
    }

    /// `value` as an `Int` when it is a whole number that fits one; `nil`
    /// for a decimal, a non-finite or an absurdly large value (`Int(_:)`
    /// would trap on the last two).
    private static func wholeCount(_ value: Double) -> Int? {
        guard value.isFinite, value.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
        return Int(exactly: value)
    }
}
