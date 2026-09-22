## Why

`docs/garmin-routes.json`'s `favoriteFoods` entry has sat as a dead end since
2026-09-14: `GET /nutrition-service/favorite/food` 405s, and the entry's own
notes called for a follow-up probe rather than giving up on it. This change
did that research properly -- checked every OSS Garmin Connect client this
project already trusts for an unconfirmed write contract (the same tier
`addWeighIn`/`addHydration` used), plus a broad GitHub code search for the
route path -- and found genuinely nothing: no third-party client has ever
implemented a favorite-foods method, at all. That's a materially weaker
evidence position than `addWeighIn`/`addHydration` had before they were
built, so guessing at a request/body shape here would violate this
project's own rule (`openspec/config.yaml`: never write to the Garmin
account before the write contract is documented). See
`docs/garmin-routes.json`'s `favoriteFoods` entry (2026-09-22 update) for
the full evidence trail.

Meanwhile the underlying user need is real and independent of Garmin's API
surface: `Food.garminIsFavorite`/`FoodListRow`'s existing "Favorite" tag
already shows that Garmin's OWN account has some favorite concept baked
into search results -- but it's read-only from this app's side, tied to
whatever the official Garmin Connect app already favorited, and gives this
app's own users no way to mark or use their own favorites for fast
re-logging. This app's "local-first, zero-network-wait" principle (CLAUDE.md)
means the honest fix doesn't have to wait for Garmin's write contract
anyway: a star toggle should be instant regardless of whether it also synced
anywhere.

## What Changes

- Add a purely local **favorite-foods** concept (`FoodLogCore.
  FavoriteFoodStore`, JSON-file-backed, actor-isolated -- the same shape
  `CustomFoodStore` already establishes) that a user can toggle on any food
  in the catalog.
- Add a star/heart toggle affordance to catalog rows (search results,
  quick-pick cards, custom-food rows) in the primary logging flow only --
  never offered while picking a food FOR another screen (`.pickBackingFood`/
  `.pickIngredient`), where favoriting doesn't make sense.
- Add a horizontally-scrolling **Favorites shelf** to the catalog, shown
  whenever the user has any favorites, at the same prominence as the
  existing quick-pick shelf, so favoriting is immediately useful for fast
  re-logging rather than just a bookmark nobody revisits.
- No Garmin sync of any kind -- documented as a deliberate, evidence-backed
  decision (see Why above), not an oversight. `docs/garmin-routes.json`
  gets a corrected, fully-cited `favoriteFoods` entry reflecting the
  negative research result, so a future pass doesn't have to redo it.

## Capabilities

### Modified Capabilities

- `food-catalog` - adds a local favoriting mechanism and a Favorites shelf,
  additive to the existing search/quick-pick/custom-food/barcode surface
  (`openspec/changes/archive/2026-09-16-add-food-log-core/specs/food-catalog/spec.md`).

### New Capabilities

None -- favoriting is scoped as an addition to the existing `food-catalog`
capability, not a new one, since it has no independent purpose outside that
screen.

## Non-goals

- **Syncing favorites to Garmin.** No evidence-backed write contract exists
  for `/nutrition-service/favorite/food` (see Why above) -- this is not
  deferred as "later," it's a considered decision given the evidence
  available. If a future device probe or a newly-published OSS client ever
  turns up a real contract, this can be revisited as its own change, gated
  the same cautious way `createCustomFood`/`createCustomMeal` already are.
- **Surfacing or using Garmin's own `garminIsFavorite` flag differently.**
  That read-only flag (`Food.garminIsFavorite`, shown by `FoodListRow`'s
  existing "Favorite" `Tag`) is untouched and stays exactly what it already
  is: a secondary badge reflecting Garmin account state, never used for
  ranking. This change's local favorites are a completely separate concept,
  deliberately not merged with it.
- **Favoriting Open Food Facts (Czech database) search results.** Those
  results end in a matching/creation flow, not a directly loggable Garmin
  food (design.md D5's "never merged" stance) -- out of scope for this pass.

## Impact

Affected surfaces: `FoodLogCore` (new `FavoriteFood.swift`), `Shared/
AppServices.swift` and `GarminFood/App/AppEnvironment.swift` (new store
wiring, mirroring `customFoodStore`), `GarminFood/Catalog/FoodCatalogView.swift`
(toggle wiring, Favorites section), `GarminFood/Catalog/QuickPickShelf.swift`
(optional favorite-star parameters), a new `GarminFood/Catalog/
FavoritesShelf.swift`, and `GarminFood/DesignSystem/Components.swift` (new
`FavoriteToggleButton`). `docs/garmin-routes.json`'s `favoriteFoods` entry
updated with the research findings.

**Depends on**: `add-food-log-core` (the `Food`/`Serving` domain model this
favorites).

**Unblocks**: nothing further planned.
