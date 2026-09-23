## 1. Probe + wire layer (GarminKit)

- [ ] 1.1 Re-probe `GET /weight-service/weight/range/{start}/{end}?includeAll=true` read-only with `tools/garmin-get.mjs`. Record the status and shape in `docs/garmin-routes.json`, and pick D2's path.
- [ ] 1.2 Add models: `GarminWeighIn` (samplePk, calendarDate, weightGrams → weightKg, timestampGMT, sourceType; the rest optional) and `HydrationDaily` (valueInML, goalInML, lastEntryTimestampLocal). Add decode tests from the 2026-09-23 payloads.
- [ ] 1.3 Add `GarminClient.weighIns(on:)` (plus a range method per 1.1), `hydrationDaily(date:)`, and `deleteWeighIn(date:samplePk:)`.
- [ ] 1.4 Add a `deleteWeighIn` operation to `WeightOutbox`, keeping backward-compatible decoding of existing outbox files. Allow negative values for `HydrationOutbox`.

## 2. Domain (FoodLogCore)

- [ ] 2.1 `WeightHistoryMerge` (D1) plus tests: delivered duplicate, pending, Garmin-only, near-miss.
- [ ] 2.2 `WeightGoalProgress` (D5) plus tests: fraction, kg to go, ETA from slope, ETA from rate, and no ETA when moving away.
- [ ] 2.3 `HydrationDayTotal` (D4) plus tests.
- [ ] 2.4 A per-day Garmin weigh-in/hydration cache store (uses `PersistedJSON`).

## 3. App

- [ ] 3.1 `WeightLoader`/`HydrationLoader` refresh on foreground, on screen appear and on pull-to-refresh, render from cache first, and show a quiet error caption.
- [ ] 3.2 Delete in `WeightView`: a Garmin sample enqueues a delete; a pending local entry cancels.
- [ ] 3.3 Remove-drink in `HydrationView` enqueues a negative delta or cancels.
- [ ] 3.4 Weight card goal bar, kg to go and ETA; the water card uses the effective goal.
- [ ] 3.5 Settings → "Goals" section: water and weight overrides, each with "Use Garmin's goal".

## 4. Verify

- [ ] 4.1 CI green.
- [ ] 4.2 On device:
  - A weigh-in logged in Connect appears in the app.
  - Deleting in the app removes it from Connect.
  - Water from Connect counts.
  - Removing a drink lowers Connect's total.
  - Goals show correctly.
