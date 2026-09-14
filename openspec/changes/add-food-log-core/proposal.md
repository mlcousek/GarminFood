## Why

Every fast entry point — a Control, a widget, a Siri phrase — needs somewhere to point at: a food to log, a serving size, a meal. Garmin's own search (verified live 2026-09-14: `GET /nutrition-service/food/search?searchExpression=<term>`, FatSecret-backed, Czech terms included) is the natural catalog, but it is a network call, and the entire premise of this project is that logging never waits on one. This change builds the local model — favourites, recents, custom foods, and a fast search-and-pick flow — that everything else points at.

## What Changes

- Add a **food catalog**: search against Garmin's food database with a local cache of recent results, plus a **favourites** and **recents** list built from the user's own logging history (Garmin's search response already carries `isFavorite`/`isRecent` flags per result, but those reflect Garmin's own state — this change also tracks local usage frequency so favourites surface even before a round trip completes).
- Add **barcode scanning** via VisionKit, mapping the scanned EAN-13/UPC-A code to a Garmin food lookup, with the UPC-A leading-zero normalisation VisionKit requires.
- Add a **custom food** editor for items Garmin's FatSecret-backed database does not carry — common for regional Czech products.
- Add the **log-entry flow**: pick a food, pick a serving (Garmin returns several `nutritionContents` options per food — grams, "medium", "large" etc.), pick a meal, confirm. This is the flow every fast-entry surface in `add-glanceable-surfaces` ultimately triggers.
- Add **local storage** for the catalog cache, favourites/recents ranking, and custom foods — scoped to the app process; per `add-garmin-auth-and-sync`'s D3, this data is not shared with extensions via a file container, only via Garmin itself once synced.

## Capabilities

### New Capabilities

- `food-catalog` - searching, caching and locally ranking Garmin's food database, plus user-defined custom foods.
- `food-log-entry` - the confirm-and-commit flow that turns a chosen food and serving into a durable, queued log entry.

### Modified Capabilities

None.

## Non-goals

- **Delivering the entry to Garmin.** Owned by `add-garmin-auth-and-sync`'s `garmin-sync` capability; this change produces the entry and hands it off.
- **Fast-entry UI surfaces** (widgets, Controls, Siri). Owned by `add-glanceable-surfaces`. This change's flow is what those surfaces open into or trigger directly.
- **Nutrition goals, macro targets, or trend charts.** Out of scope entirely — Garmin Connect already does this, and duplicating it is not the point of a fast-logging companion.
- **Recipe or multi-ingredient meal building.** A meal here is one or more independently-logged food entries sharing a meal type, not a composed recipe.

## Impact

Affected surfaces: a new `FoodCatalog` module (search, cache, favourites/recents ranking, custom foods) and a `LogEntryFlow` module, both consuming `GarminKit` from `add-garmin-auth-and-sync` for the actual food-search network call.

**Depends on**: `establish-garmin-nutrition-contract` (for the confirmed food-search contract and, once found, the write contract's serving/meal-type shape) and `add-garmin-auth-and-sync` (for an authenticated client to search with and an outbox to hand entries to).

**Unblocks**: `add-glanceable-surfaces` (needs a food and serving to log against), `add-companion-surfaces` (the vault dashboard can link back to recent local entries).
