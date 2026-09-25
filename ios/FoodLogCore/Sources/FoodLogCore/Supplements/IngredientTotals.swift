// IngredientTotals.swift
//
// "How much zinc did I get today, from everything?" (add-supplements D6).
// Sums every intake record of a day -- planned ticks AND extras -- across
// products, per ingredient, in the ingredient's canonical unit
// (`IngredientID.canonicalUnit`), converting mass units and vitamin D IU
// (40 IU = 1 µg). Multi-ingredient products (multivitamin, ZMA) add to each
// of their ingredients.
//
// A row whose amount is unstated or can't be converted (IU of anything but
// vitamin D, a unit from a later build) is NOT guessed: its ingredient is
// listed in `unconverted`, so the totals view can say "not included"
// rather than show a number that looks complete but isn't.
//
// Intake is joined with the product AS IT IS NOW (the plan store), not a
// snapshot at tick time: editing a product's label fixes past totals too,
// which is what a user correcting a typo expects. Totals are informational
// (D6), so this trade-off is deliberate.
//
// Depended on by: SupplementLimits (over-limit warnings), LabelScore
// (headroom), the totals card (wave 3). Tests: IngredientTotalsTests.

import Foundation

public struct IngredientTotals: Sendable, Equatable {
    /// Canonical-unit amount per ingredient.
    public private(set) var amounts: [IngredientID: Double]
    /// Ingredients with at least one row that couldn't be counted.
    public private(set) var unconverted: Set<IngredientID>

    public init(amounts: [IngredientID: Double] = [:], unconverted: Set<IngredientID> = []) {
        self.amounts = amounts
        self.unconverted = unconverted
    }

    public func amount(of ingredient: IngredientID) -> Double {
        amounts[ingredient] ?? 0
    }

    /// Ingredients with a counted amount, sorted by id.
    public var ingredients: [IngredientID] {
        amounts.keys.sorted()
    }

    /// Adds `servings` of `product`.
    public mutating func add(_ product: SupplementProduct, servings: Double) {
        guard servings > 0 else { return }
        for row in product.ingredients {
            guard let perServing = row.canonicalAmount else {
                unconverted.insert(row.ingredient)
                continue
            }
            amounts[row.ingredient, default: 0] += perServing * servings
        }
    }

    /// Totals of the records dated `day`. Records of products no longer in
    /// `products` are skipped (a deleted product has no label to read).
    public static func of(day: String, records: [IntakeRecord], products: [SupplementProduct]) -> IngredientTotals {
        let byId = Dictionary(products.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var totals = IngredientTotals()
        for record in records where record.day == day {
            guard let product = byId[record.productId] else { continue }
            totals.add(product, servings: record.servings)
        }
        return totals
    }

    /// The totals of `product` alone at `servings`.
    public static func of(_ product: SupplementProduct, servings: Double) -> IngredientTotals {
        var totals = IngredientTotals()
        totals.add(product, servings: servings)
        return totals
    }
}
