## Evidence

A code audit on 2026-09-23 of `FoodCatalogSearch.swift`,
`OpenFoodFactsClient.swift` and `FoodCatalogView.swift` found:

- Local foods are hidden while searching (`FoodCatalogView.swift:119`).
- Garmin results keep their raw order (`FoodCatalogSearch.swift:47`).
- `moreDataAvailable` is ignored (`GarminModels.swift:19`).
- The OFF rerank is a whole-term substring test with two buckets
  (`OpenFoodFactsClient.swift:191-201`).
- OFF uses the legacy `search.pl` and asks only for `product_name` (`:141-156`).

Endpoint status:

- **Garmin search.** `GET /nutrition-service/food/search?searchExpression=`
  returns 200 (confirmed 2026-09-14). The paging params are unknown.
  Task 1.1 probes `start`, `limit`, `pageNumber` and `pageSize` read-only,
  recording Spring's 400 bodies, which name the accepted arguments.
- **OFF Search-a-licious.** Public and needs no auth. It was deferred earlier
  because it was unproven here. Task 1.2 probes it read-only with
  `GET https://search.openfoodfacts.org/search?q=rohlik&langs=cs,en&page_size=50&fields=code,product_name,product_name_cs,generic_name_cs,brands,quantity,nutriments`,
  records the response shape and latency, and compares hit quality against
  `cgi/search.pl` on 10 queries.

## Probe results (2026-09-23, all read-only)

### Garmin food search (tasks 1.1, 1.3)

Probed with `tools/garmin-get.mjs` against the owner's account. Full notes
are in `docs/garmin-routes.json` (`foodSearch`, lastVerified 2026-09-23).

