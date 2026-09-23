## Why

Search quality is the owner's top priority, and live Czech search depends on
Open Food Facts' public API. That API is slow and flaky: it returned 503s on
2026-09-22. It filters on thin country tagging and can't work offline. On top
of that, Garmin's barcode lookup often misses Czech EANs
(`docs/garmin-food-log-contract.md`), and there is no fallback today.

On 2026-09-23 the owner approved a downloadable offline index: a slim,
weekly-refreshed copy of Czech OFF products that the app searches locally.
Results become instant, the app's own ranking runs on the full candidate set,
and search works offline.

## What Changes

**Weekly index build (GitHub Actions)**

- A workflow runs weekly, or on demand.
- It reads OFF's full data export and keeps only products sold in Czechia
  (`countries_tags` contains `en:czech-republic`).
- Fields kept: barcode, Czech name, fallback name, brand, pack quantity, and
  kcal, carbs, protein, fat, sugar, fiber and salt per 100 g.
- Products with no name or no kcal are dropped.
- Output: a gzipped JSON file plus a manifest (version, count, SHA-256, build
  date).
- Both are published as assets on a rolling GitHub Release (`food-index`) in
  this public repo, so hosting is free.

**Download in the app**

- The app checks the manifest at most once a day.
- It downloads a new version on Wi-Fi only, in the existing background
  refresh task or on foreground.
- It verifies the SHA-256 and atomically swaps the new file into Application
  Support. A failed or partial download never replaces the good file.
- Settings shows the index status, for example "Czech offline database ·
  38,412 products · updated 3 days ago", with a "Download now" button and an
  optional "Allow on cellular" switch.

**Offline search source**

- `OfflineCzechIndexSource` plugs into `FoodSearchEngine` (from
  `rebuild-food-search`).
- On load it builds an in-memory inverted index from normalized, stemmed
  tokens to products.
- Queries are answered instantly and offline, using the same ranking as every
  other source.
- Results are deduped against live OFF and Garmin results.

**Barcode fallback**

- When Garmin's barcode route misses, the scanner looks the EAN up in the
  offline index.
- A hit goes through the existing Garmin-match flow, the same as a live OFF
  result.

**Attribution**

- OFF data is ODbL. The built index is ODbL too.
- The release notes and Settings → About credit Open Food Facts, with a link
  to the licence.

## Non-goals

- A full OFF mirror, or other countries.
- Images, ingredients or allergens. They would bloat the file.
- Replacing live OFF. Live search still runs, to catch products newer than the
  last build.
- Building the index on the phone. It is built only in CI.

## Capabilities

### New Capabilities

- `offline-food-index`: index build, distribution, local search source,
  barcode fallback.

## Impact

- **New build tooling:**
  - `tools/build-czech-food-index/`: a Node or Python script with a README.
  - `.github/workflows/food-index.yml`: runs on a weekly cron and on
    `workflow_dispatch`, and publishes the release assets.
- **FoodLogCore:**
  - `OfflineFoodIndex`: load and decode, build the inverted index, look up by
    code.
  - `OfflineCzechIndexSource`.
  - Tests use a small fixture index.
- **App:**
  - `IndexDownloader`: manifest check, Wi-Fi gating, SHA-256 check, atomic
    swap.
  - A `BackgroundRefresh` hook.
  - The Settings status row.
  - The barcode flow fallback.
- **Depends on**: `rebuild-food-search` (the `FoodSearchSource` protocol and
  `SearchText`).
- **Unblocks**: nothing.
