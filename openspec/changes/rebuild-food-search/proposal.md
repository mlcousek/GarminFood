## Why

The owner's words (2026-09-23): "one thing that is really really important
for me is to find in the databases … implement best finding algorithms as
possible".

An audit of the current pipeline on 2026-09-23 found it much weaker than it
looks:

- Your own foods disappear as soon as you type. Custom foods, favorites,
  recents and quick picks are never searched.
- Garmin and Open Food Facts results appear as two unmerged lists, so the same
  product can show up twice.
- Garmin results come in Garmin's raw order, only the first page is used, and
  `moreDataAvailable` is ignored.
- OFF results get only a two-bucket "name contains the whole term" sort. There
  is no tokenization ("tvaroh měkký" doesn't match "Měkký tvaroh"), no Czech
  inflection ("rohlíky" doesn't match "Rohlík"), no typo tolerance and no
  personal boost.
- OFF queries go to the legacy `cgi/search.pl` without Czech name fields. That
  endpoint returned 503s on 2026-09-22.
- Every keystroke waits 300 ms plus the network. A spinner replaces the old
  results, and a cancelled request flashes an error.
- Siri logs Garmin's raw first hit with no relevance check.

## What Changes

A new `FoodSearchEngine` in FoodLogCore replaces the two ad-hoc pipelines. The
owner chose one ranked list (2026-09-23).

- **One pipeline, many sources.** A `FoodSearchSource` protocol with these
  implementations:
  - **Local:** custom foods, favorites, and every food ever logged (from
    `FoodCache` plus usage history). Instant, no network.
  - **Garmin:** food search, now with paging via "Show more".
  - **Open Food Facts:** Search-a-licious (`search.openfoodfacts.org`) with
    Czech name fields, falling back to the current `cgi/search.pl`.
  - **Offline Czech index:** plugs in later, from
    `add-offline-czech-food-index`.
- **Czech-aware matching, the same for every source:**
  - **Normalization:** Unicode NFKD, diacritics stripped, cs_CZ case-folding,
    punctuation dropped. Pack sizes such as "250g" and "1,5 l" become tokens
    that don't dominate the match.
  - **Tokens:** query and name are both tokenized, and order doesn't matter.
  - **Czech stemming:** a conservative light stemmer (suffix stripping after
    Dolamic & Savoy), so rohlík/rohlíky/rohlíku, jogurt/jogurty and
    chléb/chleba each match.
  - **Prefix matching** for the word you're still typing.
  - **Typo tolerance:** bounded Damerau–Levenshtein, up to 1 edit for tokens of
    length ≥ 4 and up to 2 for length ≥ 8.
- **Relevance score.** For each query token, take its best match among the name
  tokens. The tiers, best first, are exact, stem, prefix and fuzzy. Brand
  tokens get a lower weight. On top of that come:
  - a coverage bonus when every query token matched;
  - a bonus when the name starts with the query;
  - length normalization, so shorter and more specific names win ties;
  - a personal boost: log frequency with recency decay, a favorite bonus, a
    custom-food bonus, and Garmin's `isFavorite`/`isRecent` flags;
  - a small source prior, because Garmin foods can be logged directly while
    OFF foods need a match step.
- **Cross-source dedup.** Two items merge when normalized name + brand are
  equal and kcal/100 g is within 5%. The directly loggable copy is kept, with
  "also in OFF" provenance.
- **Streaming UX:**
  - Local results render on the first keystroke, with no debounce.
  - Remote results are debounced to 250 ms and streamed in. They merge into
    the ranked list without jumping: rows already shown keep their relative
    order, and new rows animate in.
  - Previous results stay visible while loading; there is no spinner swap.
  - Cancellation is never shown as an error.
  - "No matches" appears only after every source has answered.
- **Caching.** An LRU term cache for remote sources: 100 terms, 15-minute TTL,
  keyed by the normalized term. Remote results are back-filled into
  `FoodCache`, so they become local results next time.
- **Siri.** "Log <food>" uses the engine's top hit only above a confidence
  threshold, and otherwise asks for disambiguation.
- **OFF → Garmin match.** The match uses the normalized name with brand and
  pack size stripped.
- **Measured, not guessed.** A golden-query relevance test suite runs in CI:
  30+ Czech and English queries with expected top-3 results. It includes
  rohliky, tvaroh mekky, bily jogurt, banan (typo), chlba (typo), kure prsa and
  the brand-only query madeta.

## Non-goals

- The offline index itself, which is `add-offline-czech-food-index`. This
  change only defines the source protocol it plugs into.
- Server-side AI or embeddings. The owner explicitly wants no paid AI.
- Voice or photo search.

## Capabilities

### Modified Capabilities

- `food-catalog`: unified ranked search.
- `czech-food-catalog`: OFF endpoint and fields, Czech normalization and
  stemming.

## Impact

- **FoodLogCore:**
  - New: `SearchText` (normalize, tokenize, stem, fuzzy), `FoodSearchEngine`,
    `FoodSearchSource` and its implementations, and `SearchRanker`.
  - Unit tests for each, plus the golden relevance suite.
  - `FoodCatalogSearch` and `OpenFoodFactsClient.rerank` are retired or
    wrapped.
- **GarminKit:** `searchFood(term:start:limit:)` (paging params come from a
  probe) and decoding of `moreDataAvailable`.
- **App:**
  - The `FoodCatalogView` search section becomes one list with source badges,
    in its own `SearchResultsSection.swift`. The separate file keeps merge
    conflicts with the shelves change small.
  - `LogNamedFoodIntent` and `MatchConfirmationView` are updated.
- **Depends on**: `fix-testing-feedback-quick-wins` (picker routing).
- **Unblocks**: `add-offline-czech-food-index`.
