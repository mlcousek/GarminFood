// FoodShelf.swift
//
// The one horizontal card shelf every "one swipe away" row in the app is
// built from (improve-log-food-shelves task 2.1). The owner liked the
// swipeable Quick pick shelf and asked for the rest of the empty-query Log
// Food screen to work the same way -- Quick pick, Favorites, Usual for
// <meal>, Meals, Recent -- so the scroll container and the card are defined
// once here (config.yaml's "small, consistent design system... not
// per-screen improvisation") instead of three near-copies drifting apart.
//
// Two pieces, deliberately dumb:
//   - `FoodShelf`: the horizontal scroller. Cards in one shelf share a
//     height (so a two-line name doesn't make a ragged row).
//   - `FoodShelfCard`: one tappable card -- name, a secondary line, kcal --
//     with an optional favorite star and optional long-press actions. It
//     knows nothing about foods, presets or modes; WHAT a tap does is the
//     caller's closure. That is load-bearing for picker mode: every shelf
//     routes its tap through `FoodCatalogView`'s mode-aware paths
//     (`selectQuickPick`, `select`, fix-testing-feedback-quick-wins), so a
//     tap here can never log on its own.
//
// Depended on by: QuickPickShelf, FavoritesShelf (Catalog/) and
// MealPresetShelf (MealPreset/MealPresetComponents.swift), which are thin
// adapters from their own item types onto this.

import SwiftUI
import FoodLogCore

struct FoodShelf<Item: Identifiable, Card: View>: View {
    private let items: [Item]
    private let card: (Item) -> Card

    init(items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.card = card
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    card(item)
                }
            }
            // Every card stretches to the tallest one in the row (each card
            // fills `maxHeight: .infinity`, bounded by this ideal height).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
        }
    }
}

/// A long-press (context menu) action on a card -- also exposed as a
/// VoiceOver custom action, since a long-press menu is easy to miss there.
struct FoodShelfCardAction: Identifiable {
    let title: String
    let systemImage: String
    var isDestructive = false
    let perform: () -> Void

    var id: String { title }
}

/// The favorite star shown on a card's top-trailing corner, as a SIBLING of
/// the card's own button (see FavoriteToggleButton's doc comment in
/// Components.swift for why it must not be nested inside the label).
struct FoodShelfFavorite {
    let isFavorite: Bool
    let toggle: () -> Void
}

struct FoodShelfCard: View {
    private let title: String
    private let subtitle: String?
    private let calories: Double?
    private let accessibilityLabelText: String
    private let accessibilityHintText: String
    private let favorite: FoodShelfFavorite?
    private let actions: [FoodShelfCardAction]
    private let onTap: () -> Void

    /// Scales with Dynamic Type so a larger text size gets a wider card
    /// rather than a name truncated to a few letters; capped so a single
    /// card never fills the whole screen at accessibility sizes.
    @ScaledMetric(relativeTo: .headline) private var scaledWidth: CGFloat = 140
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        subtitle: String? = nil,
        calories: Double? = nil,
        accessibilityLabel: String,
        accessibilityHint: String,
        favorite: FoodShelfFavorite? = nil,
        actions: [FoodShelfCardAction] = [],
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.calories = calories
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityHintText = accessibilityHint
        self.favorite = favorite
        self.actions = actions
        self.onTap = onTap
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            withActions(
                Button(action: onTap) {
                    face
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint(accessibilityHintText)
            )
            if let favorite {
                FavoriteToggleButton(isFavorite: favorite.isFavorite, action: favorite.toggle)
                    .padding(4)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.foodTitle)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .multilineTextAlignment(.leading)
                // Leave room for the star so it never sits on the name.
                .padding(.trailing, favorite == nil ? 0 : 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let calories {
                MacroBadge.calories(calories)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(width: min(scaledWidth, 280), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    /// Adds the context menu and matching VoiceOver actions only when there
    /// are any -- an empty `.contextMenu` would still lift the card on a
    /// long-press and show nothing.
    @ViewBuilder
    private func withActions<Content: View>(_ content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content
                .contextMenu {
                    ForEach(actions) { action in
                        Button(role: action.isDestructive ? ButtonRole.destructive : nil) {
                            action.perform()
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                }
                .accessibilityActions {
                    ForEach(actions) { action in
                        Button(action.title) {
                            action.perform()
                        }
                    }
                }
        }
    }
}

/// Shared by every shelf's accessibility label ("2 times 100 g").
extension Double {
    var shelfQuantityText: String {
        NumberDisplay.quantity(self, fractionDigits: 1)
    }
}

#Preview {
    FoodShelf(items: [1, 2, 3].map { PreviewItem(id: $0) }) { item in
        FoodShelfCard(
            title: item.id == 2 ? "A much longer food name that wraps" : "Rohlík",
            subtitle: "100 g · 2×",
            calories: 290,
            accessibilityLabel: "Rohlík",
            accessibilityHint: "Logs this again",
            favorite: FoodShelfFavorite(isFavorite: item.id == 1, toggle: {}),
            actions: item.id == 3 ? [FoodShelfCardAction(title: "Edit", systemImage: "pencil", perform: {})] : [],
            onTap: {}
        )
    }
}

private struct PreviewItem: Identifiable {
    let id: Int
}
