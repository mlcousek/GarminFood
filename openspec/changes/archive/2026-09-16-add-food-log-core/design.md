## Context

Garmin's food search (confirmed live 2026-09-14) is the only food database this project has access to, and it is FatSecret-backed — good coverage, including Czech results (`rohlik` → 13 hits), but it is a network call with normal latency. A two-tap logging flow cannot afford a search round trip on the critical path every time; the previous 10 things someone logs are, empirically, mostly the same 3–4 things.

## Goals / Non-Goals

**Goals:**

- Logging a food someone has logged before should not require typing or a network wait.
- The serving-size ambiguity in Garmin's response (multiple `nutritionContents` entries per food) is resolved once per food, then remembered.
- Barcode scanning gets from a physical package to a resolved food in one scan when the product exists in Garmin's database.

**Non-Goals:**

- Building a second food database. Garmin's is the only source of truth for what gets logged, because only foods it recognises can be written back to it.
- Nutrition editing (correcting a food's macros). If Garmin's data is wrong, the fix is a custom food, not an edit to Garmin's catalog entry.

## Decisions

### D1 — Favourites and recents are ranked locally, not just mirrored from Garmin

Garmin's search response includes `isFavorite`/`isRecent` per result, but those only exist *after* a search — they don't help build a zero-search quick-pick list. This project keeps its own local usage log (food id + serving id + timestamp, incremented on every successful log) and ranks a "quick pick" shelf by recency and frequency together, independent of whether Garmin agrees a given item is a "favorite". This is what a Control's pre-configured buttons (`add-glanceable-surfaces`) bind to.

### D2 — A serving choice is remembered per food, not re-asked every time

The first time a food is logged, the user picks which of Garmin's `nutritionContents` entries applies (100g vs. one medium banana vs. one small banana). That choice — `(foodId, servingId, numberOfUnits)` — is cached locally and reused as the default the next time that same food is picked, cutting the flow by one screen for repeat entries. It remains editable; the cache is a default, not a constraint.

### D3 — Barcode scanning is deprioritized: Garmin's own barcode coverage fails for Czech products

`GET /nutrition-service/food/search/barCode?barCode={ean}` does exist (found and confirmed reachable by `establish-garmin-nutrition-contract`) — this is no longer a route-discovery problem. It is a **data coverage** problem instead, confirmed directly by the owner (2026-09-14): a Czech product barcode was not recognized by the Garmin Connect app's own native, first-party barcode scanner. If Garmin's own client can't resolve it, this project's barcode feature would mostly hit dead ends for its primary user.

Consequence: barcode scanning drops from "core flow" to "build only if it turns out useful for non-Czech/imported packaged goods." It is not removed from the plan (VisionKit's `DataScannerViewController` work and UPC-A/EAN-13 normalisation — `VNBarcodeSymbology` has no UPC-A case, it's reported as `.ean13` with a leading zero — remain valid if revisited), but it no longer blocks anything else, and no further live probing of the barcode route is planned for now (owner decision). Text search remains the confirmed-reliable path for Czech foods (`rohlik` → 13 real results). If a scanned barcode fails to resolve, the fallback remains offering custom-food creation pre-filled with the scanned code as a note.

### D4 — Custom foods store the same shape Garmin expects, from the start

A custom food record uses the exact same fields the write contract (from `establish-garmin-nutrition-contract`) requires, so that once custom-food creation is confirmed possible via the API, wiring it up is additive rather than a rewrite. If custom-food creation turns out not to be possible via the private API, a custom food logs as a best-fit existing Garmin food with an adjusted quantity, and the discrepancy is shown to the user rather than hidden.

## Risks / Trade-offs

- **The remembered serving default becomes wrong** (Garmin changes a `servingId`) → the app should treat a serving-id-not-found response as reason to re-resolve from a fresh search, not fail silently.
- **Barcode-to-EAN13 normalisation misses valid barcodes** (an 8-digit EAN-8, ITF-14 case pack) → these are accepted symbologies (`add-glanceable-surfaces` scans for them) but text search may not recognise them; fall back to custom-food creation rather than a dead end.
- **Local favourites/recents drift from what's actually in Garmin** if the same account is also used from the Garmin Connect app directly → acceptable. This project's local ranking is a convenience shelf, not a synced state; Garmin's own log remains authoritative (see `garmin-sync`'s read-from-Garmin rule).
