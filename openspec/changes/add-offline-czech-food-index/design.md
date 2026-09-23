## Evidence to gather first (spike, task 1)

Before this change there is no measurement of the Czech subset. The spike
records the following. Every access is read-only and anonymous.

- **Which export to use.** Options, in order of preference:
  1. OFF's Parquet export on Hugging Face (`openfoodfacts/product-database`),
     queried with DuckDB over HTTP with column projection. This only fetches
     the needed columns.
  2. The JSONL export (`openfoodfacts-products.jsonl.gz`), streamed and
     filtered.
  3. The CSV export (`en.openfoodfacts.org.products.csv.gz`).

  Record the actual download volume and runtime on a GitHub-hosted runner.
- **Size of the subset.** Product count, and how many products have a
  `product_name_cs` or a usable name with kcal.
- **Size of the index.** Raw and gzipped. Target ≤ 5 MB gzipped. If it is
  larger, drop fiber/sugar/salt first, then products with no barcode and no
  brand.

### Spike results (2026-09-23, read-only, anonymous, from the owner's Windows machine)

The export options above were set aside in favour of the Search-a-licious
API, the same endpoint the app already searches live
(`GET https://search.openfoodfacts.org/search`). It needs no multi-GB
download and no DuckDB.

- **Probe: `q=countries_tags:"en:czech-republic"`, `page_size=100`.**
  - 200 in ~330 ms.
  - `count: 10000, is_count_exact: false`: the count is capped.
  - Page 101 returns 400: "Maximum number of returned results is 10 000".
- **Workaround: partition by barcode prefix**
  (`… AND code:8*`). Every prefix returned an exact count:
  0*=334, 1*=58, 2*=790, 3*=178, 4*=1435, 5*=874, 6*=36, 7*=178,
  8*=8012, 9*=273. **Total 12,168.** The builder splits a prefix further
  if it ever reaches the window.
- **Legacy `/api/v2/search?countries_tags_en=czech-republic`** reports
  `count: 20805`, but page_size is capped at 100. Deeper pages returned
  **503**, then **401**, so it can't be used for a bulk build.
  **Open question:** why this count is about 8.6k higher than
  Search-a-licious's. Likely causes are products Search-a-licious doesn't
  index, or products with no usable data. If coverage turns out to matter,
  the fallback is the Parquet export (option 1).
- **Full build run locally** (`tools/build-czech-food-index/build.mjs`):
  - 126 pages, **47 s**.
  - 12,168 products fetched. **8,104 kept** with a name and kcal (67 %).
  - Size: **1.04 MB raw JSON, 295 KB gzipped**, far under the 5 MB
    target, so no trimming is needed.
  - Field coverage in the kept set:
    - brand 7,281
    - pack quantity 5,647
    - alternate name 1,252
    - carbs 7,954
    - salt 6,443
    - fiber 3,786
  - 107 products have "tvaroh" in the name.
- **kcal from kJ.** When only `energy-kj_100g` is present, kcal is derived
  from it (÷ 4.184) rather than dropping the product.

## D1: File format

    manifest.json: { "schema": 1, "version": "2026-09-28T03:00Z", "count": 38412,
                     "sha256": "…", "bytes": 2890123, "source": "Open Food Facts", "license": "ODbL-1.0" }
    czech-food-index-v1.json.gz → { "schema": 1, "products": [
        { "c": "8594001234567", "n": "Jihočeský tvaroh měkký", "e": "Soft quark", "b": "Madeta",
          "q": "250 g", "k": 102, "cb": 3.5, "p": 17, "f": 0.5, "s": 3.5, "fi": null, "sa": 0.1 } ] }

The file uses short keys to stay small. The app keeps one version: reading a
schema newer than it knows is ignored until the app is updated. A JSON decode
of about 40k small objects is acceptable once per launch, off the main actor.
If that measures above 300 ms on device, the fallback is a compact binary
format.

## D2: In-memory index

At load time, each product's name and brand are normalized with
`SearchText`. Token stems go into a `[String: [Int32]]` posting map, and
prefix lookup uses a sorted array of stems with a binary search.

A query works like this:
1. Gather candidates: the union of postings for each token's stem, prefix
   range, and fuzzy neighbours. Fuzzy neighbours are limited to stems that
   share the first two letters, for bounded cost.
2. Score them with `SearchRanker`.
3. Return the top 50.

## D3: Download safety

1. Download to a temporary file.
2. Verify its SHA-256 against the manifest.
3. `FileManager.replaceItemAt` into Application Support.
4. Exclude the file from iCloud backup, since it can be downloaded again.

The check runs at most once every 24 h. The download itself happens:
- only on Wi-Fi, unless "Allow on cellular" is on, using
  `URLSessionConfiguration.allowsCellularAccess`;
- only when the manifest version has changed.

Failures are logged to `DiagnosticsLog` and shown in the Settings status row.
They are never modal.

## D4: Barcode fallback

`BarcodeResolution` gets a new step after Garmin's `barCode` lookup misses:
`OfflineFoodIndex.product(code:)`. A hit becomes an OFF-shaped food and goes
through the existing Garmin-match flow.

## D5: Licensing

OFF data is ODbL-1.0.
- The derived index is published under ODbL-1.0.
- The release notes carry attribution and a link.
- Settings → About gets an "Open Food Facts (ODbL)" credit.

## Fallback when things break

- **Build fails in CI:** the previous release asset stays in place, and the
  app keeps the index it has.
- **No index downloaded yet:** the source reports "not available", and search
  runs live only, exactly as in `rebuild-food-search`.
