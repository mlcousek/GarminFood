// ServingAmount.swift
//
// Lets the owner type a food's amount in grams (or ml) whatever shape its
// serving has. Owner report (2026-09-24): "Sometimes there is 100 and I
// write 150 for 150 grams, but sometimes there is 100 and under it 1, so I
// need to write 1,5 for 150 grams." Both are the SAME 100 g of food, just
// described two ways by Garmin/FatSecret -- a live read-only
// `food/search?searchExpression=tvaroh` (2026-09-24) returns, for one food:
//
//   servingUnit "100g", numberOfUnits 1   (also "100г", "100ml", "100мл")
//   servingUnit "g",    numberOfUnits 100 (also "G", "ml", "ML")
//
// and other foods carry "serving (118 g)" / "serving (50 g)" (size in
// parentheses), "G" x 30, or sizes with no metric weight at all ("medium
// (7\" to 7-7/8\" long)", "can (12 fl oz)", "1/4 cup dry", "oz"). The
// confirm screen used to offer grams only when the unit was literally "g"/
// "ml", so the "100g" shape fell back to a servings multiplier.
//
// Garmin's wire format does NOT change: a log still sends `servingId` +
// `servingQty` (= `numberOfUnits` here, a multiplier of ONE WHOLE serving,
// see LogEntryConfirmView's `quantity`). Grams are converted to that
// multiplier here, and only at the input boundary -- remembered amounts
// (`ServingDefaults`, quick-pick `initialQuantity`, outbox entries) stay
// multipliers.
//
// Rounding: a gram-derived multiplier is rounded to `quantityFractionDigits`
// (3) decimals. Garmin stores `servingQty` as a 32-bit float (read back as
// 0.699999988079071 for 0.7, 2026-09-24 read of the owner's own log), about
// 7 significant digits: 3 decimals survive exactly below 8192, and above it
// (float32 step ~0.00098) the read-back error is still under half that, so
// every quantity up to `LogQuantity.maximum` stays inside `LoggedFood.
// matchesQuantity`'s 0.001 tolerance (pinned by ServingAmountTests). On a
// 100 g serving that is 0.1 g resolution.
//
// Pure, Foundation-only; tested in ServingAmountTests. Used by the app
// target's `ServingQuantityField` (confirm screen, edit sheet) and the
// meal-preset ingredient row.

import Foundation

/// The two metric quantities a user can type directly.
public enum MetricUnit: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case grams
    case milliliters

    /// "g" / "ml" -- what the input field shows next to the number.
    public var symbol: String {
        switch self {
        case .grams: return "g"
        case .milliliters: return "ml"
        }
    }
}

/// How the quantity field is being typed: an absolute metric amount
/// ("150" g), or a multiplier of the serving ("1.5" x 100 g). Remembered
/// across screens as a preference in the app target (`AppPreferences`).
public enum QuantityInputMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case amount
    case servings
}

/// The known metric size of ONE whole serving (what `numberOfUnits`/
/// `servingQty == 1` logs), e.g. 100 g for both "100g" x 1 and "g" x 100.
public struct MetricServingSize: Sendable, Equatable, Hashable {
    public let unit: MetricUnit
    /// Grams (or ml) in one serving; always finite and > 0.
    public let amountPerServing: Double

    public init?(unit: MetricUnit, amountPerServing: Double) {
        guard amountPerServing.isFinite, amountPerServing > 0 else { return nil }
        self.unit = unit
        self.amountPerServing = amountPerServing
    }

    /// From a serving's raw unit text and `numberOfUnits`. `nil` when the
    /// unit carries no gram/ml size ("medium", "cup", "oz", "can (12 fl
    /// oz)") -- there is no honest conversion for those without the food's
    /// density or piece weight, which Garmin doesn't provide.
    public init?(unit unitText: String?, numberOfUnits: Double?) {
        guard let unitText,
              let perUnit = Self.metricAmount(inUnitText: unitText)
        else { return nil }
        let units = numberOfUnits ?? 1
        guard units.isFinite, units > 0 else { return nil }
        self.init(unit: perUnit.unit, amountPerServing: perUnit.amount * units)
    }

