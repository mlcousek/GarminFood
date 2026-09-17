## 27. Open Food Facts client

- [x] 27.1 Implemented `OpenFoodFactsClient` (`ios/FoodLogCore/Sources/FoodLogCore/OpenFoodFactsClient.swift`) calling `GET https://world.openfoodfacts.org/cgi/search.pl?search_terms={term}&json=1&page_size=20&fields=code,product_name,brands,nutriments,quantity`, decoding into the existing `Food`/`Serving` shape. **User-Agent is still unconfirmed** (this file's own header, and design.md's Context): a descriptive UA (`"GarminFood - iOS - Version 1.0 - https://github.com/mlcousek/GarminFood"`) is shipped as a single named constant so it can be flipped back to "no custom header" in one place if live testing reconfirms the block seen during this change's research.
- [x] 27.2 Added the Czech country filter (`&tagtype_0=countries&tag_contains_0=contains&tag_0=czech-republic`) as a `czechOnly` parameter, defaulting to `true`, surfaced in `FoodCatalogView` as a "Czech only" toggle in the section header.
- [x] 27.3 Mapped `nutriments['energy-kcal_100g']`/`carbohydrates_100g`/`proteins_100g`/`fat_100g`/`fiber_100g`/`sugars_100g`/`sodium_100g`/`saturated-fat_100g` to `Serving`'s macro fields as a single implicit 100g serving. Numeric fields decode leniently (`Double` or a numeric-looking `String`) since OFF is known to sometimes send `""` for a missing value.
- [x] 27.4 Unit tested the decoding (`OpenFoodFactsClientTests.swift`) against the real captured 2026-09-16 "tvaroh" fixture from design.md's Context, plus missing-nutriments, missing-code/name, and empty-string-numeric edge cases — all pure decoding, no network.

## 28. Two-source catalog UI

- [x] 28.1 Added a Czech (Open Food Facts) results section to `FoodCatalogView`, visibly separate from Garmin's "Results" section, debounced the same way (300ms `.task(id:)`), hidden in `pickBackingFood` mode.
- [x] 28.2 Selecting a Garmin result is unchanged. Selecting a Czech-database result sets `matchingTarget`, routing into `MatchConfirmationView` via `navigationDestination(item:)` instead of the normal serving-picker/confirm flow.

## 29. Garmin-equivalent matching

- [x] 29.1 Implemented `GarminFoodMatching.match(offFood:garminCandidates:)` (`ios/FoodLogCore/Sources/FoodLogCore/GarminFoodMatching.swift`): normalizes both names (lowercase, diacritic-folded, packaging/quantity tokens like `250g`/`1kg`/`500ml` stripped via regex), compares for equality or containment, and rejects a name match when both sides have calories and they differ by more than 20%.
- [x] 29.2 Unit tested (`GarminFoodMatchingTests.swift`): exact match, case-insensitive match, diacritic-only difference, packaging-word stripping, calorie mismatch rejection, calories-just-inside-tolerance, missing-calories-skips-the-check, no-candidates-at-all, and no-name-similar-candidate.
- [x] 29.3 Built the "Found a match" / "No match found" confirmation screen (`MatchConfirmationView.swift`) — always shown before logging, with an explicit "Use this match" confirm, a "that's not right" reject path back to the no-match view, and a "log anyway with a different Garmin food" fallback into a fresh `FoodCatalogView` search.

## 30. Create-in-Garmin fallback

- [x] 30.1 Implemented `GarminClient.createCustomFood(...)` (`ios/GarminKit/Sources/GarminKit/GarminClient.swift`) against `POST /nutrition-service/customFood`. **Request AND response body are genuinely unconfirmed** — documented prominently in both the method's doc comment and `CreateCustomFoodRequest`'s in GarminModels.swift, matching `createFoodLogEntry`'s existing convention precisely.
- [x] 30.2 Built the "Create in Garmin" confirmation screen (`CreateInGarminConfirmView` in `MatchConfirmationView.swift`) showing the exact name, serving, and macro values about to be sent, with an explicit "Create in Garmin" tap required (disabled if there's no calorie value to send).
- [x] 30.3 Wired the created food's response into the normal log-entry flow: on success, `Food(searchResult:)` adapts the response and routes straight into the existing `LogEntryConfirmView`/`LogTarget.catalog` path, identical to any other Garmin food.
- [x] 30.4 **Confirmed exactly one call site.** `grep -rn "createCustomFood" ios` shows the only real invocation is inside `CreateInGarminConfirmView.createInGarmin()`, itself only reachable by the user's explicit "Create in Garmin" button tap — nothing else in the codebase calls it.

## 31. README

- [x] 31.1 Updated the top-level `README.md`: seven OpenSpec changes (added `add-czech-food-catalog`), the redesigned streak+calorie-hero home screen (`TodayHeroView`/`HomeView`/`MomentOverlay`), the new Czech catalog work, and a "What remains genuinely unverified" section naming the browser login flow, the two unconfirmed Garmin writes, and the lack of real-device visual QA.
