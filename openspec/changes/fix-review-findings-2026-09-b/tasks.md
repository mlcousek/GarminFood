## 1. Verify every finding

- [x] 1.1 Check findings 1-2 against 4cea263; record verdict and evidence in design.md

## 2. Real findings

- [x] 2.1 (1) `GarminWireDate` in GarminKit (Gregorian, `en_US_POSIX`, explicit time zone); write bodies, `logTimestamp`, `WeightSync`, `Reconciliation` use it. Test: `GarminWireDateTests`
- [x] 2.2 (1) `NutritionDate` Gregorian with key parsers; `GarminHistoryImport.loggedAt`, `ActivityCacheStore.parseGMT`, `DaySignalsBuilder`, `LocalNutritionReader`, `FastingLogMoments` through the helper. Test: `NutritionDateTests` (Buddhist/Japanese calendars injected)
- [x] 2.3 (1) Gamification `NutritionDayBoundary`, `WeekKey`, `FreezeDayKey`, `SportRules.dayKey` read/write keys through `NutritionDate`; app `collectionDayText` Gregorian. Test: `WeekKeyTests.testDayKeysStayGregorianOnABuddhistPhone`
- [x] 2.4 (2) `CustomFoodDraft.backingQuantityIsValid`, `MealPreset.backingQuantitiesAreValid`, `LogQuantityError.backingOutOfRange` (EN + CS); coordinator refuses before enqueue; both confirm screens disable "Log it" with the reason. Tests: `CustomFoodTests`, `LogEntryCoordinatorTests`

## 3. Checks

- [x] 3.1 `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`
- [x] 3.2 `openspec validate fix-review-findings-2026-09-b --strict`
- [ ] 3.3 CI green (`swift test` for GarminKit, FoodLogCore, Gamification; app + widget build)
- [ ] 3.4 Device check after sideload: logging and Today still show the right day; a custom food at an amount whose Garmin amount exceeds 10 000 servings shows the warning and can't be logged
