// NumberDisplay.swift
//
// Non-trapping number-to-text for everything the UI shows as a quantity or
// a rounded whole number. Exists because every screen used to format with
// `String(Int(value))` / `Int(value.rounded())`, and `Int(_:)` TRAPS (a
// crash, not an error) for a non-finite value or one outside Int's range
// (about 9.2e18). A single absurd quantity typed into the confirm screen
// was persisted, then crashed the Today screen on every launch as soon as
// it was rendered. `LogQuantity` now stops such a quantity from being
// logged at all; this makes the display side safe regardless, including
// for anything already stored or read from Garmin.
//
// Output is identical to the old helpers for every value they handled
// ("2", "0.70", "1.5"), so no screen's text changes. Pure and Foundation-
// only; tested in NumberDisplayTests. Used by `Serving.displayLabel`,
// `MealDashboard.servingDescription` and the app target's `Double`
// formatting extension (GarminFood/DesignSystem/NumberFormatting.swift).

import Foundation

public enum NumberDisplay {
    /// Shown for a value that has no sensible text (NaN or infinity).
    public static let placeholder = "–"

    /// A quantity: a whole number without decimals ("2"), anything else
    /// with exactly `fractionDigits` decimals ("0.70" at 2, "1.5" at 1) --
    /// the convention every screen's own copy already used.
    public static func quantity(_ value: Double, fractionDigits: Int = 2) -> String {
        guard value.isFinite else { return placeholder }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return integerText(value)
        }
        return String(format: "%.\(max(0, fractionDigits))f", value)
    }

    /// `value` rounded to the nearest whole number ("290" for 289.6), the
    /// text `Int(value.rounded())` used to produce, without trapping.
    public static func whole(_ value: Double) -> String {
        guard value.isFinite else { return placeholder }
        return integerText(value.rounded())
    }

    /// An already-integral, finite `value` as digits. "%.0f" prints any
    /// finite Double's digits, however large, where `Int(_:)` would trap.
    /// Zero is special-cased so `-0.0` reads "0", as `Int(-0.0)` did.
    private static func integerText(_ value: Double) -> String {
        guard value != 0 else { return "0" }
        return String(format: "%.0f", value)
    }
}
