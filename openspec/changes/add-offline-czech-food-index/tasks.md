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
- [ ] 2.3 Run the workflow once and record count, size and duration.

## 3. App (FoodLogCore + app)

- [ ] 3.1 `OfflineFoodIndex`:
  - Decodes off the main actor.
  - Builds the inverted index (D2) and provides `product(code:)`.
  - Tested with a fixture of about 200 products.
- [ ] 3.2 Plug `OfflineCzechIndexSource` into `FoodSearchEngine`, and extend the golden relevance tests with the index source.
- [ ] 3.3 `IndexDownloader` (D3):
  - Manifest check, Wi-Fi gating, SHA-256 check, atomic swap, backup exclusion.
  - Tests cover a checksum mismatch and the no-change case.
- [ ] 3.4 Add the `BackgroundRefresh` hook and a check on foreground.
- [ ] 3.5 Settings: status row, "Download now", cellular switch, and the About credit.
- [ ] 3.6 Barcode fallback in `BarcodeResolution` (D4), with tests.

## 4. Verify

- [ ] 4.1 CI green.
- [ ] 4.2 On device:
  - The index downloads on Wi-Fi.
  - Search works in airplane mode.
  - A Czech barcode that Garmin misses resolves.
