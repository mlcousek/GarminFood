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
