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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    Button {
                        onTap(item)
                    } label: {
                        QuickPickCard(item: item)
                    }
                    .buttonStyle(.plain)
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