- **Paging works.** The 400 for `start=5` names the bound object:
  `FoodSearchParams(searchExpression=rohlik, regionCode=US, languageCode=en, start=5, limit=20)`,
  with "Start index must be divisible by limit". So `start`, `limit`,
  `regionCode` and `languageCode` are real parameters. The default `limit`
  is 20 and the maximum is 50 ("Maximum value for a fat secret search is
  50"). `start=20&limit=20` for "chicken" returns the next 20 results.
- **`moreDataAvailable` is reliable.** It is true while another page
  exists, and false when the term runs out ("rohlik": 13 results, false).
- **`pageNumber` and `pageSize` are silently ignored.**
- **`regionCode=CZ` unlocks FatSecret's Czech catalogue.** This is the
  biggest finding:

  | Query | Default (US) | `regionCode=CZ` |
  |---|---|---|
  | tvaroh | 5 unrelated (Cheese [Dvaro], Carrot Sticks [Taro Brand]) | 20+ real tvarohy (Madeta, Tatra, Pilos, Albert), more pages |
  | kure | "Pure [Organifi]", "Pedia Sure" | Kuřecí šunka, Kuře pikant… |
  | mleko | 0 | 20 (Mléko [Tatra], Mleko [Kunín]…) |
  | eidam | 6 | 20+ (Eidam 30 % from Albert, Agricol, Clever…) |
  | chicken | Chicken, Chicken Breast… | the same generics |

  Results carry `regionCode: "CZ"`, `languageCode: "en"`. The owner's own
  diary for 2026-09-22 already holds FATSECRET and GARMIN foods with
  `regionCode` CZ, so that tuple is one Garmin accepts for logging.
  `languageCode=cs` is rejected (400 "Language code is not supported").
- **The search is diacritic-sensitive (task 1.3).** "rohlik" gives 13
  unrelated results (e.g. "Prepared Squid [Rolin]") while "rohlík" gives 0.
  "banan" and "banán" return different sets. Under CZ, "bily jogurt" and
  "bílý jogurt" return different Czech yogurts. "tvaroh odtucneny" missed
  Madeta's "Tvaroh Odtučněný", which "tvaroh odtučněný" found.
  **Decision:** send both spellings and merge by `foodId` (see D1a).
- Latency is 150–850 ms per request, typically about 300 ms.

### Open Food Facts: Search-a-licious vs `cgi/search.pl` (task 1.2)

Fetched with a descriptive User-Agent (`GarminFood/1.0 (personal iOS food
logger; …)`).

Search-a-licious response shape:

    { hits: [{ code, product_name, product_name_en?, product_name_cs?, generic_name_cs?,
               brands: [String], lang, quantity, nutriments: { "energy-kcal_100g", … } }],
      aggregations, facets, charts, page, page_size, page_count, debug, took,
      timed_out, count, is_count_exact, warnings }

- **`brands` is an array** here, but a comma-separated string in `search.pl`.
- **`product_name` is the main-language name.** For Czech products `lang`
  is "cs", so `product_name` is already Czech, and `product_name_cs` was
  absent from every hit in 13 queries. `product_name_en` appears when a
  translation exists.
- **The Czech filter goes in `q`** as Lucene syntax:
  `q=<term> countries_tags:"en:czech-republic"`. It works.
- **Speed.** 60–260 ms wall time, 4–15 ms server `took`.
- **Also diacritic-sensitive.** "mleko" gives 9 Czech hits and "mléko" 45;
  "sunka" 11 and "šunka" 52. Search-a-licious ORs multi-word queries: "bily
  jogurt" has a worldwide count of 10,000.

| Query | SAL worldwide | SAL Czech-only | `search.pl` Czech-only |
|---|---|---|---|
| rohlik | 6 (all brand "Rohlik"), 263 ms | 4, 119 ms | 503 |
| rohlík | 8, 61 ms | 7, 62 ms | 503 |
| tvaroh | 45, 106 ms | 33, 72 ms | 503 |
| tvaroh mekky | 45, 74 ms | 33, 67 ms ("Tvaroh měkký" in the top 6) | 503 |
| bily jogurt | 10,000 (OR), 80 ms | 406, 75 ms | 18, 278 ms |
| kefir | 1,977, 109 ms | 16, 70 ms | 24, 652 ms |
| chleb | 133, 240 ms | 8, 117 ms | 32, 817 ms |
| eidam | 33, 71 ms | 26, 70 ms | 86, 559 ms |
| sunka | 33, 68 ms | 11, 61 ms | 503 |
| šunka | 96, 72 ms | 52, 71 ms | 232, 507 ms |
| mleko | 138, 210 ms | 9, 121 ms | 40, 542 ms (one run; 503 on the retry) |
| mléko | 51, 102 ms | 45, 70 ms | 503 |
| madeta | 95, 77 ms | 85, 70 ms | 118, 563 ms |

**Conclusion.** Search-a-licious answers every time and is 3–10× faster.
`search.pl` returned 503 on 7 of 13 Czech-only probes. Its recall is higher
for diacritic-free queries, because it folds diacritics. Search-a-licious is
therefore primary, `search.pl` is the fallback, and both are sent the
typed and the diacritic-restored spelling (D1a), which closes most of the
recall gap: "mleko" is also sent as "mléko".

## D1: Normalization pipeline (`SearchText`)

    raw → NFKD → strip combining marks → lowercase(cs_CZ) → replace [^a-z0-9] with space
        → split → drop empty → classify tokens: word | quantity ("250g","1,5l","500ml","%")
        → stem(word) (D2) → [Token(original, folded, stem, isQuantity)]

Quantity tokens get a weight of 0.2, so "Rohlík 43g" still matches "rohlik".
This one pipeline is used for queries, names, brands, the Garmin cache key,
and the OFF → Garmin match query.

## D2: Czech light stemmer

A conservative port of the Dolamic & Savoy (2009) light stemmer. It removes
the case ending, then the possessive ending, and never leaves a stem shorter
than 3 characters. It works on folded text. Aggressive derivational stripping
is deliberately excluded, because it over-conflates food names. The stemmer is
a pure function, covered by table tests:

- Collapse to one stem:
  - rohlik / rohliky / rohliku / rohlikem
  - chleb / chleba / chlebem
  - jogurt / jogurty / jogurtu
  - mleko / mleka / mlekem
  - syr / syry / syru
- Must not be over-stemmed: tvaroh.
- Handled by a small exception list: kureci / kure.

## D3: Token match tiers and scoring

For each query token `q`, take its best match against the name tokens. Brand
tokens match on the same tiers, at half weight.

| Tier | Weight | Condition |
|---|---|---|
| exact folded | 1.00 | |
| same stem | 0.90 | |
| prefix | 0.80 | Last query token only, at least 2 chars ("rohl" matches rohlik) |
| fuzzy | 0.60 | Same first letter; DL distance ≤ 1 for length ≥ 4, ≤ 2 for length ≥ 8 |
| brand match | tier × 0.5 | |

The final score combines these parts:

    text           = Σ best(q) / |query words|
    coverage bonus +0.15 if every query word matched at some tier
    start bonus    +0.10 if the name's first word matched the query's first word
    length norm    × 1 / (1 + 0.05 × max(0, nameWords − queryWords))
    personal       + 0.25 × log1p(decayedLogCount) + 0.15 favorite + 0.10 custom + 0.05 garminIsRecent/Favorite
    source prior   + 0.05 local/Garmin, + 0 OFF   (a tie-breaker, never dominant)
    remote prior   + 0.05 × (1 − rank/N) from the source's own order (keeps Garmin's relevance signal)
    threshold      text ≥ 0.45, otherwise dropped (prevents "all tokens fuzzy" garbage)

