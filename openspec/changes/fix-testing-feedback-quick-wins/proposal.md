## Why

The owner's on-device test pass (2026-09-23) found four small bugs and two
quick home-screen wins. They are all low-risk and independent of the larger
waves in the same plan. They ship first, as one PR, so the next sideload
already fixes what was annoying:

- **Picker only searches Garmin.** The meal-preset ingredient picker searches
  only Garmin's database. The Czech Open Food Facts section is hidden in
  picker mode, and custom foods can't be found by typing.
- **Quick pick logs instead of adding.** Tapping a Quick pick card while
  adding a meal ingredient logs the food instead of adding it to the meal.
  `FoodCatalogView`'s quick-pick `onTap` sets `logTarget` without checking
  `mode`.
- **Profile shows a UUID.** The Profile header shows a UUID instead of the
  owner's name. It prefers `socialProfile.displayName`, which is a UUID on this
  account (live-probed 2026-09-23), over `fullName`.
- **Target includes burned calories.** The home Target silently uses Garmin's
  `adjustedCalories`, which is the goal plus burned calories. The owner wants
  the fixed goal (2300), with the day's active calories shown under it for
  information only.
- **Ring colour.** The calorie ring stays orange until the owner is within
  ±10% of the goal. The owner wants a stepped colour scale, with green meaning
  95–105%.

## What Changes

- **Picker sources.** The ingredient picker searches the same sources as
  logging: Garmin, the Open Food Facts section, and custom foods matched by
  name. Picking an OFF product runs the existing Garmin-match flow and then
  returns the ingredient instead of logging it.
- **Picker taps.** Every tap in picker mode returns the food to the caller,
  whether it comes from a quick-pick card, a favorite, a custom food or a
  search result. None of these taps logs anything.
- **Profile name.** The Profile header shows `fullName`, then `displayName`,
  then "GarminFood".
- **Fixed Target.** The home Target shows the base `calorieGoal`, not
  `adjustedCalories`.
- **Active calories.** A new line, "Active today: N kcal", appears under the
  Target. It reads `activeKilocalories` from
  `GET /usersummary-service/usersummary/daily?calendarDate=`, which was
  live-confirmed on 2026-09-23. A past day shows that day's value. The line
  is hidden if the route fails.
- **Stepped ring colours**, by % of the Target eaten. The colour animates
  between steps and respects Reduce Motion.

  | % of Target | Colour |
  |---|---|
  | under 50% | cool grey-blue |
  | 50–80% | orange |
  | 80–95% | yellow |
  | 95–105% | green |
  | 105–115% | orange |
  | over 115% | red |

## Non-goals

- The Log Food screen's new shelves layout belongs to `improve-log-food-shelves`.
- Unified ranked search belongs to `rebuild-food-search`. This change only
  stops the picker from hiding the sources that already exist.
- Eat-back of active calories is out. The owner chose a fixed target
  (decision 2026-09-23).

## Capabilities

### Modified Capabilities
- `food-catalog`: picker-mode source parity and tap routing.

### New Capabilities
- `today-dashboard`: Target semantics, active calories, ring colour scale.

## Impact

- GarminKit: a new `DailyUserSummary` model (active/bmr/total kcal) and
  `GarminClient.dailyUserSummary(date:)`.
- FoodLogCore: `MealDashboard` gains a calorie colour band. It is a pure
  function and is unit-tested.
- App: `FoodCatalogView`, `MatchConfirmationView`, `ProfileView`, `TodayView`
  (`DaySummaryCard`), `Components` (ring tint).
- **Depends on**: nothing.
- **Unblocks**: `improve-log-food-shelves` and `rebuild-food-search`. Both
  build on the picker-mode routing fixed here.
