## 1. Model and lifecycle

- [ ] 1.1 Add a stable local identity to each usage event and carry it from
  outbox creation through confirmation.
- [ ] 1.2 Add targeted usage-history removal for delivered-entry deletion and
  queued-entry cancellation; never remove an unrelated identical food.
- [ ] 1.3 Pass the selected nutrition day and durable-entry count into the
  gamification confirmation boundary.

## 2. Lifetime accounting

- [ ] 2.1 Attribute calorie totals and daily maxima to the selected nutrition
  day.
- [ ] 2.2 Record one lifetime log per durable food entry in a preset.
- [ ] 2.3 Replace adjacent-call-only goal-day tracking with per-date
  idempotency and define the persistence/migration bounds.

## 3. Regression coverage

- [x] 3.1 Add persistence/reload tests for the lifetime ledger.
- [ ] 3.2 Add red-to-green package tests for out-of-order goal statuses.
- [ ] 3.3 Add usage-history identity/removal tests.
- [ ] 3.4 Add app integration tests for delete/cancel, backdated entries,
  and meal presets.
- [ ] 3.5 Add an achievement-permanence regression case to the delete flow.

## 4. Verification

- [ ] 4.1 Run `swift test` for `FoodLogCore` and `Gamification`.
- [ ] 4.2 Run the app-target integration suite on iOS Simulator.
- [ ] 4.3 Perform the manual lifecycle scenarios from `design.md`.
