// MealPresetComponents.swift
//
// Small, composable views for meal presets (config.yaml's "small,
// composable views" principle), shared between `FoodCatalogView`'s "Meals"
// shelf and `TodayView`'s "Log a meal" shelf.
//
// improve-log-food-shelves: the catalog's vertical "Your meals" list (and
// its `MealPresetRow`) is gone -- presets are cards on the shared
// `FoodShelf` (Catalog/FoodShelf.swift) like every other shelf, with Edit
// and Delete moved from swipe actions to the card's long-press menu.

import SwiftUI
import FoodLogCore

/// The horizontally-scrolling preset shelf -- same shape/interaction as
/// `QuickPickShelf` (tapping opens the confirm screen, meal type/date stay
/// reviewable there), but for presets. `onEdit`/`onDelete` are optional:
/// the Today tab's "Log a meal" shelf passes neither, so its cards have no
/// long-press menu.
struct MealPresetShelf: View {
    let presets: [MealPreset]
    let onTap: (MealPreset) -> Void
    var onEdit: ((MealPreset) -> Void)? = nil
    var onDelete: ((MealPreset) -> Void)? = nil

    var body: some View {
        FoodShelf(items: presets) { preset in
            FoodShelfCard(
                title: preset.name,
                subtitle: ingredientCountText(preset),
                calories: preset.totals().calories,
                accessibilityLabel: "\(preset.name), \(ingredientCountText(preset)), \(preset.totals().calories.wholeNumberText) kilocalories",
                accessibilityHint: "Opens this meal to log it",
                actions: actions(for: preset),
                onTap: { onTap(preset) }
            )
        }
    }

    private func ingredientCountText(_ preset: MealPreset) -> String {
        "\(preset.ingredients.count) ingredient\(preset.ingredients.count == 1 ? "" : "s")"
    }

    private func actions(for preset: MealPreset) -> [FoodShelfCardAction] {
        var actions: [FoodShelfCardAction] = []
        if let onEdit {
            actions.append(FoodShelfCardAction(title: "Edit", systemImage: "pencil", perform: { onEdit(preset) }))
        }
        if let onDelete {
            actions.append(FoodShelfCardAction(title: "Delete", systemImage: "trash", isDestructive: true, perform: { onDelete(preset) }))
        }
        return actions
    }
}

#Preview("MealPresetShelf") {
    MealPresetShelf(
        presets: [
            MealPreset(
                name: "Breakfast bowl",
                ingredients: [
                    MealPresetIngredient(
                        food: Food(id: "1", name: "Oats", source: .fatSecret, servings: []),
                        serving: Serving(id: "s1", unit: "g", numberOfUnits: 40, calories: 150),
                        quantity: 1
                    ),
                    MealPresetIngredient(
                        food: Food(id: "2", name: "Banana", source: .garmin, servings: []),
                        serving: Serving(id: "s2", unit: "medium", numberOfUnits: 1, calories: 105),
                        quantity: 1
                    ),
                ]
            )
        ],
        onTap: { _ in },
        onEdit: { _ in },
        onDelete: { _ in }
    )
}