All weights are constants defined in one place. The golden suite (D6) is the
acceptance test, and the weights may only be tuned against it.

## D4: Dedup

The dedup key is the normalized name words, sorted, plus the normalized brand.
Two items with equal keys and kcal/100 g within 5% are merged. Precedence is
local > Garmin > OFF. The merged item keeps the higher score and adds a
provenance badge.

## D5: Streaming and stability

The engine exposes one `AsyncStream<SearchSnapshot>` per query:

- The local snapshot is emitted immediately.
- A new snapshot follows each time a remote source completes.

The view keeps rows stable across snapshots:

- Rows already shown keep their relative order.
- New rows are inserted by score.
- A full re-sort happens only when the query changes.

Error handling:

- `CancellationError` and `URLError.cancelled` are swallowed.
- A failing source produces a per-source status, e.g. "Czech database
  unavailable", shown as a footnote. It never becomes a global error.

## D6: Golden relevance suite

A `SearchRelevanceTests` fixture holds about 300 realistic candidate foods,
hand-written in the captured Garmin and OFF shapes, and 30+ queries with the
expected top-3 membership for each. It runs in CI under `swift test`, with no
network. It is the regression gate for any future ranking tweak.

## Fallbacks

- **Search-a-licious down:** fall back to `cgi/search.pl`.
- **Both OFF endpoints down:** show Garmin + local results, plus a footnote.
- **Garmin down:** show local + OFF results, plus a footnote. Auth errors stay
  loud.
- **Paging params not found by the probe:** no "Show more"; only the first
  page is used, as today.

## Implementation notes (2026-09-23, what was built vs. the plan)

These are the places where the build deliberately differs from, or adds
to, D1–D6. Each one was checked against the golden suite before being
kept. The suite's expectations were validated with a faithful port of
the ranker, since no Swift toolchain is available locally.

- **D1a: remote spelling variants.** Garmin and both OFF endpoints are
  diacritic-sensitive (probes above). Each remote source therefore sends
  at most two spellings in parallel and merges them round-robin:
  - what was typed, plus its diacritic-free form, when the user typed
    diacritics;
  - otherwise, what was typed plus a restored form from `CzechDiacritics`,
    a ~200-word food vocabulary ("mleko" → "mléko", "bily" → "bílý").

  If one spelling fails, the other's hits are still used. The remote term
  cache is keyed by the typed phrase with diacritics kept (lowercased,
  whitespace collapsed), not the folded one, because the two spellings are
  different requests.
