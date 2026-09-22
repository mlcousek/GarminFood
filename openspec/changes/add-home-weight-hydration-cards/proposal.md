## Why

Weight tracking (`add-weight-tracking`) and hydration tracking
(`add-hydration-tracking`) both shipped with their own full screens, but the
only way to reach either today is a tap through the Progress tab
(`ProgressViews.swift`'s `WeightSummaryCard`/`HydrationSummaryCard`). The
owner wants both visible at the bottom of the Today (home) screen instead —
the screen already open dozens of times a day for food logging — so a
weigh-in or a glass of water doesn't need a detour through a different tab.
Water in particular is logged far more often, in smaller amounts, than
weight is; making it a one-tap action right on Today is the actual point,
not just a second link to the same screen.

## What Changes

- Add a "Weight & Water" section to the bottom of `TodayView`'s scroll view
  (below the existing "Log a meal" preset shelf, the last thing before the
  `AppSignatureView` footer) — two new, Today-scoped cards
  (`Today/TodayWeightHydrationSection.swift`):
  - `TodayWeightCard` — `WeightHeroCard`'s existing content (current weight
    + trend delta badge, no chart), the whole card a `NavigationLink` to
    `WeightView()`.
  - `TodayHydrationCard` — `HydrationHeroCard`'s existing content (today's
    total against the local daily goal) as a tappable `NavigationLink` to
    `HydrationView()`, with `HydrationQuickAddRow` (the 100/250/500 ml
    one-tap buttons + "Custom") inline beneath it as a sibling control, so a
    drink can be logged without leaving Today at all.
- Quick-add on Today calls the exact same pair `HydrationView.quickAdd(_:)`
  already calls — `environment.hydrationLogCoordinator.
  logHydration(valueInML:)` then `environment.hydrationLogged()` — so
  logging from the home screen is local-first and drains in the background
  identically (CLAUDE.md: "Local-first, zero-network-wait"), with the same
  simple inline error alert on failure.
- The section always shows (unlike the quick-pick/meal-preset shelves above
  it, which hide when there's nothing to show yet): an empty weight/
  hydration history is itself useful information here, and the quick-add
  row is useful starting from zero history too.

## Capabilities

### Modified Capabilities

None. This reuses the existing `weight-tracking`/`hydration-tracking`
data model, loaders and log coordinators exactly as `WeightView`/
`HydrationView` already do — no new store, no new Garmin route, no change
to what either capability reads or writes. It is purely a second, additive
entry point into behavior that already exists, on a screen
(`meal-dashboard`) whose own spec already governs its section-by-section
layout but doesn't need a new requirement to add one more section to the
bottom of a `ScrollView` — the existing "day as Garmin Connect's food page"
requirements are unaffected, and nothing about how a day's meals are shown
changes. No `spec.md` delta is included for that reason.

### New Capabilities

None — deliberately scoped as UI-only reuse of two already-shipped
capabilities, not a new one.

## Non-goals

- **A weight/hydration chart or history list on Today.** That's what
  `WeightView`/`HydrationView` are for; the point of this card is a glance
  and a one-tap log, not a second copy of either full screen.
- **Custom-food creation or the Czech/OpenFoodFacts search.** Untouched;
  out of scope, handled by other changes in parallel.
- **A Garmin-synced hydration goal.** Still a local `@AppStorage` preference
  (`HydrationPreferenceKeys.dailyGoalML`), per `HydrationComponents.swift`'s
  own header — this change reads that same key, it doesn't add a new one.

## Impact

Affected surfaces: `ios/GarminFood/Today/TodayView.swift` (new section,
`AddHydrationSheet` presentation, quick-add error alert, one new
`@AppStorage` read already declared identically in `HydrationView`/
`ProgressHomeView`) and a new `ios/GarminFood/Today/
TodayWeightHydrationSection.swift` (`TodayWeightCard`, `TodayHydrationCard`).
No changes to `FoodLogCore`, `GarminKit`, `Gamification`, `AppServices.swift`
or `AppEnvironment.swift` — every store/loader/coordinator this reuses is
already wired there by `add-weight-tracking`/`add-hydration-tracking`.

**Depends on**: `add-weight-tracking`, `add-hydration-tracking` (already
merged to `main`).

**Unblocks**: nothing further planned.
