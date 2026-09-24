// ServingPickerSheet.swift
//
// The serving picker (design.md D2, food-catalog spec's "A food's serving
// choice is remembered as a default" requirement). Shown either
// automatically (first time a food is picked, no remembered default yet) or
// on demand (the user taps "Change serving" in the confirm screen, per the
// spec's "still allowing the user to change it"). Reused as-is by the
// custom-food editor to pick the Garmin food's BACKING serving
// (design.md D4) -- one component, two call sites, per config.yaml's
// "small, composable views" principle.

import SwiftUI
import FoodLogCore

struct ServingPickerSheet: View {
    let food: Food
    let onPick: (Serving) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(food.servings) { serving in
                Button {
                    onPick(serving)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(serving.displayLabel)
                                .font(.foodTitle)
                                .foregroundStyle(.primary)
                            if let calories = serving.calories {
                                Text("\(calories.wholeNumberText) kcal")
                                    .font(.foodSubtitle)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if food.servings.isEmpty {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: String(localized: "No servings"), message: String(localized: "This food has no serving information to log against."))
                }
            }
        }
    }
}

#Preview {
    ServingPickerSheet(
        food: Food(
            id: "1",
            name: "Rohlík",
            source: .fatSecret,
            servings: [
                Serving(id: "s1", unit: "g", numberOfUnits: 100, calories: 290),
                Serving(id: "s2", unit: "roll", numberOfUnits: 1, calories: 145),
            ]
        ),
        onPick: { _ in }
    )
}
