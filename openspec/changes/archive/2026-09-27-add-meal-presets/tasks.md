## 32. Meal preset domain model

- [x] 32.1 Implemented `MealPreset`/`MealPresetIngredient` (`ios/FoodLogCore/Sources/FoodLogCore/MealPreset.swift`): an ingredient snapshots a full `Food`/`Serving` (plus, for a custom-food ingredient, the full `CustomFoodDraft`) at add-time rather than an id, per design.md D2, so a preset stays loggable offline and survives its source food changing elsewhere.
- [x] 32.2 Implemented `MealPresetStore`, a JSON-file-backed actor mirroring `CustomFoodStore`'s exact pattern.
- [x] 32.3 Unit tested (`MealPresetTests.swift`): totals summing across ingredients at their own quantity, totals scaling by a servings multiplier, a `nil`-serving-calories ingredient contributing `nil`, and the store's upsert/delete/persist-across-instances behavior.

## 33. Log-entry coordinator

- [x] 33.1 Added `LogEntryCoordinator.confirmMealPreset(_:servingsMultiplier:mealType:date:now:)` (`ios/FoodLogCore/Sources/FoodLogCore/LogEntryCoordinator.swift`), built entirely on the existing `confirm`/`confirmCustomFood` methods, unchanged — per design.md D1/D3.
- [x] 33.2 Unit tested (`LogEntryCoordinatorTests.swift`): one outbox entry enqueued per ingredient sharing meal type/date, the servings multiplier scaling every ingredient together, and a custom-food ingredient logging as its backing food while usage history still tracks the custom food's own identity.

## 34. Meal preset UI

- [x] 34.1 Added `FoodCatalogView.Mode.pickIngredient` (`ios/GarminFood/Catalog/FoodCatalogView.swift`) — reuses the existing catalog/search/custom-food browsing UI, intercepting the final pick instead of navigating to the normal confirm screen.
- [x] 34.2 Built `MealPresetEditorView` (`ios/GarminFood/MealPreset/MealPresetEditorView.swift`): name, an editable ingredient list (added via the `pickIngredient` mode above), per-ingredient quantity, a running nutrition total, and a note. Handles both creating a new preset and editing an existing one (`existing:` parameter) in the same form.
- [x] 34.3 Built `MealPresetConfirmView` (`ios/GarminFood/MealPreset/MealPresetConfirmView.swift`): preset summary, per-ingredient breakdown, a "Portions" multiplier, meal type/date pickers (defaulting the same way `LogEntryConfirmView` does), and a "Log it" action calling `confirmMealPreset`.
- [x] 34.4 Added a "Your meals" section to `FoodCatalogView` (create/edit/delete via swipe actions) and a "Log a meal" shelf to `TodayView`, mirroring the existing "Log again" quick-pick shelf's shape and interaction (`MealPresetComponents.swift`).
- [x] 34.5 Wired `MealPresetStore` into `AppServices`/`AppEnvironment`, following the existing one-instance-per-store composition-root pattern.

## 35. Documentation

- [x] 35.1 Added a repo-root `CLAUDE.md` (none existed) summarizing architecture, hard constraints, and conventions for future sessions.
- [x] 35.2 This change's own proposal/design/spec/tasks docs.
