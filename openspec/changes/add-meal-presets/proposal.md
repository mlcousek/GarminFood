## Why

Logging a recurring multi-ingredient meal (a homemade breakfast bowl, a protein shake + banana + oats, a soup made of three tracked ingredients) currently means repeating the same search-and-confirm flow once per ingredient, every single time, even though the combination never changes. `add-food-log-core`'s own proposal named this out of scope at the time ("Recipe or multi-ingredient meal building. A meal here is one or more independently-logged food entries sharing a meal type, not a composed recipe") — the owner has now explicitly asked for exactly that: "create my own foods from multiple ingredients so it is presetted and I only log the meal."

## What Changes

- Add a **meal preset**: a named, saved group of ingredients (each a real catalog/Open-Food-Facts-matched food, or one of the user's own custom foods), each with its own quantity — created and edited from a dedicated editor screen.
- Add **one-tap meal logging**: confirming a preset enqueues one outbox entry per ingredient, all sharing the same meal type, date, and timestamp — durably and immediately, with the same zero-network-wait guarantee every other log-entry path in this app already has.
- Add a **"Portions" scale** on the confirm screen, so a smaller or larger serving of the same preset (e.g. "I only ate half the soup") doesn't require a different preset.
- Surface presets from two places: `FoodCatalogView`'s "Your meals" section (create/edit/delete) and a "Log a meal" shelf on the Today tab (one-tap, mirroring the existing "Log again" quick-pick shelf).

## Capabilities

### New Capabilities

- `meal-presets` — creating, editing, deleting, and logging a named multi-ingredient meal in one action.

### Modified Capabilities

- `food-catalog` — `FoodCatalogView` gains a "Your meals" section and an ingredient-picking mode reused by the preset editor. (See `add-food-log-core`'s existing capability — this change extends its UI, it does not replace it.)
- `food-log-entry` — `LogEntryCoordinator` gains `confirmMealPreset`, built entirely on its existing `confirm`/`confirmCustomFood` methods (unchanged), so a preset ingredient is logged exactly as if it had been logged on its own.

## Non-goals

- **A single aggregated Garmin food per preset.** Logging a preset writes N separate food-log entries (one per ingredient), not one combined "meal" food. Building that would mean depending on `GarminClient.createCustomFood`'s still-unconfirmed request/response shape for the aggregate case too, for no real benefit — see design.md D1.
- **Recipe scaling by weight/yield** (e.g. "this recipe makes 4 servings, I ate 1"). The "Portions" field scales the whole preset by a simple multiplier; per-serving-of-N recipe math is a possible future refinement, not built here.
- **Sharing presets between devices/accounts.** A preset is a local JSON file, same as custom foods and usage history — no sync capability is added by this change.
- **Editing an ingredient's own nutrition values.** A preset ingredient is a snapshot of an existing `Food`/`Serving` (or custom food) picked from the catalog; this change doesn't add a way to hand-edit an ingredient's macros in place (use the existing custom-food editor for that, then add the result as an ingredient).

## Impact

Affected surfaces: a new `MealPreset`/`MealPresetStore` in `FoodLogCore`, a new `confirmMealPreset` method on `LogEntryCoordinator`, two new screens (`MealPresetEditorView`, `MealPresetConfirmView`) in the `GarminFood` app target, and additive changes to `FoodCatalogView` (a new `Mode` case, a new list section) and `TodayView` (a new shelf). No changes to `GarminKit` — every ingredient logs through the exact same `Outbox.logFood` call path that already exists and is verified.

**Depends on**: `add-food-log-core` (extends its catalog UI and log-entry coordinator) and, for custom-food ingredients, the existing custom-food fallback path from that same change.

**Unblocks**: nothing further planned.
