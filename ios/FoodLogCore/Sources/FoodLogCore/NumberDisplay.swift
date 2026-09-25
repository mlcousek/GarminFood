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
// Locale-aware (add-localization design.md D7, task 6.1): a value with
// decimals is formatted with `FloatingPointFormatStyle` in the given locale
// (default: the app's current one), so a Czech phone reads "0,70" where an
// English one reads "0.70". Grouping is off, so "10000" stays "10000" in
// both (a grouped "10 000" would be new text on every screen, and a limit
// in a validation message must read like what can be typed). Whole numbers
// keep the "%.0f" path: its digits are the same in English and Czech, and
// it prints any finite Double, however large, where `Int(_:)` traps. For
// English, output matches the old "%.Nf" helpers ("2", "0.70", "1.5") for
// ordinary values, but not on a decimal tie: the format style rounds the
// value's shortest decimal form half-to-even ("1.015" -> "1.02", "0.25" ->
// "0.2" at one digit), where "%.Nf" rounded the exact binary value (1.015
// is stored just below it -> "1.01"). Callers that must agree with another
// rounding (e.g. a spoken label) should round the value themselves first.
// Input goes the other way through
// `DecimalInput`, which accepts both "," and ".".
//
// Pure and Foundation-only; tested in NumberDisplayTests
// (LogQuantityTests.swift), with pinned `en` and `cs` output. Used by
// `Serving.displayLabel`, `MealDashboard.servingDescription`,
// `ServingQuantityInput.amountLabel` and the app target's `Double`
// formatting extension (GarminFood/DesignSystem/NumberFormatting.swift).

import Foundation

public enum NumberDisplay {
    /// Shown for a value that has no sensible text (NaN or infinity).
    public static let placeholder = "–"

    /// A quantity: a whole number without decimals ("2"), anything else
    /// with exactly `fractionDigits` decimals ("0.70" at 2, "1.5" at 1;
    /// "0,70" / "1,5" in Czech) -- the convention every screen's own copy
    /// already used.
    public static func quantity(_ value: Double, fractionDigits: Int = 2, locale: Locale = .current) -> String {
        guard value.isFinite else { return placeholder }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return integerText(value)
        }
        let digits = max(0, fractionDigits)
        return decimalText(value, fractionDigits: digits...digits, locale: locale)
    }

    /// `value` with at most `maxFractionDigits` decimals and no trailing
    /// zeros ("150", "12.5", "0.333"; "12,5" in Czech) -- for a measured
    /// amount such as grams, where "150.0" would be noise.
    public static func trimmed(_ value: Double, maxFractionDigits: Int, locale: Locale = .current) -> String {
        guard value.isFinite else { return placeholder }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return integerText(value)
        }
        return decimalText(value, fractionDigits: 0...max(0, maxFractionDigits), locale: locale)
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

    /// A finite, NON-integral `value` in `locale`: its decimal separator,
    /// no grouping, `fractionDigits` decimals. Only values with a
    /// fractional part get here, so |value| < 2^52 -- far from anything a
    /// format style could mishandle. A negative value that rounds to zero
    /// is formatted unsigned ("0.00", not "-0.00"), matching the whole
    /// number path's "-0.0 reads 0".
    private static func decimalText(_ value: Double, fractionDigits: ClosedRange<Int>, locale: Locale) -> String {
        let scale = pow(10, Double(fractionDigits.upperBound))
        let signed = (value * scale).rounded() == 0 ? abs(value) : value
        let style = FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(fractionDigits))
            .grouping(.never)
        return style.format(signed)
    }
}