- **Garmin region.** `GarminFoodSource` sends `regionCode=CZ`, `limit=50`
  and `start=page×50`. "Show more" pages Garmin; OFF has no second page,
  because 50 hits per spelling exceeds its Czech subset for nearly every
  query probed.
- **D2 on folded text.** Lucene's "čt→ck", "št→sk" and "ů→o" rules are
  dropped: after folding they can't tell letters apart, and "st→sk" would
  hit "pasta". The case endings "-at", "-ám", "-os", "-us" and "-aty" are
  not stripped either. On folded text they mostly hit nominatives: salát
  and salám both became "sal", losos became "los" while lososa became
  "losos", and eidam became "eid" while eidamu became "eidam". Mobile-e
  removal needs more than 3 letters. Resulting stems: rohlík* → rohlik,
  chléb/chleba/chlebem and the typo "chlba" → chlb, mléko* → mlk, tvaroh
  unchanged. kuře/kuřecí map to "kur" through the exception table.
- **D3 additions.**
  - A **stem-prefix** tier (0.7): the query stem (3+ letters) is a prefix
    of the name stem, at most 3 letters longer. It links prsa → prsní, so
    "kure prsa" finds "Kuřecí Prsa" first.
  - A **first-letter typo** tier (0.5), for query words of 5+ letters with
    one edit. Garmin answers "jogurt" with its English "Yogurt".
  - An **alias** factor (0.9): OFF's other names (English, generic) are
    matched too.
  - The **personal boost is multiplied by `text`**, so a food eaten daily
    wins among comparable matches but can't lift a half match above a full
    one (see `testHeavyUsageDoesNotLiftAHalfMatchAboveAFullMatch`).
  - The **prefix tier accepts 1 character** when the query is a single
    token, so the first keystroke already finds your own foods.
  - The threshold is inclusive: `text ≥ 0.45`. That keeps brand-only
    matches such as "madeta" (0.5), which rank below every name match.
- **The local library** is custom foods, favorites, and foods in usage
  history that `FoodCache` can display. It deliberately excludes every
  food ever seen in a search: that cache is unbounded and full of
  unrelated remote hits. Garmin results are still back-filled into
  `FoodCache` (as before), so a food becomes local once logged.
- **D4 identity merges.** The same Garmin `foodId` from the local library
  and from Garmin merges regardless of calories, and so does the same EAN
  from live OFF and the offline index. The dedup key drops the brand's
  words from the name ("Madeta Jihočeský tvaroh" / Madeta equals
  "Jihočeský Tvaroh" / Madeta) and uses the first brand only. Unknown
  calories never merge. Two different foods from the same source are
  never merged.
- **D5 continuity.** While a remote source loads, its previous answer is
  re-ranked against the new query and shown provisionally. Rows that still
  match stay put instead of blinking out on every keystroke; rows that no
  longer match fall under the threshold. Queries of one character skip
  remote sources. `GarminClient` no longer writes cancelled requests to
  DiagnosticsLog, which fast typing would otherwise flood.
- **Siri (4.3)** logs only when `SearchConfidence` holds: the top hit
  covers every query word, has `text ≥ 0.85`, and leads the runner-up by
  at least 0.05. Otherwise it logs nothing and reads back up to three
  candidates ("could be X, or Y… say the full name").
  `requestDisambiguation` needs an `AppEntity` parameter, which this
  string-parameter intent doesn't have. Custom foods and OFF products are
  excluded from voice logging.
- **Offline index hook.** `add-offline-czech-food-index` adds a
  `FoodSearchSource` with `origin: .offlineIndex` and `isRemote: false`.
  That makes it answer on every keystroke, with no debounce and no cache,
  and rank and dedup against the live sources by EAN. Its products route
  through the Garmin match flow like live OFF ones.
