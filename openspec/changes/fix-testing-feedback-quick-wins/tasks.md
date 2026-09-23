## 1. Picker-mode fixes (food-catalog)

- [ ] 1.1 Route the Quick pick `onTap` through a mode-aware path:
  - `.pickIngredient` calls `onPick(food, serving, customDraftIfAny)` and dismisses.
  - `.logFood` opens the confirm screen, as today.
  - A custom food on the shelf keeps its `CustomFoodDraft`.
- [ ] 1.2 Show the Open Food Facts section in `.pickIngredient`. Give `MatchConfirmationView` a picker variant that returns the matched Garmin food and serving to `onPick` instead of logging.
- [ ] 1.3 Make custom foods searchable by name while the query is non-empty, in every mode. Match is diacritic- and case-insensitive substring; this is interim until `rebuild-food-search` replaces it.

## 2. Today dashboard

- [ ] 2.1 GarminKit: add the `DailyUserSummary` model (activeKilocalories, bmrKilocalories, totalKilocalories, all optional) and `GarminClient.dailyUserSummary(date:)` for the route confirmed 2026-09-23. Add a decode test built from the probed payload.
- [ ] 2.2 Base the Target and the ring fraction on the base goal (`calories`), not `adjustedCalories`. Update the `MealDashboard` tests.
- [ ] 2.3 Add a pure `CalorieBand` function (percentage → band) in FoodLogCore. Add a boundary test at every step: 49.9, 50, 79.9, 80, 94.9, 95, 105, 105.1, 115, 115.1.
- [ ] 2.4 Map `CalorieBand` to theme colours. Animate the ring tint change, respecting Reduce Motion.
- [ ] 2.5 Add the "Active today: N kcal" line under the Target. Load it for the selected day and hide it on failure.

## 3. Profile

- [ ] 3.1 `ProfileHeader` prefers `fullName`, then `displayName`, then "GarminFood".

## 4. Verify

- [ ] 4.1 CI is green: `swift test` for GarminKit/FoodLogCore, plus xcodebuild.
- [ ] 4.2 On device:
  - A Quick pick added as an ingredient is added, not logged.
  - An OFF product can be added as an ingredient.
  - Profile shows the name.
  - The ring colour and the "Active today" line are correct.
