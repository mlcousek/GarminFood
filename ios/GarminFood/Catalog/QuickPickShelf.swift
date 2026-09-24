// QuickPickShelf.swift
//
// The horizontally-scrolling "quick pick" shelf (design.md D1, food-catalog
// spec's "A quick-pick shelf is ranked from local usage" requirement) --
// tapping a card logs the exact food+serving+quantity it was last logged
// with, in as close to one tap as this app gets (the confirm screen still
// appears, so the meal type/date/quantity stay reviewable and editable, per
// the food-log-entry spec). What a tap does is entirely the caller's
// `onTap`: in `FoodCatalogView`'s ingredient picker it adds the card to the
// meal instead of logging (fix-testing-feedback-quick-wins).
//
// Since improve-log-food-shelves this is a thin adapter onto the shared
// `FoodShelf`/`FoodShelfCard` (FoodShelf.swift), and it also renders the
// "Usual for <meal>" and "Recent" shelves: all three show a remembered
// food+serving+quantity (`QuickPickItem`) and differ only in how
// `FoodCatalogView` ranks the items (`QuickPick`, `MealUsualRanker`,
// `RecentRanker` in FoodLogCore) -- so they share one card and one tap path.

import SwiftUI
import FoodLogCore

struct QuickPickShelf: View {
    let items: [QuickPickItem]
    let onTap: (QuickPickItem) -> Void
    /// Favorite-star wiring (add-favorite-foods) -- both optional and only
    /// meaningful together, so existing/preview call sites that don't pass
    /// them simply render no star at all rather than a half-wired one.
    /// `FoodCatalogView` passes `nil` for both while in a picker mode
    /// (`.pickBackingFood`/`.pickIngredient`), where toggling a favorite
    /// isn't offered.
    var isFavorite: ((Food) -> Bool)? = nil
    var onToggleFavorite: ((Food) -> Void)? = nil
    /// What a tap does, for VoiceOver. `FoodCatalogView` passes "Adds this
    /// to the meal" in its ingredient picker, where a tap no longer logs
    /// (fix-testing-feedback-quick-wins).
    var cardAccessibilityHint: String = String(localized: "Logs this again")

    var body: some View {
        FoodShelf(items: items) { item in
            FoodShelfCard(
                title: item.food.name,
                subtitle: "\(item.serving.displayLabel) · \(item.numberOfUnits.shelfQuantityText)×",
                calories: item.serving.calories.map { $0 * item.numberOfUnits },
                accessibilityLabel: accessibilityLabel(for: item),
                accessibilityHint: cardAccessibilityHint,
                favorite: favorite(for: item),
                onTap: { onTap(item) }
            )
        }
    }

    private func favorite(for item: QuickPickItem) -> FoodShelfFavorite? {
        guard let isFavorite, let onToggleFavorite else { return nil }
        return FoodShelfFavorite(isFavorite: isFavorite(item.food), toggle: { onToggleFavorite(item.food) })
    }

    private func accessibilityLabel(for item: QuickPickItem) -> String {
        // Whole-sentence keys (no glued fragments) so each language can
        // phrase quantity and energy its own way.
        let name = item.food.name
        let quantity = item.numberOfUnits.shelfQuantityText
        let serving = item.serving.displayLabel
        if let calories = item.serving.calories {
            let energy = (calories * item.numberOfUnits).wholeNumberText
            return String(localized: "\(name), \(quantity) times \(serving), \(energy) kilocalories")
        }
        return String(localized: "\(name), \(quantity) times \(serving)")
    }
}

#Preview {
    QuickPickShelf(
        items: [
            QuickPickItem(
                food: Food(id: "1", name: "Rohlík", source: .fatSecret, servings: []),
                serving: Serving(id: "s1", unit: "g", numberOfUnits: 100, calories: 290),
                numberOfUnits: 2
            )
        ],
        onTap: { _ in }
    )
}
