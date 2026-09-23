## 1. Domain

- [ ] 1.1 Add `UsageEvent.mealType: MealType?` (optional, backward-compatible) and a `record(... mealType:)` parameter. Pass it from `LogEntryCoordinator.confirm`, `confirmCustomFood` and `confirmMealPreset`. Test that an old JSON file decodes.
- [ ] 1.2 Add `MealUsualRanker.rank(events:mealType:now:limit:)`: frequency with a 14-day half-life decay, minimum 3 events for that meal. Add tests.
- [ ] 1.3 Add `RecentRanker.rank(events:limit:)`: distinct by `foodId`, newest first. Add tests.
- [ ] 1.4 Verify that Gamification still decodes usage history. Run its tests.

## 2. UI

- [ ] 2.1 Build a shared `FoodShelf`/`FoodShelfCard` component and move `QuickPickShelf` and `FavoritesShelf` onto it.
- [ ] 2.2 Add a Meals shelf of preset cards: tap to confirm, context menu for Edit and Delete. Remove the vertical "Your meals" list.
- [ ] 2.3 Add the Usual-for-meal shelf, with the meal taken from `logContext`, else the default meal type.
- [ ] 2.4 Add the Recent shelf.
- [ ] 2.5 In picker mode, every shelf tap goes to `onPick`, and the Meals shelf is hidden.
- [ ] 2.6 VoiceOver labels on all cards, and Dynamic Type layout checked.

## 3. Verify

- [ ] 3.1 CI green.
- [ ] 3.2 On device: check the shelf order, that the breakfast and dinner shelves differ, that Recent updates after logging, and that preset cards work.
