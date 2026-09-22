## 1. Garmin route research (Part 1)

- [x] 1.1 Follow up on `docs/garmin-routes.json`'s `favoriteFoods` entry
      (405 on GET, flagged as needing a further probe, not a dead end):
      check `cyberjunky/python-garminconnect` (`garminconnect/__init__.py`,
      fetched in full) for any favorite-related method. Result: none --
      zero references to "favorite" anywhere in the file, despite it being
      the source for `addWeighIn`/`addHydration`'s real contracts.
- [x] 1.2 Check `Taxuspt/garmin_mcp` (`src/garmin_mcp/nutrition.py`, fetched
      in full -- the source for `createFoodLogEntry`/`deleteFoodLogEntries`/
      `quickAddFoodLogEntry`'s confirmed contracts). Result: zero matches
      for "favorite" (grep -i, 1000 lines, 0 hits).
- [x] 1.3 Check `tamcore/garmin-mcp` (`internal/garmin/client/
      endpoints_nutrition.go`, a Go client explicitly cross-checking
      python-garminconnect against the Taxuspt curation). Result:
      comprehensive nutrition-route coverage (search, log CRUD, meals,
      settings, full custom-food CRUD) with nothing under `/favorite` at
      all.
- [x] 1.4 Broad GitHub code search (`gh api search/code`) for
      `nutrition-service/favorite`, `"favorite/food" garmin`, `isFavorite
      garmin connectapi`. Result: the only hits are this project's own
      files -- no other public Garmin Connect client or reverse-engineering
      writeup references this route family.
- [x] 1.5 Update `docs/garmin-routes.json`'s `favoriteFoods` entry (read
      array) and the top-level `unresolved` list with the full evidence
      trail and citations, same style as `addWeighIn`/`addHydration`'s
      entries. Conclusion: route existence is still real evidence (the 405,
      not a 404), but there is no third-party field-level evidence for its
      request/response shape -- per this project's task rule, NOT
      implemented in `GarminClient`. Falls back to Part 2 as a self-
      contained local feature.

## 2. Local favorite-foods store (Part 2)

- [x] 2.1 Add `FoodLogCore/FavoriteFood.swift`: `FavoriteFood` (a `Food`
      snapshot + `favoritedAt`, keyed by `Food.id`) and `FavoriteFoodStore`
      (actor, JSON-file-backed, mirroring `CustomFoodStore`'s exact shape --
      `all()`, `isFavorite(foodId:)`, `toggle(_:)`, `remove(foodId:)`).
- [x] 2.2 Unit tests (`FoodLogCoreTests/FavoriteFoodTests.swift`): toggle
      add/remove round-trip, `isFavorite` reflects state, `remove` works
      independent of `toggle`, newest-first ordering, persistence across a
      fresh store instance at the same file path -- real store instances at
      unique temp paths, no mocks, matching `CustomFoodTests.swift`'s
      pattern.

## 3. Wiring

- [x] 3.1 `Shared/AppServices.swift`: add `favoriteFoodStore` as a shared,
      one-instance-per-process store, mirroring `customFoodStore`.
- [x] 3.2 `GarminFood/App/AppEnvironment.swift`: expose `favoriteFoodStore`
      from `AppServices.shared`, mirroring the same pattern.

## 4. UI

- [x] 4.1 `GarminFood/DesignSystem/Components.swift`: add
      `FavoriteToggleButton` (star/star.fill), documented as a SIBLING view
      next to a row's own `Button` (never nested inside one, to avoid
      SwiftUI's nested-button-in-a-List-row-label hit-testing problem).
      Distinct from the existing read-only `garminIsFavorite` "Favorite"
      `Tag` on `FoodListRow`.
- [x] 4.2 `GarminFood/Catalog/QuickPickShelf.swift`: add optional
      `isFavorite`/`onToggleFavorite` closures (both `nil`-default, so
      existing previews/call sites are unaffected); render the star as a
      `ZStack`-overlaid sibling of each card's tap `Button`.
- [x] 4.3 New `GarminFood/Catalog/FavoritesShelf.swift`: a horizontally-
      scrolling shelf mirroring `QuickPickShelf`'s card shape, populated
      from `FavoriteFoodStore.all()`. Tapping a card routes through the
      same `select(_:)` dispatch `FoodCatalogView` already uses for search
      results (no remembered serving/quantity to jump straight to, unlike
      quick-pick).
- [x] 4.4 `GarminFood/Catalog/FoodCatalogView.swift`: load favorites in
      `loadLocalData()`; add the Favorites section (shown whenever
      `!favoriteFoods.isEmpty` and not picking a backing food, matching the
      quick-pick shelf's own visibility rule); add the star toggle as a
      sibling `HStack` element (not nested in the row's `Button`) to search
      results and custom-food rows; gate every toggle behind `!isPicking`
      so it never appears in `.pickBackingFood`/`.pickIngredient` mode;
      include `favoriteFoods.isEmpty` in the "nothing logged yet" empty-
      state condition so it doesn't show when favorites alone are present.

## 5. Verification

- [x] 5.1 Re-read every touched/created file for syntax and type
      correctness (no local Swift compiler -- CLAUDE.md's "no Mac"
      constraint). Actual correctness signal is CI (`swift test` for
      `FoodLogCore`, `xcodebuild` for the app target) on push -- not run as
      part of this change; flagged for the owner.
- [ ] 5.2 **NOT DONE HERE -- needs CI + a sideloaded device build.** Confirm
      the app target and `FoodLogCoreTests` both build and pass in CI, and
      that the star toggle/Favorites shelf render and behave correctly on
      a real device.