    public init?(serving: Serving) {
        self.init(unit: serving.unit, numberOfUnits: serving.numberOfUnits)
    }

    /// One serving is exactly 1 g/ml ("g" x 1): the multiplier already IS
    /// the gram amount, so there is nothing to choose between.
    public var isPerUnit: Bool {
        abs(amountPerServing - 1) < 1e-9
    }

    /// The multiplier logging `amount` g/ml, rounded to
    /// `ServingQuantityInput.quantityFractionDigits` decimals.
    public func quantity(forAmount amount: Double) -> Double {
        ServingQuantityInput.rounded(amount / amountPerServing, fractionDigits: ServingQuantityInput.quantityFractionDigits)
    }

    /// The g/ml a multiplier logs.
    public func amount(forQuantity quantity: Double) -> Double {
        quantity * amountPerServing
    }

    // MARK: Unit-text parsing

    /// Metric unit words, lowercased, with how many g/ml one of them is.
    /// Czech and Cyrillic spellings appear in real FatSecret data ("100г",
    /// "100мл").
    private static let tokens: [String: (unit: MetricUnit, factor: Double)] = [
        "g": (.grams, 1), "gr": (.grams, 1), "gram": (.grams, 1), "grams": (.grams, 1),
        "gramy": (.grams, 1), "gramů": (.grams, 1), "г": (.grams, 1), "гр": (.grams, 1),
        "kg": (.grams, 1000), "кг": (.grams, 1000),
        "ml": (.milliliters, 1), "milliliter": (.milliliters, 1), "milliliters": (.milliliters, 1),
        "millilitre": (.milliliters, 1), "millilitres": (.milliliters, 1), "мл": (.milliliters, 1),
        "l": (.milliliters, 1000), "liter": (.milliliters, 1000), "liters": (.milliliters, 1000),
        "litre": (.milliliters, 1000), "litres": (.milliliters, 1000), "litr": (.milliliters, 1000),
        "л": (.milliliters, 1000),
    ]

    /// The g/ml ONE unit of `unitText` stands for: "g" -> 1 g, "100g" /
    /// "100 g" -> 100 g, "serving (118 g)" -> 118 g, "0,5 l" -> 500 ml.
    /// `nil` for anything else.
    static func metricAmount(inUnitText unitText: String) -> (unit: MetricUnit, amount: Double)? {
        let lowered = unitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return nil }
        if let whole = numberAndUnit(lowered) { return whole }
        // "serving (118 g)": FatSecret's way of stating a named serving's
        // weight. Only the LAST parenthesised part, and only when all of
        // it is "<number> <metric unit>".
        if let open = lowered.lastIndex(of: "("),
           let close = lowered.lastIndex(of: ")"),
           open < close {
            let inner = lowered[lowered.index(after: open)..<close]
            return numberAndUnit(String(inner))
        }
        return nil
    }

    /// "<optional number><optional spaces><metric unit word>", nothing else.
    private static func numberAndUnit(_ text: String) -> (unit: MetricUnit, amount: Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits: ClosedRange<Character> = "0"..."9"
        let numberPart = trimmed.prefix(while: { character in
            character == "." || character == "," || digits.contains(character)
        })
        let unitPart = trimmed.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces)
        guard let token = tokens[unitPart] else { return nil }
        let count: Double
        if numberPart.isEmpty {
            count = 1
        } else {
            guard let parsed = DecimalInput.parse(String(numberPart)), parsed > 0 else { return nil }
            count = parsed
        }
        let amount = count * token.factor
        guard amount.isFinite, amount > 0 else { return nil }
        return (token.unit, amount)
    }
}

public extension Serving {
    /// This serving's size in g/ml, when its unit states one.
    var metricSize: MetricServingSize? { MetricServingSize(serving: self) }
}

/// The one rule for turning what's typed into a quantity field into the
/// multiplier that's logged, and back. Every screen with a serving
/// quantity field goes through this, so "150" means 150 g everywhere.
public struct ServingQuantityInput: Sendable, Equatable {
    /// Decimals kept on a multiplier converted from grams (see header).
    public static let quantityFractionDigits = 3
    /// Decimals shown for a gram/ml amount (0.1 g is plenty).
    public static let amountFractionDigits = 1

