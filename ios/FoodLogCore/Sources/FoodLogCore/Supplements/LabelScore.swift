// LabelScore.swift
//
// A transparent 0–100 score computed from the product LABEL only
// (add-supplements D7). No free external quality rating exists (Labdoor,
// ConsumerLab, Examine: no usable API; certification lists: search pages
// only), so the app never claims one. Instead three explained parts:
//
//   transparency (40): every ingredient has an amount, the form is stated
//                      where it matters (magnesium, D2), and nothing hides
//                      in a proprietary blend;
//   dose         (40): each ingredient's daily amount at the planned dose
//                      sits within its evidence card's effective range;
//   headroom     (20): the day's total at the planned dose (plus whatever
//                      else the caller passes in) stays under the user's
//                      upper limits.
//
// The screen shows the breakdown -- the `findings` of each part -- never
// just the number (spec "A label score explains product quality from the
// label only"). Scoring constants are deliberately simple and documented
// here so a reader of the breakdown can reproduce the number:
//   - transparency = 40 x (rows with an amount / rows), then -15 per
//     proprietary blend and -5 per magnesium row without a form;
//   - dose = 40 x mean(ingredient score), 1 inside the range, 0.5 outside
//     it; ingredients without a range aren't scored, and a product with
//     nothing scorable gets half (20), said so in the findings;
//   - headroom = 20, or 0 when any ingredient would be over its limit.
//
// Depended on by: the evidence/label score view (wave 3).
// Tests: LabelScoreTests.

import Foundation

public struct LabelScore: Sendable, Equatable {
    public enum Finding: Sendable, Equatable {
        case noIngredients
        case allAmountsStated
        case amountMissing(IngredientID)
        case formMissing(IngredientID)
        case proprietaryBlend(String)
        case withinRange(IngredientID)
        case belowRange(IngredientID)
        case aboveRange(IngredientID)
        case noReferenceRange(IngredientID)
        case underLimits
        case overLimit(IngredientID)
    }

    public struct Part: Sendable, Equatable {
        public let points: Int
        public let maximum: Int
        public let findings: [Finding]
    }

    public let transparency: Part
    public let dose: Part
    public let headroom: Part

    public var total: Int { transparency.points + dose.points + headroom.points }

    static let blendPenalty = 15.0
    static let missingFormPenalty = 5.0

    /// Scores `product` taken `servingsPerDay` times a day, with the user's
    /// limit `overrides` and `otherIntake` (the rest of the stack's day
    /// totals, empty by default).
    public static func evaluate(
        _ product: SupplementProduct,
        servingsPerDay: Double = 1,
        overrides: SupplementLimits.Overrides = [:],
        otherIntake: IngredientTotals = IngredientTotals()
    ) -> LabelScore {
        LabelScore(
            transparency: transparency(of: product),
            dose: dose(of: product, servingsPerDay: servingsPerDay),
            headroom: headroom(of: product, servingsPerDay: servingsPerDay, overrides: overrides, otherIntake: otherIntake)
        )
    }

    static func transparency(of product: SupplementProduct) -> Part {
        let rows = product.ingredients
        let blends = (product.proprietaryBlends ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else {
            let findings: [Finding] = blends.isEmpty ? [.noIngredients] : blends.map { Finding.proprietaryBlend($0) }
            return Part(points: 0, maximum: 40, findings: findings)
        }
        var findings: [Finding] = []
        let stated = rows.filter { $0.amount != nil }.count
        var score = 40 * Double(stated) / Double(rows.count)
        for row in rows where row.amount == nil {
            findings.append(.amountMissing(row.ingredient))
        }
        for row in rows where row.ingredient == .magnesium && (row.form ?? "").isEmpty {
            findings.append(.formMissing(row.ingredient))
            score -= missingFormPenalty
        }
        for blend in blends {
            findings.append(.proprietaryBlend(blend))
            score -= blendPenalty
        }
        if findings.isEmpty { findings = [.allAmountsStated] }
        return Part(points: clamp(score, 40), maximum: 40, findings: findings)
    }

    static func dose(of product: SupplementProduct, servingsPerDay: Double) -> Part {
        let daily = IngredientTotals.of(product, servings: max(0, servingsPerDay))
        var findings: [Finding] = []
        var scores: [Double] = []
        for ingredient in daily.ingredients {
            let amount = daily.amount(of: ingredient)
            guard let range = EvidenceCatalog.card(for: ingredient)?.effectiveRange else {
                findings.append(.noReferenceRange(ingredient))
                continue
            }
            // Tolerate float noise at the edges (4 x 1.25 g is "5 g").
            let slack = range.upperBound * 1e-9
            if amount < range.lowerBound - slack {
                findings.append(.belowRange(ingredient))
                scores.append(0.5)
            } else if amount > range.upperBound + slack {
                findings.append(.aboveRange(ingredient))
                scores.append(0.5)
            } else {
                findings.append(.withinRange(ingredient))
                scores.append(1)
            }
        }
        guard !scores.isEmpty else {
            if findings.isEmpty { findings = [.noIngredients] }
            return Part(points: 20, maximum: 40, findings: findings)
        }
        let mean = scores.reduce(0, +) / Double(scores.count)
        return Part(points: clamp(40 * mean, 40), maximum: 40, findings: findings)
    }

    static func headroom(
        of product: SupplementProduct,
        servingsPerDay: Double,
        overrides: SupplementLimits.Overrides,
        otherIntake: IngredientTotals
    ) -> Part {
        var totals = otherIntake
        totals.add(product, servings: max(0, servingsPerDay))
        let own = Set(product.ingredients.map(\.ingredient))
        let over = SupplementLimits.warnings(for: totals, overrides: overrides).filter { own.contains($0.ingredient) }
        if over.isEmpty {
            return Part(points: 20, maximum: 20, findings: [.underLimits])
        }
        return Part(points: 0, maximum: 20, findings: over.map { Finding.overLimit($0.ingredient) })
    }

    private static func clamp(_ value: Double, _ maximum: Int) -> Int {
        min(maximum, max(0, Int(value.rounded())))
    }
}
