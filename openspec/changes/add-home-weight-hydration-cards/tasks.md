## 1. Today-scoped cards

- [x] 1.1 New `ios/GarminFood/Today/TodayWeightHydrationSection.swift`:
      `TodayWeightCard` (wraps `WeightHeroCard`'s existing content in a
      `NavigationLink` to `WeightView()`, same "whole card is the tap
      target" shape `FastingTodayCard`/`ProgressStrip` already use) and
      `TodayHydrationCard` (`HydrationHeroCard`'s content as a
      `NavigationLink` to `HydrationView()`, with `HydrationQuickAddRow` as
      a sibling of the link — not nested inside its label, to avoid the
      nested-tappable-control hit-testing hazard `FavoriteToggleButton`'s
      doc comment already calls out).
- [x] 1.2 Deliberately did NOT widen access on `ProgressViews.swift`'s
      `WeightSummaryCard`/`HydrationSummaryCard` (both `private`, and tuned
      for the Progress tab's own `CardHeader`-over-a-number layout, not this
      section's "actual hero content + inline quick-add" shape) — composed
      the already-shared `WeightHeroCard`/`HydrationHeroCard`/
      `HydrationQuickAddRow` from `WeightComponents.swift`/
      `HydrationComponents.swift` instead, so formatting/behavior stays in
      one place either way.

## 2. Wiring into Today

- [x] 2.1 `TodayView.swift`: added the "Weight & Water" `SectionHeader` +
      both cards as the last section before `AppSignatureView`, below the
      "Log a meal" preset shelf. Always shown, unlike the quick-pick/
      meal-preset shelves above it.
- [x] 2.2 Added `@AppStorage(HydrationPreferenceKeys.dailyGoalML)` (the
      same key `HydrationView`/`ProgressHomeView` already read) to supply
      `TodayHydrationCard`'s goal.
- [x] 2.3 Wired quick-add to `environment.hydrationLogCoordinator.
      logHydration(valueInML:)` + `await environment.hydrationLogged()`
      inside a `Task { }`, mirroring `HydrationView.quickAdd(_:)` exactly,
      with a `hydrationActionError` alert on failure (same copy/shape as
      `HydrationView`'s own).
- [x] 2.4 Wired "Custom" to a `.sheet` presenting `AddHydrationSheet()`
      inside a `NavigationStack`, matching `HydrationView`'s own
      presentation of the same sheet.
- [x] 2.5 Confirmed `environment.weightLoader`/`hydrationLoader` don't need
      a new refresh trigger: both are already refreshed by
      `AppEnvironment.refreshOnForeground()` on every launch/foreground, and
      `TodayView`'s existing `.refreshable` already calls
      `refreshOnForeground()` — the same umbrella call `ProgressHomeView`'s
      own `.refreshable` expands into `engine.refresh()` +
      `weightLoader.refresh()` + `hydrationLoader.refresh()` individually.
      No change needed to `TodayView`'s `.task` block either: by the time
      Today first appears, `ContentView`'s own launch-time
      `refreshOnForeground()` call has already populated both loaders.

## 3. Verification

- [x] 3.1 Re-read every touched/created file for syntax and type
      correctness (no local Swift compiler — CLAUDE.md's "no Mac"
      constraint). Actual correctness signal is CI (`xcodebuild` for the
      `GarminFood` app target) on push — not run as part of this change;
      flagged for the owner.
- [ ] 3.2 **NOT DONE HERE — needs CI + a sideloaded device build.** Confirm
      the app target builds, the new section renders correctly on Today
      below the meal-preset shelf, the quick-add buttons log instantly and
      show up in `HydrationView`'s history after, and both cards' taps open
      the right destination screen.
