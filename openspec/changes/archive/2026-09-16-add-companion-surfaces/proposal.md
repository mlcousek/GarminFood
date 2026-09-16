## Why

The owner already runs a substantial Obsidian vault with a Garmin sync pipeline and a Nutrition dashboard, and it has been silently broken since the day it was written: `scripts/lib/garmin.mjs`'s `getNutritionLog()` calls `/nutrition-service/food/log/date/{date}`, which returns 404 (confirmed 2026-09-14), and its `catch { return null }` reports that as "no nutrition data" rather than "this endpoint doesn't exist." Once `establish-garmin-nutrition-contract` finds the real route, fixing this is small, isolated, and gives the owner a working nutrition dashboard immediately — independent of whether the iOS app ever ships.

## What Changes

- Fix `getNutritionLog()` in the vault's `scripts/lib/garmin.mjs` to call the route discovered by `establish-garmin-nutrition-contract`, instead of the confirmed-dead guess.
- Fix `sync-nutrition.mjs`'s response parsing to match the real payload shape (currently a defensive guess with many `??` fallbacks against a shape nobody had ever seen).
- Add the same loud-vs-quiet failure distinction used throughout this project: a 404 on the corrected route logs a visible warning, not silent nothing.
- No other changes to the vault's sync pipeline, dashboard rendering, or file layout — this is a two-function fix, not a redesign.

## Capabilities

### New Capabilities

- `vault-nutrition-bridge` - keeping the Obsidian vault's existing nutrition sync correctly wired to Garmin's real food-log route.

### Modified Capabilities

None. (The vault's sync pipeline predates this OpenSpec project and has no existing spec of its own; this introduces the first one for its nutrition slice.)

## Non-goals

- **Any change to the iOS app.** This change is entirely inside the existing Node.js vault tooling and does not depend on `add-food-log-core` or `add-glanceable-surfaces` existing.
- **Changing the vault's Nutrition dashboard UI.** The dataviewjs rendering already works against the frontmatter fields; only the fields' source of truth is being fixed.
- **General vault refactoring.** Touches exactly the two functions named above.

## Impact

Affected files: `Jirkas_world/scripts/lib/garmin.mjs` (`getNutritionLog()`), `Jirkas_world/scripts/sync-nutrition.mjs` (`parseNutrition()`, `parseMeals()`).

**Depends on**: `establish-garmin-nutrition-contract`. Cannot be done before the real route and payload shape are known — that is the entire point of this change existing.

**Unblocks**: nothing further planned. This can run at any point after its dependency, in parallel with the iOS-side changes, since it touches an entirely separate codebase.
