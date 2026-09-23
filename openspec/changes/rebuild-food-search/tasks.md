## 1. Probes (read-only; record status and shape in docs/garmin-routes.json or the OFF notes)

- [ ] 1.1 Garmin food search paging: try `start`, `limit`, `pageNumber` and `pageSize` with `tools/garmin-get.mjs`. Record the 200/400 bodies and whether `moreDataAvailable` flips.
- [ ] 1.2 OFF Search-a-licious: record the shape, latency, and the `product_name_cs`/`generic_name_cs` presence. Compare 10 Czech queries against `search.pl`.
- [ ] 1.3 Check whether Garmin search differs for "rohlík" vs "rohlik". Decide whether to send the folded term too (and merge).

## 2. Text engine (FoodLogCore, pure and tested)

- [ ] 2.1 `SearchText.normalize/tokenize` (D1), with quantity tokens. Tests.
- [ ] 2.2 `CzechLightStemmer` (D2) plus table tests.
- [ ] 2.3 Bounded Damerau–Levenshtein with early exit. Tests (including performance: 10k comparisons < 50 ms in a release build).
- [ ] 2.4 `SearchRanker` (D3), with weights in one struct. Tests per tier.
- [ ] 2.5 `SearchDedup` (D4). Tests.

## 3. Sources and engine

- [ ] 3.1 `FoodSearchSource` protocol. `LocalFoodSource` covers custom foods, favorites, and `FoodCache` joined with usage history.
- [ ] 3.2 `GarminFoodSource`: paging if 1.1 found it; LRU cache keyed by the normalized term.
- [ ] 3.3 `OpenFoodFactsSource`: Search-a-licious with `search.pl` as fallback; Czech name fields; LRU cache; Czech-only toggle preserved.
- [ ] 3.4 `FoodSearchEngine`: `AsyncStream<SearchSnapshot>`, stable merge (D5), per-source status, back-fill into `FoodCache`.
- [ ] 3.5 Golden relevance suite, `SearchRelevanceTests` (D6): 30+ queries, about 300 fixtures. It must pass.

## 4. App

- [ ] 4.1 New `SearchResultsSection.swift` in the Catalog folder: one list, source badges, per-source footnotes, "Show more" (Garmin paging), stable animations. `FoodCatalogView` hosts it, and all modes honour picker routing.
- [ ] 4.2 An OFF result tap still goes through the Garmin match flow. The match query is built with `SearchText`, with brand and quantity stripped.
- [ ] 4.3 `LogNamedFoodIntent` uses the engine's top hit when score ≥ threshold; otherwise it returns a disambiguation list.
- [ ] 4.4 Remove the old separate Results and Czech sections, and remove `OpenFoodFactsClient.rerank`.

## 5. Verify

- [ ] 5.1 CI green, including the golden suite.
- [ ] 5.2 On device: rohlíky, tvaroh měkký, typos, own custom food, offline typing, fast typing (no error flash).
