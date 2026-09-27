## 40. Garmin custom-meal write (experimental)

- [x] 40.1 Added `CustomMealItemInput`/`CreateCustomMealRequest`/`CreateCustomMealResponse` (`ios/GarminKit/Sources/GarminKit/GarminModels.swift`), reusing `FoodLogWriteBody`'s confirmed field vocabulary per design.md D1.
- [x] 40.2 Added `GarminClient.createCustomMeal(name:items:)`, injecting `regionCode`/`languageCode` internally (not caller-supplied), matching `createCustomFood`'s existing public API shape.
- [x] 40.3 Unit tested (`CreateCustomMealRequestTests.swift`): request encodes the expected field names/values, response decodes the presumed `{customMealId}` shape.

## 41. Meal-preset data model

- [x] 41.1 Added `garminCustomMealId`/`garminSyncedAt` to `MealPreset` (`ios/FoodLogCore/Sources/FoodLogCore/MealPreset.swift`).
- [x] 41.2 Added `MealPreset.hasUnsyncableIngredients`, per design.md D2.
- [x] 41.3 Unit tested (`MealPresetTests.swift`): `false` for an all-catalog preset, `true` once a custom-food ingredient is added.

## 42. Editor UI

- [x] 42.1 Added a "Garmin" section to `MealPresetEditorView` (only for an already-saved preset with ingredients): sync status, an explanation when unsyncable, and a confirmation-gated "Sync to Garmin (experimental)" / "Re-sync" action, per design.md D3.
- [x] 42.2 Wired `DiagnosticsLog` on sync failure, matching `add-reminders-and-diagnostics`'s established pattern.
- [x] 42.3 `save()` persists `garminCustomMealId`/`garminSyncedAt` alongside the preset's other fields.

## 43. Documentation

- [x] 43.1 Updated `docs/garmin-routes.json`'s `createCustomMeal` entry: status, evidence, and what this change actually built.
- [x] 43.2 This change's own proposal/design/specs/tasks docs.
