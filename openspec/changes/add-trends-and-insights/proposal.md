## Why

Today, Weight and Hydration each get their own trend chart, and the Today
screen shows a single day's macros against goal -- but there is nowhere in
the app to see "how have my calories/protein/carbs/fat actually tracked
against goal over the last month" or "how consistent has my hydration been,
not just today's total." Both are pure derivatives of data this app either
already fetches (food logs, via a cheaper multi-day route than the one
currently used per-day) or already stores locally (hydration entries) --
this is a read-only insights screen, not a new kind of data.

## What Changes

- Add `GarminClient.calorieSummaryDaily(startDate:endDate:)`
  (`GET /nutrition-service/calorie/summary/daily`), a route already
  confirmed live in `docs/garmin-routes.json` (2026-09-14, as a standalone
  probe) but never actually called by this project's own code until now. It
  returns a whole date range's daily calorie/macro totals AND goals in one
  call, versus one `dailyFoodLog` call per day -- the only new Garmin
  traffic this change adds, and it is a READ with no write-contract
  concerns.
- Add `MacroTrendLoader` (`GarminFood/Trends/`), an app-layer loader
  (mirroring `WeightLoader`'s shape) that fetches ~30 days of macro data on
  demand, only while the Trends screen is open -- not part of the
  foreground refresh batch every other loader participates in, since a
  30-day history has no use outside this one screen.
- Add `HydrationHistory.streak(for:goalML:on:calendar:)` to
  `FoodLogCore/HydrationTracking.swift` -- a pure, local "consecutive days
  meeting the goal" count, deliberately simpler than `Gamification`'s
  grace-day food streak (no forgiveness for a missed day), since
  `FoodLogCore` cannot depend on `Gamification`.
- Add the Trends screen (`GarminFood/Trends/TrendsView.swift` +
  `TrendsComponents.swift`): a ~30-day calorie/protein/carbs/fat
  actual-vs-goal line chart from the new route, and a hydration streak stat
  plus a ~21-day daily-total bar chart against the local hydration goal,
  computed entirely from data already on the device.
- Add a `TrendsSummaryCard` entry point on the Progress tab
  (`ProgressViews.swift`'s `ProgressHomeView`), matching the existing
  `WeightSummaryCard`/`HydrationSummaryCard` pattern exactly.

## Capabilities

### New Capabilities

- `trends-and-insights` - the Trends screen: macro actual-vs-goal history
  and hydration streak/trend, read-only, computed from data this app
  already has a route or a local store for.

### Modified Capabilities

None. `GarminClient` gains one new read method; nothing existing changes
behavior.

## Non-goals

- **No new Garmin writes.** This entire change is read-only against Garmin
  (one new READ route) plus pure local computation (the hydration streak).
  Per `openspec/config.yaml`'s task rule ("never include a task that writes
  to the Garmin account before the write contract is documented"), nothing
  here needs a write contract because nothing here writes.
- **No grace-day forgiveness for the hydration streak.** That richer rule
  (`Gamification.StreakEngine`'s food streak) is XP-aware, persisted state
  scoped to `Gamification`, which `FoodLogCore` cannot depend on
  (`FoodLogCore` never imports `Gamification` -- the dependency runs the
  other way). A plain consecutive-day count is the right scope for a pure,
  local trend stat; a richer hydration streak is a future change if wanted.
- **No barcode-scanning or widget-extension changes.** Out of scope, owned
  by other in-flight work.
- **No new local persistence for macro trend data.** `calorieSummaryDaily`
  is a single stateless multi-day read; there is nothing to durably store,
  no outbox, no offline cache -- a fresh in-memory fetch each time the
  Trends screen opens is the correct design, not a shortcut.

## Impact

Affected surfaces: `GarminKit` (one new client method + two new response
models), `FoodLogCore` (one new pure function + its tests), `GarminFood`
(one new screen, one new loader, one new Progress-tab entry point),
`docs/garmin-routes.json` (one entry's notes updated to record that the
route is now actually implemented/called, not just probed).

**Depends on**: `add-weight-tracking` and `add-hydration-tracking` (this
change's hydration half reads `HydrationStore`/`HydrationLoader`, both
introduced there) and the nutrition-day boundary work in
`add-app-shell-and-meal-dashboard` (`NutritionDayBoundary`, reused here for
the macro trend's date range).

**Unblocks**: nothing planned; this is a leaf feature.
