// SupplementLimits.swift
//
// Targets and upper limits per ingredient, and the calm over-limit check
// (add-supplements D6, spec "Daily ingredient totals are compared with the
// user's own limits" / "Over-limit warnings are informational and calm").
//
//   - Defaults come from `EvidenceCatalog` (design D8). The user can
//     override the target and/or the upper limit per ingredient
//     (`LimitOverride`, persisted by `SupplementLimitsStore`) -- endurance
//     athletes often need more sodium or magnesium -- and "Reset to
//     default" deletes the override.
//   - A warning means the day's total is ABOVE (not at) the effective upper
//     limit. An ingredient with no EU upper limit (vitamin C, EPA+DHA,
//     creatine...) never warns unless the user sets a limit of their own:
//     the US vitamin C figure is shown, labelled US, but not enforced.
//   - Warnings are data for a row on the totals/evidence view and a
//     non-blocking notice when an extra dose is logged. Nothing here blocks
//     a log, and nothing sends a notification.
//
// Depended on by: SupplementLimitsStore (persists overrides), LabelScore
// (headroom), the totals view and extra-dose sheet (wave 3).
// Tests: SupplementLimitsTests.

import Foundation

/// The user's own figures for one ingredient, in its canonical unit. A
/// `nil` field keeps the default for that field.
public struct LimitOverride: Codable, Sendable, Equatable {
    public let ingredient: IngredientID
    public var target: Double?
    public var upperLimit: Double?

    public init(ingredient: IngredientID, target: Double? = nil, upperLimit: Double? = nil) {
        self.ingredient = ingredient
        self.target = target
        self.upperLimit = upperLimit
    }

    private enum CodingKeys: String, CodingKey { case ingredient, target, upperLimit }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ingredient = try container.decode(IngredientID.self, forKey: .ingredient)
        target = try container.decodeIfPresent(Double.self, forKey: .target)
        upperLimit = try container.decodeIfPresent(Double.self, forKey: .upperLimit)
    }

    /// Nothing overridden: storing it would be the same as the default.
    public var isEmpty: Bool { target == nil && upperLimit == nil }
}

/// The figures in force for one ingredient.
public struct EffectiveLimit: Sendable, Equatable {
    public let ingredient: IngredientID
    public let unit: DoseUnit
    public let target: Double?
    /// What warnings compare against; `nil` = no warning.
    public let upperLimit: Double?
    /// The catalog's default, for "Default: 250 mg (EFSA)" next to an
    /// override.
    public let defaultUpperLimit: Double?
    /// `nil` for an ingredient without a card.
    public let defaultKind: LimitKind?
    public let isOverridden: Bool
}

public struct LimitWarning: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The day's total is above the daily limit.
        case daily
        /// A single dose is above the per-dose limit (caffeine 200 mg).
        case singleDose
    }

    public let ingredient: IngredientID
    public let kind: Kind
    /// The amount compared (day total, or the dose), canonical unit.
    public let amount: Double
    public let limit: Double
    public let unit: DoseUnit
}

public enum SupplementLimits {
    public typealias Overrides = [IngredientID: LimitOverride]

    public static func effective(for ingredient: IngredientID, overrides: Overrides) -> EffectiveLimit {
        let card = EvidenceCatalog.card(for: ingredient)
        let override = overrides[ingredient]
        let defaultUpper = card?.limit.value
        return EffectiveLimit(
            ingredient: ingredient,
            unit: ingredient.canonicalUnit,
            target: override?.target,
            upperLimit: override?.upperLimit ?? defaultUpper,
            defaultUpperLimit: defaultUpper,
            defaultKind: card?.limit.kind,
            isOverridden: !(override?.isEmpty ?? true)
        )
    }

    /// Every ingredient of `totals` above its effective upper limit, by id.
    public static func warnings(for totals: IngredientTotals, overrides: Overrides) -> [LimitWarning] {
        totals.ingredients.compactMap { ingredient -> LimitWarning? in
            let total = totals.amount(of: ingredient)
            guard let limit = effective(for: ingredient, overrides: overrides).upperLimit, total > limit + tolerance(limit) else {
                return nil
            }
            return LimitWarning(ingredient: ingredient, kind: .daily, amount: total, limit: limit, unit: ingredient.canonicalUnit)
        }
    }

    /// The non-blocking notice when `servings` of `product` are logged as an
    /// extra on a day already at `current` (spec "Extra dose over the
    /// limit"): each ingredient whose day total WOULD go above its limit,
    /// plus any single dose above a per-dose limit. The dose is logged
    /// either way.
    public static func extraDoseNotice(
        adding product: SupplementProduct,
        servings: Double,
        to current: IngredientTotals,
        overrides: Overrides
    ) -> [LimitWarning] {
        let dose = IngredientTotals.of(product, servings: servings)
        var after = current
        after.add(product, servings: servings)
        var result = warnings(for: after, overrides: overrides).filter { dose.amount(of: $0.ingredient) > 0 }
        for ingredient in dose.ingredients {
            let amount = dose.amount(of: ingredient)
            if let single = EvidenceCatalog.card(for: ingredient)?.limit.singleDose, amount > single + tolerance(single) {
                result.append(LimitWarning(ingredient: ingredient, kind: .singleDose, amount: amount, limit: single, unit: ingredient.canonicalUnit))
            }
        }
        return result
    }

    /// Floating-point slack, so 0.1 + 0.2 g of something isn't "over" 0.3 g.
    private static func tolerance(_ limit: Double) -> Double {
        abs(limit) * 1e-9
    }
}
