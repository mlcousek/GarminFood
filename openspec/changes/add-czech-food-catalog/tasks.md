## 27. Open Food Facts client

- [ ] 27.1 Implement `OpenFoodFactsClient` (FoodLogCore) calling `GET https://world.openfoodfacts.org/cgi/search.pl?search_terms={term}&json=1&page_size={n}&fields=code,product_name,brands,nutriments,quantity`, decoding into a domain model matching `Food`/`Serving`'s existing shape so the rest of the catalog/log-entry code treats it identically. Set a descriptive `User-Agent` per OFF's own etiquette guidance (design.md's flagged re-verification item — a plain/no UA worked in this change's testing, but that's not the long-term-correct header to ship).
- [ ] 27.2 Add the optional Czech country filter (`&tagtype_0=countries&tag_contains_0=contains&tag_0=czech-republic`) as a toggle/default, confirmed live 2026-09-16 (134 real matches for "tvaroh").
- [ ] 27.3 Map `nutriments['energy-kcal_100g']`/`carbohydrates_100g`/`proteins_100g`/`fat_100g`/`sugars_100g`/`sodium_100g` etc. to the existing `Serving` macro fields (per-100g, matching how Garmin's own servings are already modeled).
- [ ] 27.4 Unit test the response-decoding against a captured fixture from the real 2026-09-16 "tvaroh" response (design.md's Context section has the shape) — pure decoding logic, no network needed for the test itself.

## 28. Two-source catalog UI

- [ ] 28.1 Add a Czech (Open Food Facts) results section to `FoodCatalogView`, visibly separate from Garmin's results (design.md D5), each result tagged with its source.
- [ ] 28.2 Selecting a Garmin result behaves exactly as it already does today (no change). Selecting a Czech-database result routes into the matching flow (task group 29) instead of straight to the confirm screen.

## 29. Garmin-equivalent matching

- [ ] 29.1 Implement the matching heuristic (design.md D3): normalize both names (lowercase, strip diacritics, drop packaging/quantity words), compare against Garmin search results for the same term, and where calorie data exists on both sides, treat a >20% mismatch as evidence against a match even if names are close.
- [ ] 29.2 Unit test the heuristic directly: exact/near-exact name matches, diacritic-only differences (e.g. "tvaroh" vs "Tvaroh"), a name match with wildly different calories (should NOT match), and no-candidates-at-all.
- [ ] 29.3 Build the "Found a match" / "No match found" confirmation screen (design.md D3's "always shown to the user" rule) — never resolves invisibly.

## 30. Create-in-Garmin fallback

- [ ] 30.1 Implement `GarminClient.createCustomFood(...)` (GarminKit) against the `createCustomFood` route (`POST /nutrition-service/customFood`, route confirmed to exist, request body genuinely unconfirmed per design.md's Context — document this prominently in the code, matching the existing convention for `createFoodLogEntry`).
- [ ] 30.2 Build the "Create in Garmin" confirmation screen showing the exact name and macro values that will be sent, requiring an explicit tap before anything is sent (design.md D4 — never auto-triggered).
- [ ] 30.3 Wire the created food's response (once/if confirmed working) into the normal log-entry flow, so logging happens immediately after creation succeeds, same as any other food.
- [ ] 30.4 **Do not invoke this automatically anywhere in the codebase.** The first real creation is a deliberate action the owner takes knowingly, exactly like `add-garmin-auth-and-sync` task 11.4.

## 31. README

- [ ] 31.1 Update the top-level `README.md` to reflect the current, real state of the project: 7 OpenSpec changes (adding this one), the redesigned home screen, the CI-verified build pipeline, and what remains genuinely unverified (the first real Garmin write, the browser login flow, any visual QA).
