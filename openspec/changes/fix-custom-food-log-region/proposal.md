## Why

A real device error: logging a just-created custom food failed with `400 BadRequestException: "Custom food nutrition information is missing for the provided food id with region code and language code."` — the exact same message the earlier `createCustomFood` bug produced, but this time on `/nutrition-service/food/logs` (the LOG write), not `/nutrition-service/customFood` (the CREATE write). Diagnostics confirmed creation itself wasn't failing; the same queued log entry kept retrying and failing identically for 13+ minutes until the outbox gave up.

Root cause: every food-log write and custom-food creation in this app has always hardcoded `regionCode: "US"`/`languageCode: "en"`, regardless of the account's real locale. `FoodLogWriteBody`'s own existing comment already documented that region/language "are not checked against the food" for a REGULAR Garmin/FatSecret food — but a custom food's nutrition record is looked up by the exact `(foodId, regionCode, languageCode)` tuple it was created under, so if Garmin actually stores/normalizes a custom food's region under the account's real locale (not necessarily "US"/"en"), logging it with the hardcoded fallback can't find that record.

The fix: `nutritionSettings` (`GET /nutrition-service/settings/{date}`) already returns the account's real `regionCode`/`languageCode` — confirmed live since 2026-09-16 — but this app never decoded those two fields. They're now decoded and threaded through as an optional override on every food-log write and custom-food creation, falling back to the same hardcoded constants when unavailable (so nothing regresses for the working regular-food-log path).

## What Changes

- `NutritionSettings` (GarminKit) decodes `regionCode`/`languageCode` — already part of this route's confirmed-live shape, simply never read.
- `CreateFoodLogEntryRequest`/`OutboxEntry` gain optional `regionCode`/`languageCode` fields, captured at ENQUEUE time (not re-read at delivery) so a custom food logs under the same region/language it was actually created under even if cached settings change later. Backward-compatible: an entry queued by an older build (missing these keys) decodes with `nil`, same fallback as before this fix.
- `FoodLogWriteBody.make`/`CustomFoodWriteBody.make` prefer the caller-supplied region/language over the hardcoded `"US"`/`"en"` default when present.
- `LogEntryCoordinator.confirm`/`confirmCustomFood`/`confirmMealPreset` (FoodLogCore) and `GarminClient.createCustomFood` all gain optional `regionCode`/`languageCode` parameters, threaded through to the wire body.
- App layer (`LogEntryConfirmView`, `MealPresetConfirmView`, `MatchConfirmationView`'s `CreateInGarminConfirmView`) passes `environment.profile.settings?.regionCode`/`.languageCode` (already cached from app foreground refresh) into every one of these calls.

## Non-goals

- **Changing the region/language for the REGULAR (non-custom) food-log path away from `"US"`/`"en"` by default.** The existing hardcoded fallback is left in place and known to work (this project's own first real write); this change only adds the ABILITY to override it with the account's real values, gated on `nutritionSettings` having actually loaded.
- **Retrying the stuck outbox entry automatically.** An entry already queued before this fix carries `regionCode: nil`/`languageCode: nil` baked in — manually retrying it replays the SAME old data and will 400 again. The owner needs to delete it from the Sync Queue and log the food again fresh once this fix is on-device.
- **Confirming what the account's actual regionCode/languageCode value is.** Still unconfirmed until a real device reports back what `nutritionSettings` actually returns for this specific field on this account.

## Impact

Affected surfaces: `GarminModels.swift`, `GarminClient.swift`, `Outbox.swift` (GarminKit); `LogEntryCoordinator.swift` (FoodLogCore); `LogEntryConfirmView.swift`, `MealPresetConfirmView.swift`, `MatchConfirmationView.swift` (GarminFood app target). No new Garmin route, no new local store — purely threading an already-confirmed-live field through the existing write paths.

**Depends on**: `nutritionSettings` (confirmed live 2026-09-16), the `fix-create-custom-food` change earlier this session.

**Unblocks**: nothing further planned.
