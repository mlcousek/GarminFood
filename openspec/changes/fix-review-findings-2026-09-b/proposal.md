## Why

A second external review reported two findings against `main` at 4cea263.
Each was checked against the code before anything was changed (evidence in
design.md). The first is real; the second is real in part: the zero, NaN and
negative amounts it names were already refused before the outbox, but the
amount Garmin receives for a custom food had no upper bound.

| # | Sev | Finding | Verdict |
|---|-----|---------|---------|
| 1 | High | Garmin wire dates use the device calendar; a non-Gregorian calendar writes wrong years into request paths and write bodies and misreads Garmin's dates | **Real** |
| 2 | Medium | A custom food's multiplier lets a zero or invalid `servingQty` into the durable outbox | **Real, partly** (zero/NaN/negative already refused; the upper bound was missing) |

## What Changes

- **1** One helper, GarminKit `GarminWireDate`, makes every Garmin date and
  reads every Garmin date back: Gregorian calendar, `en_US_POSIX`, and an
  explicit time zone. The time zone is still the device's own for a local
  day, so what a "day" means is unchanged. FoodLogCore `NutritionDate` (the
  day in request paths and in `mealDate`, and the day key every store
  uses) now takes only its calendar's time zone. The Gamification functions
  that read and write those keys go through `NutritionDate`, so a key is
  written and read back the same way.
- **2** `CustomFoodDraft.backingQuantityIsValid(for:)` holds the amount sent to
  Garmin (the typed amount times the multiplier) to the same `LogQuantity`
  bound as every other logged amount: finite, greater than zero, at most
  10 000. `LogEntryCoordinator` refuses anything outside it before enqueueing,
  for a single custom food and for a meal preset, with the new
  `LogQuantityError.backingOutOfRange`. Both confirm screens disable "Log it"
  and give the reason, in the style they already use.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `garmin-sync` (finding 1) and `food-catalog` (finding 2) each gain an ADDED
  requirement.

## Impact

- GarminKit: `GarminWireDate.swift` (new). `GarminModels` (weigh-in and drink
  bodies, `logTimestamp`), `WeightSync.localCalendarDate` and
  `Reconciliation.parseLogTimestamp` use it.
- FoodLogCore: `NutritionDate` (Gregorian, with new key parsers),
  `GarminHistoryImport.loggedAt`, `ActivityCacheStore.parseGMT`,
  `DaySignalsBuilder`, `LocalNutritionReader`, `FastingLogMoments`. Also
  `CustomFoodDraft.backingQuantityIsValid`, `MealPreset.backingQuantitiesAreValid`,
  `LogQuantityError.backingOutOfRange`, and `LogEntryCoordinator`.
- Gamification: `NutritionDayBoundary`, `WeekKey`, `FreezeDayKey` and
  `SportRules.dayKey` read and write keys through `NutritionDate`.
- App: `LogEntryConfirmView` and `MealPresetConfirmView` get the new check.
  `collectionDayText` reads its key as Gregorian. One new string, EN and CS,
  in FoodLogCore's `.lproj` files.
- Stored data: on a Gregorian phone (the owner's) every key and wire date is
  byte-for-byte what it was before. On a non-Gregorian phone, keys written
  before this change carry the old year and are not migrated (design.md D3).
- No new Garmin route. No change to the outbox file format.
