// GarminFoodMatching.swift
//
// design.md D3 / garmin-food-matching spec (task group 29): finds a
// Garmin-side equivalent for a chosen Czech-database (Open Food Facts)
// food, so logging it never leaves Garmin as an incomplete or
// inconsistent record -- either it's logged against a real Garmin food,
// or (design.md D4) a new one is created with explicit confirmation.
//
// Pure and synchronous: this does no searching itself. The caller
// (MatchConfirmationView) searches Garmin for `searchQuery(for:)` via
// `FoodSearchEngine` and hands the ranked results in here -- this file has
// no network dependency at all,
// which is what makes it trivially unit-testable (task 29.2) without a
// fake server.
//
// Deliberately NOT trying to be a perfect matcher (design.md's own
// Non-Goal: "Perfect matching. A reasonable, explainable heuristic is
// enough; the user always sees what was matched (or that nothing was)
// before anything is logged" -- see MatchConfirmationView.swift for the
// "always shown, never resolved invisibly" half of that rule).

import Foundation

public enum GarminFoodMatchResult: Equatable, Sendable {
    case matched(Food)
    case noMatch
}

public enum GarminFoodMatching {
    /// design.md D3: "a rough sanity check that calorie values are in the
    /// same neighborhood (within ~20%)". Only applied when BOTH sides
    /// carry a calorie value -- a Garmin candidate or OFF product missing
    /// calories entirely can't be sanity-checked this way, so a
    /// name-only match is accepted in that case per the same paragraph's
    /// "where available".
    public static let calorieTolerance = 0.20

    /// Finds the first Garmin candidate whose normalized name reasonably
    /// matches `offFood`'s normalized name and, where both sides have a
    /// calorie value, isn't a wild calorie mismatch (a strong signal the
    /// name similarity is coincidental rather than the same product).
    public static func match(offFood: Food, garminCandidates: [Food]) -> GarminFoodMatchResult {
        let normalizedTarget = normalize(offFood.name)
        guard !normalizedTarget.isEmpty else { return .noMatch }

        let offCalories = offFood.servings.first?.calories

        for candidate in garminCandidates {
            let normalizedCandidate = normalize(candidate.name)
            guard !normalizedCandidate.isEmpty else { continue }

            let namesMatch = normalizedCandidate == normalizedTarget
                || normalizedCandidate.contains(normalizedTarget)
                || normalizedTarget.contains(normalizedCandidate)
            guard namesMatch else { continue }

            // 2026-09-21 bug fix: `candidateCalories > 0` used to gate
            // whether this check ran AT ALL, which treated a genuinely
            // zero-calorie Garmin food (diet soda, black coffee) the same
            // as "calories missing" -- a name-similar OFF product with
            // real calories (e.g. regular Coca-Cola) could match a
            // "Coca-Cola Zero" Garmin candidate on name alone, with no
            // sanity check at all. The `> 0` split below now only decides
            // HOW to compare (relative-% is undefined against a zero
            // denominator), never WHETHER to compare.
            if let offCalories, let candidateCalories = candidate.servings.first?.calories {
                if candidateCalories > 0 {
                    let relativeDifference = abs(offCalories - candidateCalories) / candidateCalories
                    guard relativeDifference <= calorieTolerance else { continue }
                } else {
                    // A relative-% comparison against zero is meaningless;
                    // require the OFF side to also be near-zero instead.
                    guard offCalories <= 5 else { continue }
                }
            }

            return .matched(candidate)
        }

        return .noMatch
    }

    /// What to search Garmin for when matching `offFood` (rebuild-food-search
    /// task 4.2): the product's own words without its brand or pack size,
    /// diacritics kept, via the shared `SearchText` pipeline. The full OFF
    /// name ("Rohlíky Krehké Celozrné 250G Active Bonavita") used to be sent
    /// verbatim, and the brand/pack-size words only diluted Garmin's own
    /// matching.
    public static func searchQuery(for offFood: Food) -> String {
        SearchText.matchQuery(name: offFood.name, brand: offFood.brandName)
    }

    /// Lowercases, strips diacritics (`folding(options: .diacriticInsensitive,
    /// locale:)` per design.md D3's explicit instruction), and drops
    /// packaging/quantity tokens like "250g"/"1 kg"/"500ml" before
    /// collapsing to single-space-separated alphanumeric tokens -- so
    /// "Rohlíky Krehké 250G" and "rohliky krehke" normalize to the same
    /// thing.
    static func normalize(_ name: String) -> String {
        let folded = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        let withoutPackaging = folded.replacingOccurrences(
            of: #"\d+\s*(g|kg|ml|l)\b"#,
            with: " ",
            options: .regularExpression
        )
        return withoutPackaging
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
