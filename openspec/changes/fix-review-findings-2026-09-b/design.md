## Context

Two findings, each checked against 4cea263 before any change. Paths are under
`ios/`. Line numbers are from 4cea263.

## Verdicts and evidence

### 1. Garmin wire dates use the device calendar: real

The day that goes to Garmin comes from FoodLogCore `NutritionDate.string(from:
calendar:)`, with `calendar` defaulting to `.current`
(`FoodLogCore/.../NutritionDate.swift:23-29`). Its `DateFormatter` got
`formatter.calendar = calendar` with no locale, so the year is spelled in the
device's calendar. With the Buddhist calendar, 2026-09-30 came out as
`2569-09-30`. With the Japanese calendar it came out as `0008-09-30`, because
Reiwa 8 is the year. That string then goes to Garmin:

- request paths: `DayLogLoader.swift:114` becomes `GarminClient.dailyFoodLog(date:)`,
  which is `/nutrition-service/food/logs/{date}` (`GarminClient.swift:119`).
  `ProfileLoader.swift:33` becomes `/nutrition-service/settings/{date}`, and
  `GarminHealthCache`/`GarminHealthSync` produce the range and day routes.
- write bodies: `LogEntryConfirmView.swift:375`,
  `MealPresetConfirmView.swift:187` and the Siri/Control intents become the
  outbox `date`, which becomes `mealDate` (`FoodLogWriteBody`).
  `WeightLogCoordinator.swift:172` becomes a weigh-in's `calendarDate`.

Garmin's dates were also read with the device calendar.
`GarminHistoryImport.loggedAt` (`GarminHistoryImport.swift:133-151`) parsed
Garmin's zone-less `logTimestamp` using `formatter.calendar = calendar`. An
explicit calendar wins over the POSIX locale's, so on a Buddhist phone
"2026-..." was read as Buddhist year 2026, which is 1483 CE.

The same day keys are read back by component parsers and formatters that
also used the injected calendar: `NutritionDayBoundary.swift:77`, `:137`;
`WeekKey.swift:44`, `:93`; `StreakFreezeStore.swift:170`, `:183`;
`SportRules.swift:216`; `DaySignalsBuilder.swift:324`, `:454`. The app's own
parsers already read keys as Gregorian (`BingoGridView.swift:30`,
`RecordsView.swift:82`, `SupplementUI.swift:19`), and so does
FoodLogCore `SupplementDate`, which uses civil-day arithmetic. So a
non-Gregorian phone also disagreed with itself.

Already correct, and moved onto the helper only so that every Garmin date
has one home: `WeightSync.localCalendarDate` (explicitly Gregorian/POSIX,
`:550`), `ActivityCacheStore.parseGMT` (explicit), and the
`ISO8601DateFormatter` sites (`GarminModels.swift:812`,
`Reconciliation.swift:512`, `FastingLogMoments`, `LocalNutritionReader`).
`ISO8601DateFormatter` is Gregorian and GMT by definition. The weigh-in and
drink bodies (`GarminModels.swift:1207`, `:1275`) set only the POSIX locale.
In practice that locale implies the Gregorian calendar, but nothing said so
explicitly.

Out of scope: the vault's dates. TrainingCore `LocalDate`, `HubEventClock` and
VaultKit are already explicitly Gregorian. Also out of scope are local-only
calendar arithmetic that never reaches Garmin (`SeasonalCalendar`,
`AchievementSignals`, the backup file name) and deep-link dates.

### 2. Custom-food multiplier lets an invalid `servingQty` into the outbox: real, partly

Not real as stated. A zero, negative or non-finite resulting amount never
reached the outbox:

- `LogEntryCoordinator.confirmCustomFood` checks the typed amount
  (`LogEntryCoordinator.swift:123`, `LogQuantity.isValid`). Then, before
  `outbox.logFood`, it checks the resulting backing amount:
  `guard target.numberOfUnits.isFinite, target.numberOfUnits > 0`
  (`:132`, since feccdef7).
- `confirmMealPreset` makes the same check for every custom ingredient up
  front (`:199-202`).
- The editor accepts a multiplier only within `LogQuantity`
  (`CustomFoodEditorView.swift:88`, `:100-103`).

Real: nothing bounded the resulting amount from above. Two in-bound numbers
could multiply to 10^8 servings (10 000 × 10 000). A stored draft never passes
through the editor: an older file or a restored backup can carry a multiplier
of any size, and a finite 1e300 went straight to the outbox. That amount
is exactly what `LogQuantity` exists to stop: `servingQty` far beyond anything
eaten, and totals no display can render (`LogQuantity.swift` header). The
confirm screen also didn't know about the product. It showed "Log it" as
enabled, and a refusal said "Enter an amount greater than zero and at most
10 000", which is false for the amount that was actually typed.

## Decisions

- **D1 One wire-date helper in GarminKit (1).** `GarminWireDate` is the lowest
  layer that knows Garmin's formats. It provides day, local timestamp, ISO
  timestamp, key-to-noon and key-to-midnight conversions, and a Gregorian
  calendar for day arithmetic. The caller supplies only a `TimeZone`. That
  makes it impossible to pass a device calendar's system in, and it keeps the
  day boundary where the design put it: the device's local day
  (`NutritionDate` header, and `WeighInWriteBody` for local wall clock versus
  UTC).
- **D2 `NutritionDate` is the key's single spelling (1).** Its `calendar`
  parameter is kept, so no call site changes, but it now contributes only its
  time zone. New `startOfDay(fromDayString:)`, `noon(ofDayString:)` and
  `keyCalendar(matching:)` read keys back. Gamification already imports
  FoodLogCore and calls them. It does not import GarminKit, so the module
  boundary stays as it was. Tests inject a Buddhist, Japanese, Islamic or
  Hebrew `Calendar` value. `Calendar.current` is never mutated.
- **D3 No key migration (1).** On a Gregorian phone every string is identical
  to before. A non-Gregorian phone already wrote requests Garmin couldn't
  answer for the right day, and its keys already disagreed with the app's own
  Gregorian parsers. Rewriting its old keys (for example `2569-…`) is out of
  scope for a personal app on a Gregorian phone. They simply stop matching the
  current day.
- **D4 The amount Garmin receives uses the logged-amount bound (2).** There is
  no new limit. `LogQuantity` already documents why 10 000 servings is the
  most one entry may carry, including a "1 g" backing serving logged by
  weight. The check is a model method (`CustomFoodDraft.backingQuantityIsValid`,
  and `MealPreset.backingQuantitiesAreValid` for presets). It is enforced in
  the coordinator before anything is enqueued, and read by the screens to
  disable the button. A food without a backing passes the check, because
  nothing is sent for it: `needsGarminMatch` owns that case.
- **D5 A separate error and message (2).** `LogQuantityError.backingOutOfRange`
  carries "The amount recorded in Garmin must be greater than zero and at most
  10 000 servings of the food it's recorded as…". It is new EN and CS text in
  FoodLogCore's `.lproj` files. The confirm screen shows it as a warning label
  in the same style as "Needs a Garmin match", and the preset screen shows it
  in its existing message row.

## Risks

- There is no local compiler. CI verifies everything (`swift test` for
  GarminKit, FoodLogCore and Gamification, plus the app build).
- `WeekKey.dayKeys` now builds a formatter for each key through
  `NutritionDate.string`, which means seven per call. That is negligible here.
  The hot path, `DaySignalsBuilder`, keeps its cached formatter.
- The test that checks the Japanese era expects Foundation to spell Reiwa 8 as
  `0008` under `yyyy`. If a Foundation version differs, only that control
  assertion fails, not the fix.
