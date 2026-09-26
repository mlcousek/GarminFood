## 1. Spike (record results in design.md)

- [x] 1.1 Pick the export (Parquet via DuckDB, JSONL or CSV). Measure download volume and runtime.
- [x] 1.2 Measure the Czech product count, name coverage, and index size raw and gzipped. If it exceeds 5 MB, apply the trimming from D1.

## 2. Builder + CI

- [x] 2.1 Add `tools/build-czech-food-index/` (script and README). Output must be deterministic, sorted by code.
- [x] 2.2 Add `.github/workflows/food-index.yml`:
  - Triggers: weekly cron and `workflow_dispatch`.
  - Builds the index and writes the manifest.
  - Uploads both to the rolling `food-index` release (`gh release upload --clobber`).
  - Release notes carry the ODbL attribution.
- [x] 2.3 Run the workflow once and record count, size and duration. *Run 35946067256 (`workflow_dispatch`, 2026-09-24 02:09:46–02:10:58 UTC, about 72 s): **8104** products, `czech-food-index-v1.json.gz` **294 928 bytes** (gzipped JSON), published to the `food-index` release.*

## 3. App (FoodLogCore + app)

- [x] 3.1 `OfflineFoodIndex`:
  - Decodes off the main actor.
  - Builds the inverted index (D2) and provides `product(code:)`.
  - Tested with a fixture of about 200 products.
- [x] 3.2 Plug `OfflineCzechIndexSource` into `FoodSearchEngine`, and extend the golden relevance tests with the index source.
  - Done as `OfflineFoodIndexSearchTests.testPreScoringKeepsTheSameTopResultsAsRankingEverything`: ranking only the top 50 matches ranking the whole index. The golden table in SearchRelevanceTests was left unchanged.
- [x] 3.3 `IndexDownloader` (D3), built as FoodLogCore `OfflineIndexStore` + `URLSessionOfflineIndexFetcher`, with the app-side `OfflineIndexLoader`:
  - Manifest check, Wi-Fi gating, SHA-256 check, atomic swap, backup exclusion.
  - Tests cover a checksum mismatch and the no-change case.
- [x] 3.4 Add the `BackgroundRefresh` hook and a check on foreground.
- [x] 3.5 Settings: status row, "Download now", cellular switch, and the About credit.
- [x] 3.6 Barcode fallback in `BarcodeResolution` (D4), with tests.

## 4. Verify

- [x] 4.1 CI green. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.2 On device:
  - The index downloads on Wi-Fi.
  - Search works in airplane mode.
  - A Czech barcode that Garmin misses resolves.
