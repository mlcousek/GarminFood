// QuickPickShelf.swift
//
// The horizontally-scrolling "quick pick" shelf (design.md D1, food-catalog
// spec's "A quick-pick shelf is ranked from local usage" requirement) --
// tapping a card logs the exact food+serving+quantity it was last logged
// with, in as close to one tap as this app gets (the confirm screen still
// appears, so the meal type/date/quantity stay reviewable and editable, per
// the food-log-entry spec).

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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            onTap(item)
                        } label: {
                            QuickPickCard(item: item)
                        }
                        .buttonStyle(.plain)
                        // A sibling of the Button above, not nested inside
                        // its label -- see FavoriteToggleButton's own doc
                        // comment (Components.swift) for why.
                        if let isFavorite, let onToggleFavorite {
                            FavoriteToggleButton(isFavorite: isFavorite(item.food)) {
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

private struct QuickPickCard: View {
    let item: QuickPickItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(item.food.name)
                .font(.foodTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(item.serving.displayLabel) · \(item.numberOfUnits.formattedQuantity)×")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let calories = item.serving.calories {
                MacroBadge(value: calories * item.numberOfUnits, unit: " kcal", accessibleUnit: "kilocalories")
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 140, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.food.name), \(item.numberOfUnits.formattedQuantity) times \(item.serving.displayLabel)")
        .accessibilityHint("Logs this again")
    }
}

private extension Double {
    var formattedQuantity: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.1f", self)
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
