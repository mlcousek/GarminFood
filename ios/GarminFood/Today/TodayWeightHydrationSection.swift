// TodayWeightHydrationSection.swift
//
// The "Weight & Water" section at the bottom of the Today screen
// (2026-09-22, owner request): both trackers already have a full screen
// (`Weight/WeightView.swift`, `Hydration/HydrationView.swift`) reached today
// only via the Progress tab (`ProgressViews.swift`'s `WeightSummaryCard`/
// `HydrationSummaryCard`) -- this adds a compact, second entry point right
// on the home screen, since weight and water are logged far more often than
// the Progress tab is opened. The water card goes further than a summary:
// it embeds `HydrationQuickAddRow` inline, so a glass of water can be logged
// without leaving Today at all -- the whole point of putting it here rather
// than just linking to the Progress tab's existing cards.
//
// Deliberately new, Today-scoped views rather than reusing `ProgressViews.
// swift`'s `WeightSummaryCard`/`HydrationSummaryCard` (both `private` to
// that file) or exporting them: those two are laid out as a `CardHeader`
// (icon + uppercase title + chevron) over a big number, tuned for a
// tap-to-open list of many such cards on the Progress tab. This section
// wants the actual hero content (`WeightHeroCard`/`HydrationHeroCard`, the
// same views `WeightView`/`HydrationView` themselves open with) plus, for
// water, the live quick-add row beneath it -- a different enough shape that
// widening `ProgressViews.swift`'s private types' access level would just
// be a same-visuals detour, not real reuse. Both cards below instead
// compose the already-shared `WeightHeroCard`/`HydrationHeroCard`/
// `HydrationQuickAddRow` from `WeightComponents.swift`/
// `HydrationComponents.swift`, so the number formatting, trend badge and
// quick-add amounts stay in exactly one place.
//
// Quick-add here calls `environment.hydrationLogCoordinator.
// logHydration(valueInML:)` then `environment.hydrationLogged()` -- the
// exact same pair `HydrationView.quickAdd(_:)` calls, so logging from Today
// is local-first and drains in the background identically (CLAUDE.md:
// "Local-first, zero-network-wait").

import SwiftUI
import FoodLogCore
import GarminKit

/// Wraps `WeightHeroCard`'s content in a `NavigationLink` to `WeightView()`,
/// the same "whole card is one tap target" shape `FastingHomeCard`/
/// `ProgressStrip` (`TodayView.swift`) already use for their own Today-tab
/// summary rows.
struct TodayWeightCard: View {
    let latest: WeightEntry?
    let previous: WeightEntry?

    var body: some View {
        NavigationLink {
            WeightView()
        } label: {
            HStack {
                WeightHeroCard(latest: latest, previous: previous)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens weight tracking")
    }
}

/// `HydrationHeroCard`'s content, tappable through to `HydrationView()`,
/// with `HydrationQuickAddRow` beneath it as a SIBLING of the
/// `NavigationLink` -- not nested inside its label -- so the quick-add
/// buttons stay independently tappable rather than being swallowed by the
/// link's own tap target (the same nested-tappable-control hazard
/// `FavoriteToggleButton`'s doc comment in `DesignSystem/Components.swift`
/// already calls out for buttons-in-rows).
struct TodayHydrationCard: View {
    let todayTotalML: Double
    let goalML: Double
    let onQuickAdd: (Double) -> Void
    let onCustom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            NavigationLink {
                HydrationView()
            } label: {
                HStack {
                    HydrationHeroCard(todayTotalML: todayTotalML, goalML: goalML)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens water tracking")

            HydrationQuickAddRow(onAdd: onQuickAdd, onCustom: onCustom)
        }
        .card()
    }
}

#Preview("TodayWeightCard") {
    NavigationStack {
        TodayWeightCard(
            latest: WeightEntry(weightKg: 75.5, loggedAt: Date()),
            previous: WeightEntry(weightKg: 76.8, loggedAt: Date().addingTimeInterval(-86_400))
        )
        .padding()
    }
}

#Preview("TodayHydrationCard") {
    NavigationStack {
        TodayHydrationCard(todayTotalML: 750, goalML: 2000, onQuickAdd: { _ in }, onCustom: {})
            .padding()
    }
}
