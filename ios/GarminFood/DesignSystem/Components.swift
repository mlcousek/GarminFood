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
        Text("\(value.wholeNumberText)\(unit)")
            .font(.macroBadge)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(value.wholeNumberText) \(accessibleUnit)")
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

// MARK: - FavoriteToggleButton

/// The star affordance for marking/unmarking a food as a LOCAL favorite
/// (add-favorite-foods, `FoodLogCore.FavoriteFoodStore`) -- distinct from
/// Garmin's own read-only `Food.garminIsFavorite` flag shown by
/// `FoodListRow`'s "Favorite" `Tag` above (that one reflects Garmin
/// account state this app cannot write to; this one is entirely this
/// project's own local, instantly-toggleable concept).
///
/// Deliberately a SIBLING view next to a row's own `Button`, never nested
/// inside one -- a second `Button` inside a List row's primary `Button`'s
/// `label` is unreliable in SwiftUI (the outer button's hit-testing can
/// swallow the inner tap). Every call site places this in an `HStack`/
/// `ZStack` alongside, not inside, the row's own tap target, matching the
/// standard "checkbox + row" multi-button List pattern.
struct FavoriteToggleButton: View {
    let isFavorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? Theme.accent : .secondary)
                .imageScale(.medium)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityAddTraits(isFavorite ? [.isSelected] : [])
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

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 36

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
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

// MARK: - Card

/// The one surface style for grouped content on the new screens.
struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Spacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.md) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Goal colour

extension TodaySummary.GoalState {
    /// One mapping from "how close to target" to colour, shared by every
    /// ring and bar.
    func tint(base: Color) -> Color {
        switch self {
        case .under, .noGoal: return base
        case .onTarget: return Theme.success
        case .over: return Theme.over
        }
    }
}

// MARK: - Calorie ring colour (fix-testing-feedback-quick-wins)

extension CalorieBand {
    /// The home calorie ring's stepped scale (today-dashboard spec). Only
    /// the ring uses this; the macro bars and meal cards keep the coarser
    /// `GoalState.tint` above. Reuses existing tokens where one already
    /// means the right thing; yellow and red have no token of their own, so
    /// they are defined here, next to the only place that draws them.
    var tint: Color {
        switch self {
        case .low: return Theme.grace
        case .building, .slightlyOver: return Theme.ember
        case .approaching: return Color(red: 0.96, green: 0.79, blue: 0.18)
        case .onTarget: return Theme.success
        case .over: return Color(red: 0.86, green: 0.24, blue: 0.23)
        }
    }

    /// Spoken with the ring's value, so the colour's meaning isn't
    /// sight-only (config.yaml's accessibility baseline).
    var accessibilityDescription: String {
        switch self {
        case .low: return "under half of target"
        case .building: return "building toward target"
        case .approaching: return "approaching target"
        case .onTarget: return "on target"
        case .slightlyOver: return "slightly over target"
        case .over: return "well over target"
        }
    }
}

// MARK: - ProgressRing

/// A circular progress ring with content in the middle.
struct ProgressRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 12
    var tint: Color = Theme.accent
    @ViewBuilder var center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: fraction)
                // A tint step (e.g. the home ring crossing into its green
                // goal band) cross-fades rather than snapping; an instant
                // change under Reduce Motion, same as the fill above.
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: tint)
            center()
        }
    }
}

// MARK: - MacroBar

/// "Protein 42 / 120 g" with a thin bar underneath.
struct MacroBar: View {
    let title: String
    let progress: MacroProgress
    let unit: String
    let tint: Color
    var compact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(valueText)
                    .font(compact ? .caption.monospacedDigit() : .macroValue)
                    .foregroundStyle(.primary)
            }
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(height: compact ? 4 : 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(progress.state.tint(base: tint))
                            .frame(width: proxy.size.width * (progress.fraction ?? 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: progress.fraction)
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityText)
    }

    private var valueText: String {
        let consumed = progress.consumed.wholeNumberText
        guard let goal = progress.goal else { return "\(consumed) \(unit)" }
        return "\(consumed) / \(goal.wholeNumberText) \(unit)"
    }

    private var accessibilityText: String {
        let consumed = progress.consumed.wholeNumberText
        guard let goal = progress.goal else { return "\(consumed) \(unit)" }
        return "\(consumed) of \(goal.wholeNumberText) \(unit)"
    }
}

