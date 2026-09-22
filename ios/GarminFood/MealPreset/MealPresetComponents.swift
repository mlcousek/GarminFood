// MealPresetComponents.swift
//
// Small, composable views for meal presets (config.yaml's "small,
// composable views" principle), shared between `FoodCatalogView`'s "Your
// meals" list and `TodayView`'s "Log a meal" shelf.

import SwiftUI
import FoodLogCore

/// One row in a list -- mirrors `FoodListRow`'s shape (name, a secondary
/// line, trailing calories) but for a preset: the secondary line is an
/// ingredient count instead of a brand/serving, since a preset has no
/// single serving of its own.
struct MealPresetRow: View {
    let preset: MealPreset

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.foodTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(preset.ingredients.count) ingredient\(preset.ingredients.count == 1 ? "" : "s")")
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            MacroBadge(value: preset.totals().calories, unit: " kcal", accessibleUnit: "kilocalories")
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// The horizontally-scrolling "Log a meal" shelf on the Today tab -- same
/// shape/interaction as `QuickPickShelf` (tapping opens the confirm screen,
/// meal type/date stay reviewable there), but for presets.
struct MealPresetShelf: View {
    let presets: [MealPreset]
    let onTap: (MealPreset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(presets) { preset in
                    Button {
                        onTap(preset)
                    } label: {
                        MealPresetCard(preset: preset)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }
}

private struct MealPresetCard: View {
    let preset: MealPreset

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(preset.name)
                .font(.foodTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(preset.ingredients.count) ingredient\(preset.ingredients.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            MacroBadge(value: preset.totals().calories, unit: " kcal", accessibleUnit: "kilocalories")
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 140, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.name), \(preset.ingredients.count) ingredients")
        .accessibilityHint("Logs this meal")
    }
}

#Preview("MealPresetRow") {
    List {
        MealPresetRow(preset: MealPreset(
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
        ))
    }
}
