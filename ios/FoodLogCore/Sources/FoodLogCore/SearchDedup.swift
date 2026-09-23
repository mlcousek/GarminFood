// SearchDedup.swift
//
// Cross-source dedup (rebuild-food-search design.md D4). Once Garmin,
// Open Food Facts and the user's own foods share one list, the same
// product regularly arrives twice -- e.g. "Jihočeský tvaroh" from Madeta in
// both Garmin and OFF -- and before this change it was simply shown twice,
// in two separate lists.
//
// Two results are the same product when:
//   - they are literally the same record (same Garmin food id reached via
//     the local library and via Garmin search; same EAN from live OFF and
//     the offline index), or
//   - they come from DIFFERENT sources, their normalized name words (brand
//     words removed, pack sizes ignored, order ignored) and normalized
//     first brand are equal, and their kcal per 100 g agree within 5 %.
//     Unknown calories never merge: without that check a same-named but
//     different product (plain vs. flavoured) could silently vanish.
// The copy from the highest-precedence source is kept (local > Garmin >
// offline index > OFF -- the directly loggable one), with the higher of
// the two scores and an "also in" provenance list.
//
// Pure; used by SearchRanker.rank. Tested by SearchDedupTests.

import Foundation

public enum SearchDedup {
    public static let calorieTolerance = 0.05

    public static func merge(_ results: [SearchResult], calorieTolerance: Double = SearchDedup.calorieTolerance) -> [SearchResult] {
        // Highest-precedence copies first, so they are the ones kept.
        let ordered = results.sorted { lhs, rhs in
            if lhs.origin.precedence != rhs.origin.precedence { return lhs.origin.precedence < rhs.origin.precedence }
            return lhs.score > rhs.score
        }

        var merged: [SearchResult] = []
        var indexByIdentity: [String: Int] = [:]
        var indicesByKey: [String: [Int]] = [:]

        for result in ordered {
            let identity = identityKey(result)
            if let index = indexByIdentity[identity] {
                merged[index] = combine(merged[index], result)
                continue
            }

            let key = nameKey(for: result.food)
            let calories = kcalPer100(result.food)
            let sameProductIndex = indicesByKey[key]?.first { index in
                let existing = merged[index]
                return existing.origin != result.origin
                    && !existing.alsoIn.contains(result.origin)
                    && caloriesAgree(kcalPer100(existing.food), calories, tolerance: calorieTolerance)
            }
            if let index = sameProductIndex {
                merged[index] = combine(merged[index], result)
                indexByIdentity[identity] = index
                continue
            }

            merged.append(result)
            let newIndex = merged.count - 1
            indexByIdentity[identity] = newIndex
            indicesByKey[key, default: []].append(newIndex)
        }
        return merged
    }

    /// The same underlying record, whichever source returned it.
    static func identityKey(_ result: SearchResult) -> String {
        switch result.origin {
        case .openFoodFacts, .offlineIndex:
            return "off:\(result.food.id)"
        case .local, .garmin:
            return "food:\(result.food.id)"
        }
    }

    /// Sorted name words (brand words and pack sizes removed) + "|" + the
    /// first brand's words.
    public static func nameKey(for food: Food) -> String {
        let firstBrand = food.brandName?.split(separator: ",").first.map(String.init) ?? ""
        let brandWords = SearchText.words(firstBrand)
        let brandSet = Set(brandWords)
        let nameWords = SearchText.words(food.name)
        let withoutBrand = nameWords.filter { !brandSet.contains($0) }
        let words = (withoutBrand.isEmpty ? nameWords : withoutBrand).sorted()
        return words.joined(separator: " ") + "|" + brandWords.joined(separator: " ")
    }

    /// kcal per 100 g (or 100 ml) from the first serving whose unit is a
    /// plain mass/volume ("g" x 100, "100g" x 1, "100 ml" x 1 …).
    public static func kcalPer100(_ food: Food) -> Double? {
        for serving in food.servings {
            guard let calories = serving.calories, let amount = gramsOrMilliliters(in: serving), amount > 0 else { continue }
            return calories * 100 / amount
        }
        return nil
    }

    static func gramsOrMilliliters(in serving: Serving) -> Double? {
        let unit = SearchText.fold(serving.unit).filter { !$0.isWhitespace }
        let numberPart = unit.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let suffix = String(unit.dropFirst(numberPart.count))
        guard ["g", "ml", "gram", "grams", "gramu", "gramy"].contains(suffix) else { return nil }
        let perUnit: Double
        if numberPart.isEmpty {
            perUnit = 1
        } else if let parsed = Double(numberPart.replacingOccurrences(of: ",", with: ".")) {
            perUnit = parsed
        } else {
            return nil
        }
        return perUnit * serving.numberOfUnits
    }

    static func caloriesAgree(_ lhs: Double?, _ rhs: Double?, tolerance: Double) -> Bool {
        guard let lhs, let rhs else { return false }
        let larger = max(abs(lhs), abs(rhs))
        guard larger > 0 else { return true }
        return abs(lhs - rhs) / larger <= tolerance
    }

    /// Keeps the higher-precedence copy (ties keep `existing`), the higher
    /// score, and records the other copy's source(s) as provenance.
    static func combine(_ existing: SearchResult, _ incoming: SearchResult) -> SearchResult {
        let keepIncoming = incoming.origin.precedence < existing.origin.precedence
        let winner = keepIncoming ? incoming : existing
        let loser = keepIncoming ? existing : incoming
        var provenance = Set(existing.alsoIn + incoming.alsoIn)
        provenance.insert(loser.origin)
        provenance.remove(winner.origin)
        return SearchResult(
            food: winner.food,
            origin: winner.origin,
            alsoIn: provenance.sorted { $0.precedence < $1.precedence },
            score: max(existing.score, incoming.score),
            textScore: max(existing.textScore, incoming.textScore),
            coversQuery: existing.coversQuery || incoming.coversQuery,
            customDraft: winner.customDraft
        )
    }
}
