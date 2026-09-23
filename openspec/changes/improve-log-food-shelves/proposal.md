## Why

The owner likes the swipeable Quick pick shelf. They want the rest of the
empty-query Log Food screen built the same way, so the foods they actually eat
are one swipe away. Today the screen has these problems:

- Meal presets are a vertical list below custom foods.
- Nothing knows that breakfast looks different from dinner.
- There is no "what did I just have" row.

Decisions made in the grilling session on 2026-09-23:

- **Shelf order** is Quick pick → Favorites → Usual for <meal> → Meals →
  Recent.
- The shelves should be consistent swipeable cards.

## What Changes

The empty-query Log Food screen becomes five horizontal card shelves, in
this order, all built from one shared `FoodShelf` card component:

1. **Quick pick** is unchanged. Its ranking is recency × frequency.
2. **Favorites** is the existing shelf, restyled to the shared card.
3. **Usual for <meal>** is new. It shows the foods most often logged *for the
   meal being logged*, ranked by frequency with a recency decay, top 10.
   The meal comes from the log context when opened from a meal card, else from
   the existing time-of-day or Garmin meal-window default. The title follows
   the meal: "Usual for breakfast", "Usual for lunch", and so on. The shelf is
   hidden until that meal has at least 3 logged events.
4. **Meals** moves meal presets from the vertical list to cards. Each card
   shows the name, item count and kcal. Tap opens the existing preset confirm
   screen; long-press gives Edit and Delete.
5. **Recent** is new. It lists the last 10 distinct foods logged, newest first.

Supporting changes:

- `UsageEvent` gains an optional `mealType`. It is recorded on every confirm,
  including custom foods and preset ingredients. Old events decode with `nil`
  and don't count toward any meal's "Usual" shelf.
- "Your custom foods" stays as the vertical list under the shelves.
- Shelves that have no items are hidden.
- In picker mode (`.pickIngredient`), every shelf tap returns the food to the
  caller. This builds on the routing fix in `fix-testing-feedback-quick-wins`.
  The Meals shelf is hidden in picker mode because presets can't nest.

## Non-goals

- Search results layout: `rebuild-food-search`.
- Entry editing and copying a past meal: `add-log-entry-editing`.
- Syncing favorites or presets to Garmin: not needed here.

## Capabilities

### Modified Capabilities

- `food-catalog`: shelves layout, per-meal ranking, and the Recent shelf.

## Impact

- FoodLogCore:
  - `UsageEvent.mealType` is optional and backward-compatible. The
    Gamification package also reads this JSON, and optional-field decoding
    keeps it compatible.
  - `LogEntryCoordinator` passes `mealType` to `usageHistory.record`.
  - New pure rankers `MealUsualRanker` and `RecentRanker`, with tests.
- App: `FoodCatalogView` (empty-query section) and a new `FoodShelf`
  component that `QuickPickShelf`, `FavoritesShelf` and `MealPresetShelf`
  migrate onto.
- **Depends on**: `fix-testing-feedback-quick-wins` (picker tap routing).
- **Unblocks**: nothing.
