// Components.swift
//
// Small, composable, previewable views shared across screens --
// config.yaml's "small, composable views... makes adding the next thing
// cheap" and "previewable SwiftUI views" principles. Each carries its own
// `#Preview` so it can be inspected in isolation (there is no Xcode Previews
// canvas actually running for this project today -- design.md's "no Mac"
// constraint -- but the previews still document intended usage and will
// work the moment someone opens this in real Xcode).

import SwiftUI
import FoodLogCore

// MARK: - MacroBadge

/// A compact "290 kcal" / "9g protein" pill. VoiceOver reads the full label
/// ("290 kilocalories"), not the abbreviated glyph text, per config.yaml's
/// accessibility baseline.
struct MacroBadge: View {
    let value: Double
    let unit: String
    let accessibleUnit: String

    var body: some View {
        Text("\(Int(value.rounded()))\(unit)")
            .font(.macroBadge)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(Int(value.rounded())) \(accessibleUnit)")
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.sectionHeader)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - FoodListRow

/// One row in a search-results / recents list. Shows the food's name, an
/// optional brand, its calories (if the given serving carries them), and a
/// small source badge -- Garmin's own `isFavorite`/`isRecent` flags
/// (design.md D1: shown as secondary context, never used for ranking) or a
/// "Custom" tag for a locally-created food.
struct FoodListRow: View {
    let food: Food
    let serving: Serving?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.foodTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.xs) {
                    if let brandName = food.brandName, !brandName.isEmpty {
                        Text(brandName)
                            .font(.foodSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    if let serving {
                        Text(serving.displayLabel)
                            .font(.foodSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                badges
            }
            Spacer(minLength: Theme.Spacing.sm)
            if let calories = serving?.calories {
                MacroBadge(value: calories, unit: " kcal", accessibleUnit: "kilocalories")
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if food.source == .custom {
                Tag(text: "Custom", color: Theme.warning)
            }
            if food.garminIsFavorite == true {
                Tag(text: "Favorite", color: Theme.accent)
            }
            if food.garminIsRecent == true {
                Tag(text: "Recent", color: .secondary)
            }
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - PrimaryButton

/// The one CTA style this app uses for its "log it" / "save" / "confirm"
/// actions -- defined once (config.yaml's design-system principle) rather
/// than styled ad hoc per screen.
struct PrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm + 2)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(isDisabled)
    }
}

// MARK: - EmptyStateView

/// A deliberate empty state (config.yaml: "states (loading, empty, error,
/// success) are designed on purpose, not left as whatever SwiftUI does by
/// default"), not a blank screen.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview("FoodListRow") {
    List {
        FoodListRow(
            food: Food(id: "1", name: "Rohlík", brandName: nil, source: .fatSecret, servings: [], garminIsFavorite: true),
            serving: Serving(id: "s1", unit: "g", numberOfUnits: 100, calories: 290)
        )
        FoodListRow(
            food: Food(id: "2", name: "Domácí tvaroh", source: .custom, servings: []),
            serving: Serving(id: "custom", unit: "bowl", numberOfUnits: 1, calories: 220)
        )
    }
}

#Preview("EmptyStateView") {
    EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Try a different search term.")
}
