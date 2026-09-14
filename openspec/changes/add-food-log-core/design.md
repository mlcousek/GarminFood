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

### D3 — Barcode-to-food resolution normalises UPC-A to EAN-13

VisionKit's `VNBarcodeSymbology` has no UPC-A case — a UPC-A barcode is returned as `.ean13` with a leading zero. Since Garmin's search is text-based, not barcode-based (no barcode-lookup route has been found — see `establish-garmin-nutrition-contract` task 2), a scanned code is first tried as a direct search term, and on no match the leading zero is stripped and retried, matching how UPC-A/EAN-13 equivalence actually works. If Garmin never exposes a real barcode-to-food route, the fallback is offering to create a custom food pre-filled with nothing but the scanned code as a note.

### D4 — Custom foods store the same shape Garmin expects, from the start

A custom food record uses the exact same fields the write contract (from `establish-garmin-nutrition-contract`) requires, so that once custom-food creation is confirmed possible via the API, wiring it up is additive rather than a rewrite. If custom-food creation turns out not to be possible via the private API, a custom food logs as a best-fit existing Garmin food with an adjusted quantity, and the discrepancy is shown to the user rather than hidden.

## Risks / Trade-offs

- **The remembered serving default becomes wrong** (Garmin changes a `servingId`) → the app should treat a serving-id-not-found response as reason to re-resolve from a fresh search, not fail silently.
- **Barcode-to-EAN13 normalisation misses valid barcodes** (an 8-digit EAN-8, ITF-14 case pack) → these are accepted symbologies (`add-glanceable-surfaces` scans for them) but text search may not recognise them; fall back to custom-food creation rather than a dead end.
- **Local favourites/recents drift from what's actually in Garmin** if the same account is also used from the Garmin Connect app directly → acceptable. This project's local ranking is a convenience shelf, not a synced state; Garmin's own log remains authoritative (see `garmin-sync`'s read-from-Garmin rule).
