// FavoritesShelf.swift
//
// The horizontally-scrolling "Favorites" shelf (add-favorite-foods) --
// mirrors QuickPickShelf's card-shelf shape (the established pattern for
// fast re-access to a food, food-catalog spec), but is driven by the user's
// own explicit star-toggle choice (`FoodLogCore.FavoriteFoodStore`) rather
// than QuickPick's derived recency/frequency ranking (QuickPick.swift). The
// two lists are deliberately separate and independently populated -- a food
// can be quick-picked without ever being favorited (most foods), and a food
// can be favorited without having been quick-picked yet (e.g. starred while
// browsing search results for a planned future meal, never logged).
//
// Tapping a card routes through the SAME `select(_:)` dispatch
// `FoodCatalogView` already uses for a search result -- unlike
// `QuickPickShelf`, a `FavoriteFood` only remembers the food itself, not a
// last-used serving/quantity, so there is no "jump straight to the confirm
// screen" shortcut available here; every tap goes through the normal
// remembered-serving-or-picker-sheet path, same as tapping any other
// catalog result.
//
// Since improve-log-food-shelves: a thin adapter onto the shared
// `FoodShelf`/`FoodShelfCard` (FoodShelf.swift), so it looks and behaves
// like every other shelf on the Log Food screen.

import SwiftUI
import FoodLogCore

struct FavoritesShelf: View {
    let items: [FavoriteFood]
    let onTap: (Food) -> Void
    /// `nil` while in a picker mode (`.pickBackingFood`/`.pickIngredient`)
    /// -- see `FoodCatalogView`'s own gating, matching `QuickPickShelf`'s
    /// identical optional-pair convention.
    var onToggleFavorite: ((Food) -> Void)? = nil
    /// What a tap does, for VoiceOver ("Adds this to the meal" in the
    /// ingredient picker).
    var cardAccessibilityHint: String = "Logs this food"

    var body: some View {
        FoodShelf(items: items) { item in
            FoodShelfCard(
                title: item.food.name,
                subtitle: brandLine(for: item.food),
                calories: item.food.servings.first?.calories,
                accessibilityLabel: accessibilityLabel(for: item.food),
                accessibilityHint: cardAccessibilityHint,
                // Every card in THIS shelf is, by construction, already
                // favorited -- always the filled star; tapping it
                // un-favorites.
                favorite: onToggleFavorite.map { toggle in
                    FoodShelfFavorite(isFavorite: true, toggle: { toggle(item.food) })
                },
                onTap: { onTap(item.food) }
            )
        }
    }

    private func brandLine(for food: Food) -> String? {
        guard let brandName = food.brandName, !brandName.isEmpty else { return nil }
        return brandName
    }

    private func accessibilityLabel(for food: Food) -> String {
        var label = "\(food.name), favorite"
        if let calories = food.servings.first?.calories {
            label += ", \(calories.wholeNumberText) kilocalories"
        }
        return label
    }
}

#Preview {
    FavoritesShelf(
        items: [
            FavoriteFood(
                food: Food(
                    id: "1",
                    name: "Rohlík",
                    source: .fatSecret,
                    servings: [Serving(id: "s1", unit: "g", numberOfUnits: 100, calories: 290)]
                )
            )
        ],
        onTap: { _ in },
        onToggleFavorite: { _ in }
    )
}
