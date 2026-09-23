// EditDistance.swift
//
// Typo tolerance for search (rebuild-food-search design.md D3's "fuzzy"
// tier): "chlba", "bnan" and "tvaroch" should still find the food. A plain
// Levenshtein distance counts a swapped pair ("jgourt") as two edits, so
// this is the optimal-string-alignment variant of Damerau-Levenshtein,
// where an adjacent transposition costs one.
//
// Bounded on purpose: search only ever asks "is this within 1 (or 2)
// edits?", so the computation stops as soon as the length difference or a
// whole DP row already exceeds the bound. Every row's minimum is
// non-decreasing, which is what makes that early exit safe. This keeps the
// per-keystroke cost of fuzzy-matching every query word against every
// candidate word small (task 2.3's budget: 10k comparisons well under
// 50 ms in a release build).
//
// Pure; used by `SearchRanker`, tested by EditDistanceTests.

import Foundation

public enum EditDistance {
    /// The optimal-string-alignment distance between `a` and `b`, or `nil`
    /// when it is larger than `maxDistance`. Compares Unicode scalars, so
    /// callers pass already-folded text.
    public static func damerauLevenshtein(_ a: String, _ b: String, maxDistance: Int) -> Int? {
        bounded(Array(a.unicodeScalars), Array(b.unicodeScalars), maxDistance: maxDistance)
    }

    static func bounded<Element: Equatable>(_ source: [Element], _ target: [Element], maxDistance: Int) -> Int? {
        guard maxDistance >= 0 else { return nil }
        let sourceCount = source.count
        let targetCount = target.count
        if abs(sourceCount - targetCount) > maxDistance { return nil }
        if sourceCount == 0 { return targetCount }
        if targetCount == 0 { return sourceCount }

        // Three rolling rows: i-2, i-1 and i.
        var beforePrevious = [Int](repeating: 0, count: targetCount + 1)
        var previous = Array(0...targetCount)
        var current = [Int](repeating: 0, count: targetCount + 1)

        for i in 1...sourceCount {
            current[0] = i
            var rowMinimum = i
            for j in 1...targetCount {
                let cost = source[i - 1] == target[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, source[i - 1] == target[j - 2], source[i - 2] == target[j - 1] {
                    value = min(value, beforePrevious[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maxDistance { return nil }
            let recycled = beforePrevious
            beforePrevious = previous
            previous = current
            current = recycled
        }

        let distance = previous[targetCount]
        return distance <= maxDistance ? distance : nil
    }
}
