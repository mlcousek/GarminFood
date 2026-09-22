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

import SwiftUI
import FoodLogCore

struct FavoritesShelf: View {
    let items: [FavoriteFood]
    let onTap: (Food) -> Void
    /// `nil` while in a picker mode (`.pickBackingFood`/`.pickIngredient`)
    /// -- see `FoodCatalogView`'s own gating, matching `QuickPickShelf`'s
    /// identical optional-pair convention.
    var onToggleFavorite: ((Food) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            onTap(item.food)
                        } label: {
                            FavoriteCard(food: item.food)
                        }
                        .buttonStyle(.plain)
                        // Sibling of the Button above, not nested inside its
                        // label -- see FavoriteToggleButton's own doc
                        // comment (Components.swift).
                        if let onToggleFavorite {
                            // Every card in THIS shelf is, by construction,
                            // already favorited -- always show the filled
                            // star; tapping it un-favorites.
                            FavoriteToggleButton(isFavorite: true) {
                                onToggleFavorite(item.food)
                            }
                            .padding(4)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }
}

private struct FavoriteCard: View {
    let food: Food

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(food.name)
                .font(.foodTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let brandName = food.brandName, !brandName.isEmpty {
                Text(brandName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let calories = food.servings.first?.calories {
                MacroBadge(value: calories, unit: " kcal", accessibleUnit: "kilocalories")
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 140, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(food.name), favorite")
        .accessibilityHint("Logs this food")
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
