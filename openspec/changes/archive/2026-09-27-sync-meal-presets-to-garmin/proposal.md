## Why

`add-meal-presets` deliberately logs each ingredient as its own separate Garmin entry rather than one combined meal (design.md D1 of that change), because Garmin's own "custom meal" write route was unconfirmed. Research prompted directly by the owner ("look on how it works in garmin... there are also meals") found real evidence this concept is not hypothetical: this account's own `GET /nutrition-service/food/logs/{date}` data already carries a real `customMealId` (185179), created by the official Garmin Connect Mobile app — Garmin Connect genuinely has a native grouped-meal feature, this project just never called its write route.

## What Changes

- Add `GarminClient.createCustomMeal(name:items:)` (`POST /nutrition-service/customMeal`) — a guessed request body, same risk tier as `createCustomFood`, gated behind an explicit user action, never called automatically.
- Add a "Sync to Garmin (experimental)" action to the meal-preset editor for an already-saved preset: sends its ingredients as one named Garmin meal, stores the returned `customMealId` locally, and is available again as "Re-sync" afterward.

## Non-goals

- **Attaching logged food entries to the created `customMealId`.** `FoodLogWriteBody`'s confirmed write contract (the route this project actually verified) has no `customMealId` field — only the READ side has been observed carrying one. Logging a preset still writes N separate entries via the existing, verified path; this change only creates the meal TEMPLATE in Garmin, it doesn't yet (and may never, depending on what's confirmed) tie individual logged entries to it.
- **Custom-food ingredients.** A custom food only exists by proxy through its backing food; deriving that indirection's own region/source reliably would meaningfully complicate an already-unconfirmed route. A preset containing one shows a plain explanation instead of a sync button.
- **Deleting or updating a synced Garmin meal.** Only creation is implemented; `DELETE /nutrition-service/customMeal/{customMealId}` is documented but not built.

## Impact

Affected surfaces: `GarminKit` gains `CreateCustomMealRequest`/`CustomMealItemInput`/`CreateCustomMealResponse` (GarminModels.swift) and `GarminClient.createCustomMeal`; `FoodLogCore`'s `MealPreset` gains `garminCustomMealId`/`garminSyncedAt` fields and `hasUnsyncableIngredients`; `MealPresetEditorView` gains the sync UI. No changes to the confirmed `createFoodLogEntry`/`Outbox` write path — logging a preset is unaffected whether or not it's ever synced.

**Depends on**: `add-meal-presets` (extends its editor and data model).

**Unblocks**: attaching logged entries to a synced meal, if `customMealId` on the write side is ever confirmed — not planned until that happens.
