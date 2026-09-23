// CustomFoodSearch.swift
//
// Finds the user's own custom foods by name while a search query is typed
// (fix-testing-feedback-quick-wins task 1.3, food-catalog spec "Picking an
// ingredient searches every food source"). Before this, custom foods were
// only listed while the search field was EMPTY -- typing anything hid them,
// so the meal-preset ingredient picker could never find one by name.
//
// Deliberately a simple, interim filter: diacritic- and case-insensitive
// substring on the name, so "rohlik" finds "Rohlík" and "CHLEBA" finds
// "chléba". The planned `rebuild-food-search` change replaces this with a
// unified ranked search across every source; until then this stays pure
// and local (no network, no ranking) so it can't slow the catalog down.
// Used by `FoodCatalogView` (app target); tested by CustomFoodSearchTests.

import Foundation

public enum CustomFoodSearch {
    /// The drafts whose name contains `query`, ignoring case and
    /// diacritics, in their original order. A blank query matches nothing:
    /// the catalog shows the full custom-food list itself when the search
    /// field is empty, so "every custom food" is never this function's job.
    public static func filter(_ drafts: [CustomFoodDraft], query: String) -> [CustomFoodDraft] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        return drafts.filter { normalized($0.name).contains(needle) }
    }

    /// Case- and diacritic-folded, locale-independent, so the result never
    /// depends on the device's language setting.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
