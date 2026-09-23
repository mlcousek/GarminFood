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
