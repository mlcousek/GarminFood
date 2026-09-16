// GarminFoodMatching.swift
//
// design.md D3 / garmin-food-matching spec (task group 29): finds a
// Garmin-side equivalent for a chosen Czech-database (Open Food Facts)
// food, so logging it never leaves Garmin as an incomplete or
// inconsistent record -- either it's logged against a real Garmin food,
// or (design.md D4) a new one is created with explicit confirmation.
//
// Pure and synchronous: this does no searching itself. The caller
// (MatchConfirmationView) re-searches Garmin for the OFF product's own
// name via the existing `FoodCatalogSearch`/`GarminClient` seam and hands
// the results in here -- this file has no network dependency at all,
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

            if let offCalories, let candidateCalories = candidate.servings.first?.calories, candidateCalories > 0 {
                let relativeDifference = abs(offCalories - candidateCalories) / candidateCalories
                guard relativeDifference <= calorieTolerance else { continue }
            }

            return .matched(candidate)
        }

        return .noMatch
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
