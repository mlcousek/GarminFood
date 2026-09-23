// DecimalInput.swift
//
// The one parser for a number the user TYPED into a text field (custom
// food editor, meal-preset ingredient quantity, weigh-in, water amount and
// goal). Exists because the owner's phone is set to Czech, whose decimal
// pad types a comma: `Double("0,5")` is `nil`, so "0,5" was silently
// rejected -- or, for an optional macro field, silently dropped -- in every
// editor that parsed with `Double(_:)` directly. `AddWeightSheet` already
// normalised the comma by hand; this replaces that one-off with a single
// tested rule every screen shares.
//
// Deliberately stricter than `Double(_:)` on everything else: only an
// optional sign, digits and at most one "." or "," separator are accepted,
// so "1e5", "inf", "nan" or "0x10" -- which `Double(_:)` happily parses --
// can never become a quantity. Range checks (> 0, an upper bound) stay with
// each caller, since they differ per field.
//
// Pure, Foundation-only; tested in DecimalInputTests. Depended on by the app
// target's editors only.

import Foundation

public enum DecimalInput {
    /// The number in `text`, accepting either "." or "," as the decimal
    /// separator and ignoring surrounding whitespace; `nil` for empty text,
    /// anything that isn't a plain decimal number, or a non-finite result.
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var body = Substring(trimmed)
        var isNegative = false
        if let first = body.first, first == "-" || first == "+" {
            isNegative = first == "-"
            body = body.dropFirst()
        }

        var digitCount = 0
        var separatorCount = 0
        var normalized = ""
        for character in body {
            switch character {
            case "0"..."9":
                digitCount += 1
                normalized.append(character)
            case ".", ",":
                separatorCount += 1
                normalized.append(".")
            default:
                return nil
            }
        }
        guard digitCount > 0, separatorCount <= 1 else { return nil }
        // "5." and ".5" are fine as typed; make both explicit rather than
        // rely on `Double(_:)` accepting a bare separator at either end.
        if normalized.hasPrefix(".") { normalized = "0" + normalized }
        if normalized.hasSuffix(".") { normalized += "0" }
        if isNegative { normalized = "-" + normalized }

        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
