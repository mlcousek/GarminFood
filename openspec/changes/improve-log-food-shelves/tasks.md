## 1. Domain

- [x] 1.1 Add `UsageEvent.mealType: MealType?` (optional, backward-compatible) and a `record(... mealType:)` parameter. Pass it from `LogEntryCoordinator.confirm`, `confirmCustomFood` and `confirmMealPreset`. Test that an old JSON file decodes.
  - `confirmMealPreset` records it through `confirm`/`confirmCustomFood`, so every ingredient carries the preset's meal. Tests: `UsageEventCodingTests`, three new cases in `LogEntryCoordinatorTests`.
- [x] 1.2 Add `MealUsualRanker.rank(events:mealType:now:limit:)`: frequency with a 14-day half-life decay, minimum 3 events for that meal. Add tests.
  - Groups by food, not by (food, serving); a card re-logs the serving and quantity most recently used at that meal. Events with no meal type never count. Tests: `MealUsualRankerTests`.
- [x] 1.3 Add `RecentRanker.rank(events:limit:)`: distinct by `foodId`, newest first. Add tests.
  - Orders by `timestamp` (when logged), not `nutritionDay`. Tests: `RecentRankerTests`.
- [x] 1.4 Verify that Gamification still decodes usage history. Run its tests.
  - Checked by reading: Gamification only builds `UsageEvent` through the labelled init (new parameter is defaulted) and decodes it with `Codable` (the new key is optional). Added `StreakHistoryTests.testUsageFilesWithTheNewMealTypeFieldStillDecodeAndCount`. Challenges keep the time-of-day bucket on purpose (see `ChallengeTemplates.swift`'s header). The tests themselves run in CI (3.1); there's no local Swift toolchain.

## 2. UI

- [x] 2.1 Build a shared `FoodShelf`/`FoodShelfCard` component and move `QuickPickShelf` and `FavoritesShelf` onto it.
  - `Catalog/FoodShelf.swift`. `MealPresetShelf` (also used by Today's "Log a meal") moved onto it too.
- [x] 2.2 Add a Meals shelf of preset cards: tap to confirm, context menu for Edit and Delete. Remove the vertical "Your meals" list.
  - Edit and Delete are also VoiceOver custom actions. The now-unused `MealPresetRow` was removed.
- [x] 2.3 Add the Usual-for-meal shelf, with the meal taken from `logContext`, else the default meal type.
  - The default is the same one `LogEntryConfirmView` uses: Garmin's meal windows when that preference is on, the time-of-day table otherwise.
- [x] 2.4 Add the Recent shelf.
- [x] 2.5 In picker mode, every shelf tap goes to `onPick`, and the Meals shelf is hidden.
  - Quick pick, Usual and Recent go through `selectQuickPick`; Favorites through `select`. All shelves stay hidden in `pickBackingFood`, as before.
- [x] 2.6 VoiceOver labels on all cards, and Dynamic Type layout checked.
  - Checked by reading only. Card width scales with Dynamic Type (`@ScaledMetric`, capped at 280 pt), names get up to 4 lines at accessibility sizes, and cards in a shelf share one height. Still needs an on-device look at the largest sizes (3.2).

## 3. Verify

- [ ] 3.1 CI green.
- [ ] 3.2 On device: check the shelf order, that the breakfast and dinner shelves differ, that Recent updates after logging, and that preset cards work.
  - "Usual for <meal>" starts empty after the upgrade. Events logged before this build have no meal type, so it appears once a meal has 3 new logs.
