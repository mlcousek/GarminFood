## 1. Decode the account's real region/language

- [x] 1.1 `NutritionSettings` (GarminModels.swift) decodes `regionCode`/`languageCode` -- part of this route's confirmed-live shape (docs/garmin-routes.json) since 2026-09-16, never previously read.

## 2. Thread it through the write paths

- [x] 2.1 `CreateFoodLogEntryRequest` gains optional `regionCode`/`languageCode`; `FoodLogWriteBody.make` prefers them over its own hardcoded `"US"`/`"en"` constants when present.
- [x] 2.2 `OutboxEntry`/`Outbox.logFood` gain the same optional fields, captured at ENQUEUE time (not re-read at drain/delivery time) -- backward compatible, an entry queued by an older build decodes with `nil` and falls back exactly as before.
- [x] 2.3 `CustomFoodWriteBody.make`/`GarminClient.createCustomFood` gain the same optional override.
- [x] 2.4 `LogEntryCoordinator.confirm`/`confirmCustomFood`/`confirmMealPreset` (FoodLogCore) gain the same optional parameters, threaded to `Outbox.logFood`.
- [x] 2.5 App layer passes `environment.profile.settings?.regionCode`/`.languageCode` (already cached, refreshed on app foreground) into all three call sites: `LogEntryConfirmView.confirm()`, `MealPresetConfirmView`'s confirm action, `MatchConfirmationView`'s `CreateInGarminConfirmView.createInGarmin()`.

## 3. Tests

- [x] 3.1 `FoodLogWriteBodyTests.swift`: defaults to `"US"`/`"en"` when no override is supplied (unchanged behavior); an explicit override wins; `Outbox.logFood` captures region/language into the entry; an old (pre-this-field) outbox entry JSON still decodes with `nil` region/language and `FoodLogWriteBody.make` still falls back correctly.
- [x] 3.2 `CreateCustomFoodRequestTests.swift`: a caller-supplied region/language wins over the default in `CustomFoodWriteBody.make`.
- [x] 3.3 `LogEntryCoordinatorTests.swift`: `confirm(...)` carries region/language into the durably-enqueued `OutboxEntry`.

## 4. Verification

- [ ] 4.1 **CARRIED, needs CI.** No local Swift/Xcode toolchain -- push this branch and let `.github/workflows/build.yml` confirm both packages and the app target still build and the new/existing tests pass.
- [ ] 4.2 **CARRIED, needs a real device.** The stuck "ginger shot" outbox entry from before this fix must be deleted from the Sync Queue (retrying it replays the same stale `nil` region/language and will 400 again) and re-logged fresh. Confirm the new attempt either succeeds, or -- if it still 400s -- report the new diagnostics line back, since the account's actual `regionCode`/`languageCode` value from `nutritionSettings` has never been directly observed and this fix's premise (that it differs from `"US"`/`"en"` in a way that matters here) is itself unconfirmed until a real device proves it one way or the other.
