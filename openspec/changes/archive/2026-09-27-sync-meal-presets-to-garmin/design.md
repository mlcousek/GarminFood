## Context

Two pieces of real evidence, neither a guess: (1) `POST /nutrition-service/customMeal` exists as a string literal in the decompiled Garmin Android client (docs/garmin-routes.json, found 2026-09-14); (2) this account's own real logged-food data already carries `customMealId: 185179` (docs/garmin-food-log-contract.md), proving the concept is live and used by Garmin's own app today. Neither piece tells us the WRITE request/response shape — only that the feature is real.

## Decisions

### D1 — Guess the request body from the confirmed sibling contract, not from scratch

`FoodLogWriteBody` (the CONFIRMED food-log write) already proves Garmin's nutrition-service writes key a food by `(foodId, servingId, source, regionCode, languageCode)` plus a quantity field. `CreateCustomMealRequest.Item` reuses that exact vocabulary rather than inventing new field names — the same reasoning `CreateCustomFoodRequest` already used for its own guess. `regionCode`/`languageCode` are injected by `GarminClient` internally (the same confirmed `"US"`/`"en"` constants), not exposed to callers, matching `createCustomFood`'s existing public API shape exactly.

### D2 — Custom-food ingredients are excluded, not worked around

A `MealPresetIngredient` backed by a `CustomFoodDraft` has no Garmin identity of its own — it only exists by proxy through its `backingFoodId`/`backingServingId` (add-food-log-core design.md D4). Resolving that indirection's own `source` (GARMIN vs FATSECRET) would need re-deriving inference logic that today only lives inside `FoodLogCore` (`FoodSource.garminFoodSource`, not exposed publicly) — a meaningful amount of new plumbing to support ONE MORE unconfirmed field on an already-fully-unconfirmed route. `MealPreset.hasUnsyncableIngredients` gates the sync action off entirely when this applies, with a plain explanation, rather than attempting a shakier resolution.

### D3 — Sync is a standalone action, not wired into logging

Confirming this route's real shape needs a human watching the result on a real device (this project's own established pattern for every unconfirmed write — `createCustomFood`'s original 400 was only found and fixed this way). Wiring it into the normal "Log it" flow would mean every future preset log either silently no-ops the sync or risks failing the whole confirm on an experimental route. Keeping it a separate, explicit, re-triable action in the editor means a failure here changes nothing about the preset's actual (already fully working) logging behavior.

## Risks / Trade-offs

- **The request shape is a genuine guess and may simply fail** → by design; the UI treats failure as an expected, non-alarming outcome ("this route is experimental and may not be supported"), and nothing else about the preset changes.
- **A successful `createCustomMeal` creates a real object in the user's Garmin account that this project has no delete path for** → `DELETE /nutrition-service/customMeal/{customMealId}` is documented (docs/garmin-routes.json) but explicitly out of scope here (see proposal.md); if this route is confirmed working, deletion is the natural next increment.
- **No real-device verification exists yet** → the owner cannot currently sideload (2026-09-22). This ships as inert-until-tapped, gated code so it's ready the moment they can test, rather than blocking on that timeline.