    /// `nil` when the serving has no known metric size: servings only.
    public let size: MetricServingSize?

    public init(size: MetricServingSize?) {
        self.size = size
    }

    public init(serving: Serving?) {
        self.size = serving?.metricSize
    }

    /// Whether a "g | servings" choice makes sense: only for a known
    /// metric size that isn't already 1 g/ml per serving.
    public var offersModeChoice: Bool {
        guard let size else { return false }
        return !size.isPerUnit
    }

    /// The mode actually used for `preferred`: servings when there is no
    /// metric size; grams for a 1 g/1 ml serving (the multiplier already is
    /// the gram amount -- today's behaviour for "g" servings).
    public func resolvedMode(_ preferred: QuantityInputMode) -> QuantityInputMode {
        guard let size else { return .servings }
        if size.isPerUnit { return .amount }
        return preferred
    }

    /// The multiplier `text` stands for in `mode`, or `nil` when it doesn't
    /// parse (`DecimalInput`, so "1,5" works) or falls outside
    /// `LogQuantity.isValid`. A gram amount is rounded (see header); a
    /// typed servings multiplier is kept exactly as typed.
    public func quantity(fromText text: String, mode: QuantityInputMode) -> Double? {
        guard let value = DecimalInput.parse(text) else { return nil }
        let quantity: Double
        switch resolvedMode(mode) {
        case .servings:
            quantity = value
        case .amount:
            guard let size else { return nil }
            quantity = size.quantity(forAmount: value)
        }
        return LogQuantity.isValid(quantity) ? quantity : nil
    }

    /// What a field in `mode` shows for `quantity`: "150" (g) or "1.5"
    /// (servings), trailing zeros trimmed, with `decimalSeparator` (the
    /// phone's, so a Czech phone shows "1,5").
    public func text(forQuantity quantity: Double, mode: QuantityInputMode, decimalSeparator: String = ".") -> String {
        switch resolvedMode(mode) {
        case .servings:
            return Self.inputText(quantity, maxFractionDigits: Self.quantityFractionDigits, decimalSeparator: decimalSeparator)
        case .amount:
            guard let size else {
                return Self.inputText(quantity, maxFractionDigits: Self.quantityFractionDigits, decimalSeparator: decimalSeparator)
            }
            return Self.inputText(size.amount(forQuantity: quantity), maxFractionDigits: Self.amountFractionDigits, decimalSeparator: decimalSeparator)
        }
    }

    /// The g/ml `quantity` logs, as display text ("150 g"), or `nil`
    /// without a metric size.
    public func amountLabel(forQuantity quantity: Double) -> String? {
        guard let size else { return nil }
        let amount = size.amount(forQuantity: quantity)
        return "\(Self.inputText(amount, maxFractionDigits: Self.amountFractionDigits)) \(size.unit.symbol)"
    }

    /// Why the field's text was rejected, in the unit being typed -- the
    /// gram limit is `LogQuantity.maximum` servings' worth.
    public func invalidMessage(mode: QuantityInputMode) -> String {
        guard resolvedMode(mode) == .amount, let size else { return LogQuantity.invalidMessage }
        let limit = NumberDisplay.whole(size.amount(forQuantity: LogQuantity.maximum))
        return String(
            localized: "Enter an amount greater than zero and at most \(limit) \(size.unit.symbol).",
            bundle: .module,
            comment: "Validation error under an amount field. First %@ is the maximum amount (e.g. 25000), second %@ the unit symbol (g or ml)."
        )
    }

    // MARK: Helpers

    static func rounded(_ value: Double, fractionDigits: Int) -> Double {
        guard value.isFinite else { return value }
        let scale = pow(10, Double(max(0, fractionDigits)))
        return (value * scale).rounded() / scale
    }

    /// `value` with at most `maxFractionDigits` decimals and no trailing
    /// zeros ("150", "1.5", "0.333"); empty for a non-finite value.
    public static func inputText(_ value: Double, maxFractionDigits: Int, decimalSeparator: String = ".") -> String {
        guard value.isFinite else { return "" }
        var text = String(format: "%.\(max(0, maxFractionDigits))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if text == "-0" { text = "0" }
        return decimalSeparator == "." ? text : text.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}
