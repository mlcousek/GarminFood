## 1. Probe + wire layer (GarminKit)

- [x] 1.1 Re-probe `GET /weight-service/weight/range/{start}/{end}?includeAll=true` read-only with `tools/garmin-get.mjs`. Record the status and shape in `docs/garmin-routes.json`, and pick D2's path.
- [x] 1.2 Add models: `GarminWeighIn` (samplePk, calendarDate, weightGrams → weightKg, timestampGMT, sourceType; the rest optional) and `HydrationDaily` (valueInML, goalInML, lastEntryTimestampLocal). Add decode tests from the 2026-09-23 payloads.
- [x] 1.3 Add `GarminClient.weighIns(on:)` (plus a range method per 1.1), `hydrationDaily(date:)`, and `deleteWeighIn(date:samplePk:)`.
- [x] 1.4 Add a `deleteWeighIn` operation to `WeightOutbox`, keeping backward-compatible decoding of existing outbox files. Allow negative values for `HydrationOutbox`.

## 2. Domain (FoodLogCore)

- [x] 2.1 `WeightHistoryMerge` (D1) plus tests: delivered duplicate, pending, Garmin-only, near-miss.
- [x] 2.2 `WeightGoalProgress` (D5) plus tests: fraction, kg to go, ETA from slope, ETA from rate, and no ETA when moving away.
- [x] 2.3 `HydrationDayTotal` (D4) plus tests.
- [x] 2.4 A per-day Garmin weigh-in/hydration cache store (uses `PersistedJSON`).

## 3. App

- [x] 3.1 `WeightLoader`/`HydrationLoader` refresh on foreground, on screen appear and on pull-to-refresh, render from cache first, and show a quiet error caption.
- [x] 3.2 Delete in `WeightView`: a Garmin sample enqueues a delete; a pending local entry cancels.
- [x] 3.3 Remove-drink in `HydrationView` enqueues a negative delta or cancels.
- [x] 3.4 Weight card goal bar, kg to go and ETA; the water card uses the effective goal.
- [x] 3.5 Settings → "Goals" section: water and weight overrides, each with "Use Garmin's goal".

## 4. Verify

- [x] 4.1 CI green. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.2 On device:
  - A weigh-in logged in Connect appears in the app.
  - Deleting in the app removes it from Connect.
  - Water from Connect counts.
  - Removing a drink lowers Connect's total.
  - Goals show correctly.

## Implementation notes

- D2 path: the range route was re-probed and confirmed (`dailyWeightSummaries[].allWeightMetrics[]`), so a refresh makes one `weighInRange` call: the full 90 days at most once a day or on pull-to-refresh, otherwise today and yesterday. `weighIns(on:)` (dayview) stays as the documented fallback and is unused.
- The Garmin reads live in FoodLogCore's `GarminHealthSync` (unit-tested with a fake reader and a real cache store). The app calls it through `AppEnvironment.refreshGarminHealth(force:)`. Auth failures go to `GarminAuthState.report`; other failures set the loaders' quiet "couldn't refresh" flag and are logged to Diagnostics.
- After any weight or water delivery, the app re-reads Garmin in the background, so a just-delivered weigh-in picks up its `samplePk`.
- Weight and water outbox entries (including queued Garmin deletes and negative drink corrections) now appear in the sync queue and its badge count.
- The old per-device `hydrationDailyGoalML` preference is no longer read. The water goal is Garmin's unless overridden in Settings → Goals (or the Water screen's "Edit goal").
- The Trends screen's hydration streak and chart still sum only drinks logged in the app, because Garmin's total is read for today only.