// MARK: - NutrientRow / NutritionBreakdownSections

// implement-micronutrients (2026-09-22): promoted out of MealDetailView.swift
// (was `private struct NutrientRow` there) so `LogEntryConfirmView`'s new
// per-serving nutrition breakdown can reuse the exact same row styling
// instead of a second, subtly-different one -- config.yaml's "small,
// composable views... makes adding the next thing cheap" principle.

/// One nutrient's name + amount, e.g. "Vitamin D  3.4 µg" -- indented and
/// de-emphasized when `NutrientKind.isSubNutrient` (fiber under carbs).
struct NutrientRow: View {
    let nutrient: NutrientAmount

    var body: some View {
        HStack {
            Text(nutrient.kind.displayName)
                .font(nutrient.kind.isSubNutrient ? .subheadline : .body)
                .foregroundStyle(nutrient.kind.isSubNutrient ? .secondary : .primary)
                .padding(.leading, nutrient.kind.isSubNutrient ? Theme.Spacing.md : 0)
            Spacer()
            Text("\(nutrient.value.formatted(.number.precision(.fractionLength(0...1)))) \(nutrient.kind.unit)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A food/serving's full nutrient panel, grouped into Form/List `Section`s
/// by `NutrientKind.group` (design ask: "Group by type (vitamins vs.
/// minerals)... if that reads better than one flat list" -- it does, once
/// Open Food Facts's richer panel is in the mix: a single ungrouped list of
/// ~30 rows is much harder to scan than four short, labeled ones). Calories
/// is excluded -- every call site already shows it more prominently nearby
/// (`LogEntryConfirmView`'s calorie row, `MealDetailView`'s ring).
///
/// Emits `Section`s directly (not wrapped in a `List`/`Form` itself) so it
/// drops straight into an existing `Form { ... }` body, the same way
/// `MealDetailView`'s own "Nutrients" `Section` already does -- this is
/// deliberately NOT a new parallel screen, per this change's "prefer
/// extending what exists" constraint. A group with nothing present is
/// omitted entirely, same "never a fabricated zero" rule every other
/// nutrient display in this codebase already follows.
struct NutritionBreakdownSections: View {
    let nutrients: [NutrientAmount]

    private var groupedSections: [(group: NutrientGroup, items: [NutrientAmount])] {
        NutrientGroup.allCases.compactMap { group in
            let items = nutrients.filter { $0.kind.group == group && $0.kind != .calories }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        ForEach(groupedSections, id: \.group.rawValue) { section in
            Section(section.group.displayName) {
                ForEach(section.items) { item in
                    NutrientRow(nutrient: item)
                }
            }
        }
    }
}

// MARK: - StatTile

struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.streakNumber)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - DaySwitcher

/// "‹ Today ›" with a jump back to today.
struct DaySwitcher: View {
    let date: Date
    let isToday: Bool
    let onStep: (Int) -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                onStep(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous day")

            Spacer(minLength: 0)
            VStack(spacing: 0) {
                Text(title)
                    .font(.headline)
                if !isToday {
                    Button("Back to today", action: onToday)
                        .font(.caption.weight(.semibold))
                }
            }
            Spacer(minLength: 0)

            Button {
                onStep(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
        .tint(Theme.accent)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
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

#Preview("FavoriteToggleButton") {
    HStack {
        FavoriteToggleButton(isFavorite: false, action: {})
        FavoriteToggleButton(isFavorite: true, action: {})
    }
}

#Preview("EmptyStateView") {
    EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: "Try a different search term.")
}
