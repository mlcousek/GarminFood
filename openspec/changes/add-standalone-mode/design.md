## Context

This design was written on 2026-09-24 against `origin/main` @ `b117adf`. It
rests on the dependency map in `docs/garmin-dependency-map.md`, which lists
every file and type involved. The load-bearing facts, all from reading code:

- **Every logging path ends in a Garmin `foodId`/`servingId`.**
  `LogEntryCoordinator` writes `Outbox.logFood(foodId:servingId:…)`.
  `CustomFoodDraft` stores a required `backingFoodId`. `FoodCatalogView`
  routes `.openFoodFacts` results to `MatchConfirmationView`, which needs a
  Garmin search or `createCustomFood`. `SearchOrigin.isDirectlyLoggable`
  is `.local || .garmin`.
- **The food log exists only in Garmin.** `DayLogLoader` reads
  `GarminClient.dailyFoodLog`. `MealDashboard.build(date:log:meals:
  outboxEntries:foods:)` combines that read-back with queued outbox
  entries. `Reconciliation` removes delivered entries. `UsageHistoryStore`
  is capped at 500 events and stores no nutrients.
- **`DailyFoodLog` is the one type most consumers read:**
  `MealDashboard.build`, `CopyMealPlanner.plan(log:mealType:)`,
  `GamificationEngine.refreshGoalStatus`,
  `FastingLogMoments.moments(fromGarminLog:)`, `UsageMealBackfill`, and
  `DayLogLoader.cachedFoodLogs`. `MacroTrendLoader` reads
  `calorieSummaryDaily`. The GarminKit DTOs are `Decodable` structs with
  internal memberwise initialisers only.
- **No sign-in gate.** `ContentView` goes straight to the tabs.
  `AuthBannerView` shows "Not connected to Garmin" whenever `authState` is
  not `.authenticated`. `Outbox.drain` returns `.notSignedIn` without
  spending attempts, so a signed-out install queues forever.
- **Weight and water are local-first already.** `WeightStore` and
  `HydrationStore` commit first, `WeightHistoryMerge` and `HydrationDayTotal`
  merge with the cached Garmin reads, and goal overrides already exist
  (`AppPreferences.weightGoalOverrideKg`, start override,
  `waterGoalOverrideML`, 2000 ml fallback).
- **One composition root per process.** `AppServices.shared` builds every
  store once, with `let` properties. `AppEnvironment` exposes them. The
  widget extension runs no intents and shows no data.
- **Free Personal Team:** no App Groups, iCloud, Push or HealthKit
  (`openspec/config.yaml`). Only Keychain Sharing was confirmed blocked on
  a device, on 2026-09-14. The others are documented platform limits that
  this repo has not probed on a device. The plan depends on none of them.

## Evidence (probes)

No live probe was run for this change. The task forbade network access, and
nothing here needs a new Garmin route. Everything in Garmin-connected mode
uses routes already recorded in `docs/garmin-routes.json` with their dates.
Standalone mode calls **no Garmin route at all**.

| Route | Status in `docs/garmin-routes.json` | Used here |
|---|---|---|
| `PUT /nutrition-service/food/logs/quickAdd` | "documented, not exercised" (2026-09-16) | **No.** It is the only candidate for a future backfill (Non-goals). |
| `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` (Open Food Facts, not Garmin) | Not a Garmin route. Probed read-only on 2026-09-25 and recorded in `docs/openfoodfacts-product-route.md`: found returns 200 + `status: 1`; an unknown code returns 404 | **Yes, in standalone mode only.** It is step 3 of the barcode chain (`StandaloneBarcodeResolution`: own custom foods, then the offline index, then this route). |

## Goals / Non-Goals

**Goals**
- Garmin-connected mode behaves byte-for-byte as it does today.
- A standalone user can log, edit and review food with targets, track
  weight and water, and earn gamification, with zero Garmin calls.
- Local-first holds: every confirm is a local commit with no network wait.
- The new logic lives in the SPM packages, is pure where possible, and is
  unit-tested in CI.

**Non-goals**: see proposal.md. In short: no Garmin backfill, no cloud
sync, no HealthKit, no manual activities, no multi-user on one phone.

## Decisions

### D1 — `DataMode`, stored per install, existing installs classified silently

`enum DataMode: String, Codable { garminConnected, standalone }`, stored in
`UserDefaults` under `dataMode.v1` through `AppPreferences`. It lives in
FoodLogCore so that pure logic can depend on it.

When `dataMode.v1` is unset (the first launch of the new build),
`DataModeMigration.decide(storedMode:hasGarminToken:hasLocalHistory:)`
(pure, tested) decides as follows:

- `hasGarminToken` means `TokenProvider.shared.loadOAuth1Token() != nil`.
- `hasLocalHistory` means any outbox, usage history or weight or hydration
  entry exists.
- If either is true, the mode becomes **`.garminConnected`**, is stored, and
  **no onboarding** is shown. This is the owner's phone.
- If both are false, it's a fresh install: the mode stays unset and
  onboarding runs (D10).

Why not default everyone to Garmin and add a toggle? A new user would still
land on the Garmin banner first and have to find the switch. Asking once, at
the point where the answer matters, is the better experience. Silent
classification removes any risk for the existing user.

The widget extension never reads the mode. It shows no data and runs no
intents (`AppServices` header), and its `UserDefaults` container is separate
anyway.

### D2 — A local system of record: `LocalFoodLogStore`

This is a FoodLogCore actor. It keeps one JSON file per calendar month,
`Application Support/FoodLog/2026-09.json`, loaded through
`FoodLogCoreStorage.loadPersistedJSON`, so a file that can't be read is
quarantined rather than wiped (`fix-silent-store-wipe`). Writes are atomic.

Monthly shards keep every commit's rewrite small. A heavy logger (about 15
entries a day, with micronutrients) produces roughly 3 MB a year. A single
file would grow without bound and be rewritten on every tap.

```
LocalLogEntry {
  id: UUID                      // also the "logId" shown to the dashboard
  day: String                   // nutrition day, NutritionDate.string (same rule as Garmin mode)
  mealType: MealType
  loggedAt: Date
  food: LocalFoodRef { id, source: FoodSource, name, brandName?, barcode? }
  servingId: String, servingLabel: String, servingUnit: String?
  quantity: Double              // servings, validated by LogQuantity.isValid
  nutrients: [NutrientKind: Double]   // for the LOGGED amount (serving × quantity), snapshot at confirm
  customFoodId: UUID?, presetId: UUID?
  editedAt: Date?
}
```

- **Nutrients are snapshotted at confirm time.** The food's source may
  change later: an OFF product can be edited upstream, or a custom food can
  be edited locally. A logged day must not change retroactively. Garmin
  behaves the same way, because a logged entry keeps its nutrition.
- **No outbox, no drain, no "syncing" state.** The local commit *is* the
  system-of-record write, so the zero-network-wait rule holds structurally.
- **Kept forever.** It is not capped like `UsageHistory`. It is included in
  backups (D9).

### D3 — Read seam: `NutritionLogReading`, satisfied by Garmin and by a local reader

```swift
// GarminKit
public protocol NutritionLogReading: Sendable {
    func dailyFoodLog(date: String) async throws -> DailyFoodLog?
    func mealsForDate(date: String) async throws -> MealsForDate
    func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse
    func dailyUserSummary(date: String) async throws -> DailyUserSummary
}
extension GarminClient: NutritionLogReading {}   // no body changes
```

`LocalNutritionReader` (FoodLogCore) implements the same protocol from
`LocalFoodLogStore` and `LocalGoalStore`:

- `dailyFoodLog` returns a `DailyFoodLog`:
  - one `MealDetail` per meal type, with `loggedFoods` built from entries
    (`logId = entry.id.uuidString`, `foodMetaData` from the food reference,
    `nutritionContent` from the snapshot);
  - `mealNutritionContent` and `dailyNutritionContent` as sums;
  - `dailyNutritionGoals` from the goal in effect on that day (D6);
  - `mealNutritionGoals` from the optional per-meal split, or `nil`.
- `mealsForDate` returns the four default meals and no windows, so meal
  defaulting falls back to the clock through `MealTypeDefaulting`.
- `calorieSummaryDaily` returns per-day totals and that day's goal, for
  Trends.
- `dailyUserSummary` throws `LocalReaderError.unavailable`. The "Active
  today" line already hides on any failure.

Consumers change only the *type* they hold, from `GarminClient` to
`any NutritionLogReading`: `DayLogLoader`, `MacroTrendLoader`,
`GamificationEngine`, and `AppEnvironment.copyMealPlan`. In Garmin mode they
get the very same `GarminClient` instance, so behaviour is identical.

This needs additive `public init(...)` on the read DTOs. They stay
`Decodable`, and adding an initialiser changes no decoding.

**Alternatives rejected**

- *A neutral `DayLog` domain model that both backends convert into.* It
  would be cleaner in the long run, but it rewrites the dashboard, copy-meal
  and goal code in *Garmin* mode, which is the verified half. The owner's
  standing guidance is to unify toward the verified half, never away from
  it. It can be revisited once standalone mode has proven itself.
- *Draining the existing outbox into a local "fake Garmin"*
  (`FoodLogDelivering` on the local store). This reuses the pipeline but
  invents pending, sent and reconciled states for a write that is already
  durable. It would also run `Reconciliation`'s duplicate heuristics
  against local data, and it would fill the sync queue for a user who has
  nothing to sync.

### D4 — Write seam: `FoodLogging` and a mode-routing proxy

`FoodLogging` (FoodLogCore) is `LogEntryCoordinator`'s public surface, as it
is today:

- `confirm`, `confirmCustomFood`, `confirmMealPreset`, `edit`,
  `duplicate`, `copyMeal`, `deletePending`;
- plus `deleteCommitted(logId:date:)`, which covers the `.synced` branch
  that currently sits inline in `DayLogLoader.delete`.

The implementations:

- `LogEntryCoordinator` conforms by extension. Its bodies are unchanged.
  Its `deleteCommitted` is a straight move of `DayLogLoader`'s existing
  `client.deleteFoodLogEntries` call and error mapping.
- `LocalLogEntryCoordinator` (new) writes `LocalFoodLogStore`:
  - `confirm` snapshots `serving × quantity`;
  - `confirmCustomFood` uses the **custom food's own macros**, never a
    backing food's;
  - `edit` changes the entry in place, rescaling nutrients by the quantity
    ratio and moving it to the new meal if that changed;
  - `duplicate` and `copyMeal` append entries;
  - both kinds of delete remove the entry.
  - It updates `UsageHistoryStore`, `ServingDefaultStore` and
    `FoodCacheStore` exactly as the Garmin coordinator does, so quick picks,
    serving memory, streaks and "Log again" behave the same in both modes.
- `ModeRoutingFoodLogging` is held by `AppServices` and forwards each call
  to the implementation for the current `DataMode`, which it reads on every
  call. Views, `AppEnvironment` and the intents keep calling
  `services.logEntryCoordinator`, now typed `any FoodLogging`.

Local entries reach the dashboard as `MealEntry.status == .synced(logId:)`.
"Synced" in that type already means "present in the system of record". The
enum is left unrenamed to avoid churn in every view that switches over it.
The header comment says so.

### D5 — Food catalog without Garmin

- **Search.** `FoodSearchEngine.standard(garmin:)` accepts `nil`, which
  leaves out `GarminSearchSource`. Standalone mode gets Local, the offline
  Czech index and OFF.
- **Loggable origins.** `SearchOrigin.isDirectlyLoggable` becomes
  `isDirectlyLoggable(in: DataMode)`: every origin in standalone, today's
  rule in Garmin mode.
- **OFF and Czech results.** In standalone mode, `FoodCatalogView.select`
  sends them to the serving picker and `LogEntryConfirmView`.
  `MatchConfirmationView` is unreachable in that mode.
- **Custom foods.** `backingFoodId`, `backingFoodName` and
  `backingServingId` become optional. Existing files decode unchanged,
  because they have the values. `CustomFoodEditorView` hides the "closest
  Garmin food" section in standalone mode and still requires it in Garmin
  mode. A custom food with no backing food, seen in Garmin mode (after a
  mode switch), shows "Needs a Garmin match before it can be logged to
  Garmin" and opens the backing picker. It is never logged silently or
  dropped.
- **Barcode.** Standalone mode resolves in three steps:
  1. the offline index;
  2. once probed (task 3.5), `OpenFoodFactsClient.product(barcode:)`;
  3. otherwise the custom-food editor, with the code pre-filled.
  Garmin mode keeps `BarcodeResolution.resolve` unchanged. The online OFF
  lookup may be added to Garmin mode's fallback later, but that is outside
  this change.
- **Meal presets.** Ingredients may be of any origin in standalone mode.
  "Sync to Garmin" is hidden.
- **Siri "log X".** `LogNamedFoodIntent` searches `[.local, .offlineIndex]`
  in standalone mode. Siri's answer must stay fast, so OFF online is left
  out. It logs through `FoodLogging` and never calls `briefDelivery`.
- **Quick-pick intent and Controls.** They log through `FoodLogging`. In
  standalone mode they skip `briefDelivery`, so
  `ActionError.savedButSignedOut` can't happen.

### D6 — Local nutrition goals and the calculator

`LocalGoalStore` (FoodLogCore, JSON) holds `[LocalNutritionGoals]`:

```
LocalNutritionGoals {
  effectiveFrom: String         // nutrition day this goal starts applying
  calories: Double
  proteinG, carbsG, fatG: Double?
  mealSplit: [MealType: Double]? // optional fractions; nil = no per-meal targets
}
```

The goal for a given day is the latest one whose `effectiveFrom` is on or
before that day. Past days keep the target they had, so Trends and goal
status don't rewrite history when the user edits a goal. The ring colour
band `CalorieBand` and `TodaySummary.GoalState` apply unchanged.

`GoalCalculator` (pure, tested with reference values) computes a suggested
starting target. Inputs:

- sex: female or male. It only selects the Mifflin–St Jeor constant, and
  the UI explains why it asks;
- birth year;
- height in cm;
- current weight: the latest local weigh-in, or typed;
- activity level: sedentary 1.2, light 1.375, moderate 1.55, very 1.725 or
  extra 1.9;
- goal: lose, maintain or gain;
- pace: 0.25, 0.5 or 0.75 kg a week.

How it works:

- BMR = 10·kg + 6.25·cm − 5·age + (male +5 | female −161).
- TDEE = BMR × activity factor.
- Target = TDEE ∓ pace × 7700 / 7 kcal a day (about 275, 550 or 825).
- **Floors:** the target is never below 1200 kcal, and never below BMR.
  The pace choices are capped at 0.75 kg a week, and a pace above 1 % of
  body weight a week is refused. When a floor applies, the UI says so.
  (Tasks 4.2 and 5.1 settle whether the sex setting should also move the
  floor.)
- **Macros:**
  - protein: 1.6 g per kg when losing, 1.4 g per kg otherwise;
  - fat: 30 % of the calorie target;
  - carbs: whatever calories remain, at least 0. If protein and fat
    already exceed the target, fat drops to 25 % and the rest follows.

The result is only a suggestion. Every number can be edited, and saving
creates a new history entry that starts today. The screen states that
these are general estimates, not medical advice.

Goals by mode:

- In standalone mode, Settings' "Nutrition plan" section becomes this
  editable goal, with a "Recalculate" button.
- The weight goal and start weight use the existing overrides. The start
  weight defaults to the first local weigh-in. "Use Garmin's goal" is
  hidden.
- The water goal is the override, or 2000 ml.
- In Garmin mode, targets stay Garmin's and read-only (Non-goals).

### D7 — Weight and water in standalone mode

- `WeightLogCoordinator` and `HydrationLogCoordinator` take a
  `deliversToGarmin` flag, set from `DataMode` for each call through
  `AppServices`. When it is `false`:
  - adding commits only to `WeightStore` or `HydrationStore`, with no outbox
    enqueue;
  - deleting or removing deletes the local record, with no Garmin delete
    and no negative correction.
- `AppEnvironment.refreshGarminHealth` and the weight and water drains are
  skipped in standalone mode. `GarminHealthCacheStore` stays empty.
- Display: `WeightHistoryMerge` with no Garmin rows gives the local rows.
  Their "not in Garmin yet" badge is hidden in standalone mode.
  - The water total comes from `HydrationTracking.total(for:on:)` over
    local entries, because standalone mode has no outbox entries.
  - `HydrationDayTotal` stays Garmin mode's rule.
  - The weight ETA uses `WeightGoalProgress` over local rows, unchanged.

### D8 — Active kcal, activities and HealthKit

Standalone mode has no source of activity data:

- **HealthKit is not available on the free Personal Team**
  (`openspec/config.yaml` lists it with App Groups, iCloud and Push). This
  repo has not probed that limit on a device; only Keychain Sharing was
  probed. The plan doesn't depend on HealthKit either way.
- Garmin's `usersummary` and `activitylist` routes need a Garmin account.

The consequences in standalone mode:

- The "Active today" line is hidden, because the reader throws
  `.unavailable` (D3).
- Nothing is estimated from steps or motion. `CMPedometer` would need
  Motion permission and would give steps, not active kcal. It is left out
  to keep the numbers honest.
- Manual activity entry is an open question. If the owner wants it, it
  becomes its own change.

### D9 — Backup and restore

- **Export** (Settings → Data → "Back up now"), in both modes. It builds a
  `BackupBundle`:

  ```
  { schema: "garminfood.backup", version: 1, exportedAt, appVersion, dataMode, stores: {…} }
  ```

  `stores` holds every local JSON store's decoded value: the local food log,
  goals history, custom foods, meal presets, favourites, usage history,
  serving defaults, food cache, weight and hydration entries, day notes,
  every gamification store (XP, achievements, challenges, daily challenges,
  streak history, goal status, lifetime stats), and the non-device
  preferences (fasting schedule, reminders, goal overrides).

  It excludes:
  - Garmin tokens, which stay in the Keychain;
  - the Garmin health cache;
  - outboxes;
  - the offline index;
  - the diagnostics log. That one is copied separately from Diagnostics.

  The export also writes `food-log.csv`: day, meal, time, food, brand,
  amount, unit, kcal, protein, carbs, fat, fibre, sugar. Both files are
  shared through `ShareLink`, to Files, AirDrop or Mail.
- **Import** (Settings → Data → "Restore from backup…") uses
  `.fileImporter` for `.json`.
  1. It checks `schema` and `version`. A newer version is refused with an
     "update the app" message.
  2. It shows a preview of the counts per store.
  3. On confirm, it writes an automatic safety export to
     `Application Support/Backups/pre-restore-<date>.json`.
  4. It replaces every store in the bundle, each store writing atomically.
  5. It reloads the stores in memory.
  It **replaces**, it doesn't merge. Merging two histories is out of scope
  for version 1.
- **Nudge.** In standalone mode, Settings shows "Last backup: N days ago",
  and the Today tab gets a quiet reminder card after 14 days without one.
  No iCloud or free-account backup exists, so losing or wiping the phone
  loses everything since the last export. AltStore's 7-day re-sign
  preserves data. Only deleting the app, or reinstalling through a path
  that re-signs under a different identity, wipes it.

### D10 — Onboarding, hiding Garmin surfaces, switching modes

**Onboarding** (`GarminFood/Onboarding/`, shown when the mode is unset):

1. Welcome.
2. "How do you want to use GarminFood?"
   - **"With my Garmin account"**: runs today's `GarminSignInSheet`, then
     stores `.garminConnected`. "Not now" also stores `.garminConnected`,
     so today's signed-out behaviour and banner apply.
   - **"Just on this phone"**: stores `.standalone`.
3. Standalone only: goal setup (D6), where Skip leaves no target. Then a
   one-screen "Back up regularly" explainer (D9).

**Hidden in standalone mode:**

- `AuthBannerView` and `DeliveryBannerView`;
- Settings → "Garmin account" (replaced by a **Data** section: mode, switch,
  backup, restore);
- the Sync queue row;
- Garmin's read-only Nutrition plan (replaced by D6's editor);
- "Default meal from Garmin's schedule";
- "Use Garmin's goal";
- the custom-food backing picker and "Create in Garmin";
- "Sync to Garmin" for presets;
- "Active today";
- the Garmin social profile. Profile shows an editable local display
  name.

On foreground, standalone mode skips `authState.refresh`,
`drainAndReconcile`, `refreshGarminHealth`, `profile.refresh` and
`backfillUsageMealsIfNeeded`. `BackgroundRefresh` is never scheduled.
`NSCameraUsageDescription` becomes mode-neutral ("…look it up in food
databases").

**Switching** (Settings → Data), always explicit and confirmed:

- **Standalone → Garmin.**
  1. Sign in. The switch only completes after sign-in succeeds.
  2. The dashboard, Trends and goal status then read Garmin.
  3. The local food log **stays on the phone**, is included in backups, and
     shows again if the user switches back. Nothing is uploaded (Non-goals).
  4. Custom foods without a backing food are flagged (D5).
  5. Standalone weight and water entries stay local and are not queued.
     Uploading past weigh-ins could be a later opt-in; it isn't part of
     this change.
  6. The confirmation text says all of this.
- **Garmin → standalone.**
  1. This is refused while a drain is in flight, with "Finishing sync…,
     try again in a moment".
  2. Undelivered food entries are shown with two choices: "Deliver first"
     (only if signed in) or "Keep on this phone". Keeping them converts
     each one into a `LocalLogEntry`, with nutrients taken from
     `FoodCacheStore` (or calories only if the cache lacks them), and
     cancels it in the outbox.
  3. Garmin history is not imported by default. An optional **"Copy my last
     90 days from Garmin"** action reads through the confirmed read route
     `GET /nutrition-service/food/logs/{date}` (2026-09-14) and writes local
     entries. It is read-only toward Garmin.
  4. The Garmin token is kept unless the user also picks "Sign out", so
     switching back is instant.

### D11 — Gamification and trends in standalone mode

- **Existing gamification.** `GamificationEngine.refreshGoalStatus` reads
  through `NutritionLogReading`. The goal-met judgement (`CalorieBand`,
  `metAtLeast`) moves unchanged into a pure `GoalStatusEvaluator`, which
  both modes use. In standalone mode the day log comes from the local
  reader, whose goals come from `LocalGoalStore`, so goal challenges,
  achievements and lifetime goal stats work. A day with no local goal
  records nothing, which is what Garmin mode does with no goals today.
  Streaks, XP and daily challenges already come from `UsageHistory` and
  are unaffected.
- **Planned changes.**
  - `add-gamification-signals`' `DaySignals.availability` gets its day
    totals from `NutritionLogReading`. `hasGarminLog` is renamed or aliased
    to `hasFoodLog`, true for a local day with entries.
  - In standalone mode, `hasActivities` and active kcal are **always
    false**. Rotation and eligibility must therefore never offer a
    challenge, bingo square or boss whose `DataRequirement` is
    `.activities`.
  - Garmin-only features: activity badges in
    `add-sport-and-body-achievements`, bingo `m-refuel` and `h-earned-it`,
    `sig-fuel-and-recover`, `sig-active-on-target`, the active-kcal → km
    journey, and the `active-kcal-day` record. The Progress tab hides these
    in standalone mode rather than showing them as locked forever.
  - Everything food-, water-, weight-, fasting- and note-based works
    locally.
  - If `add-gamification-signals` ships first, task 7.2 adapts its builder.
    If this change ships first, that change's tasks must add the
    `NutritionLogReading` input.
- **Trends.** The macro charts use `calorieSummaryDaily` from the local
  reader. The water trend and note markers are already local.

### D12 — Installing for a second person

The plan gets a doc, `docs/install-second-phone.md`:

- She installs on **her own iPhone**, with **her own Apple ID** in AltStore
  (via AltServer for Windows on the owner's PC) or SideStore (which needs
  no PC after pairing, so the 7-day refresh happens on her phone). She uses
  the same unsigned `.ipa` from CI.
- Free-account limits apply per Apple ID:
  - about **3 active sideloaded apps per device**, AltStore or SideStore
    included;
  - **10 new App IDs per 7 days**. GarminFood uses 2: the app and the
    widget extension.
  - a **7-day re-sign**. If it lapses, the app won't launch until it is
    refreshed, but its data is kept.
- AltStore re-signs under her Personal Team, and by AltStore's documented
  behaviour it suffixes the bundle ID with her team ID. Task 7.5 confirms
  this on her first install. `project.yml` declares no entitlements, App
  Groups or Keychain groups (all removed after the 2026-09-14 spike), so
  nothing needs to change for a second signer. The fixed identifiers
  `com.mlcousek.garminfood`, `.widget` and `BGTaskScheduler` id
  `com.mlcousek.garminfood.refresh` are per-app and can't collide across
  phones.
- Every install is its own sandbox. The two phones share nothing, and each
  chooses its own mode at onboarding.

### D13 — Safety for the existing user; testing

Nothing changes behaviour on the owner's phone:

- The mode classification resolves to `.garminConnected` (D1).
- `GarminClient` gains only a protocol conformance and public DTO inits.
- `LogEntryCoordinator`'s bodies are untouched.
- The routing proxy returns the Garmin implementation.
- Every hidden surface is hidden only when `.standalone`.

Wave 1 ships this seam alone, so any regression shows up before local code
exists.

Every piece of new logic has unit tests in its package. The pattern is the
one in `LogEntryCoordinatorTests`: real stores pointed at temp files, no
mocks of our own stores.

- `DataModeMigrationTests`.
- `LocalFoodLogStoreTests`: commit, edit, delete, month sharding, 
  quarantine, and decoding with unknown keys.
- `LocalLogEntryCoordinatorTests`:
  - nutrient scaling;
  - a custom food uses its own macros;
  - presets;
  - usage and serving-default side effects match the Garmin coordinator's.
- `LocalNutritionReaderTests` (golden tests): `MealDashboard.build` over a
  synthesized log gives the expected totals, goals and entry statuses.
  `CopyMealPlanner` and `GoalStatusEvaluator` work over the same log.
- `GoalCalculatorTests`: reference people and floors.
- `LocalGoalStoreTests`: the goal in effect per day.
- `BackupBundleTests`: a round trip, a newer version refused, and CSV
  escaping.
- `CustomFoodDraft` decodes old files that have a backing food, and new
  ones that don't.
- `SearchOrigin.isDirectlyLoggable(in:)`.
- GarminKit: the DTO public inits build values equal to the decoded fixtures.

UI stays thin and is checked on a device each wave. Until onboarding exists
(wave 5), a hidden Diagnostics toggle, "Force standalone mode (testing)",
lets each wave be checked on a device.

## Fallbacks for private-API dependencies

Standalone mode adds **no** private-API dependency. It is also the fallback
for the whole Garmin integration: if Garmin removes or blocks the private
nutrition routes, the owner can switch to standalone mode and keep logging.
He loses only Garmin-side visibility and active kcal. The optional "Copy my
last 90 days from Garmin" action (D10) depends on
`GET /nutrition-service/food/logs/{date}` (confirmed 2026-09-14). If that
route breaks, the action shows the error and copies nothing, and the switch
still completes.

## Risks / Trade-offs

- **Local data is shaped like Garmin's DTOs** (D3). Local data is tied to
  Garmin's read models. The shape is plain and a later neutral model can
  replace it, but it's a real coupling, taken on purpose so Garmin mode
  stays untouched.
- **Data loss without backups.** There is no cloud copy. This is mitigated
  by D9's export, the nudge and the safety backup on restore, and stated
  plainly in onboarding.
- **OFF data quality.** Standalone users rely on community data with no
  Garmin/FatSecret cross-check. Missing calories block logging, as
  `MatchConfirmationView` already does for creates. Other missing macros
  log as unknown, and totals treat them as 0 with a "some values missing"
  marker.
- **Divergent mode code paths.** Each guard is one `if mode == .standalone`
  at a view or composition-root boundary, never deep in shared logic. The
  domain differences live behind the two protocols.
- **Switching back and forth** leaves a local log that Garmin mode doesn't
  show. This is by design and stated in the confirmation. Backfill is a
  separate change.

## Migration Plan

1. Wave 1 ships the seams with no behaviour change. The owner uses that
   build for a few days.
2. Waves 2–4 build standalone mode behind the testing toggle.
3. Wave 5 adds onboarding. From then on a fresh install can choose
   standalone mode.
4. Wave 6 adds backup, and is required before the fiancée relies on the
   app.
5. Wave 7 covers gamification gating, the install doc, and her first
   install.

Rollback: if a wave misbehaves, revert its PR. Stores written by later
waves (`FoodLog/*.json`, `local-goals.json`) are new files that older builds
ignore. An older build has no standalone mode, so a standalone user
shouldn't downgrade. The install doc says so.

## Open Questions

Carried into tasks.md group 0 for the owner:

1. Should her data ever leave the phone other than by manual export? For
   example a shared-folder backup, or never.
2. Manual activity entry: yes or no, and would it ever change her target?
   Owner's 2026-09-23 decision: no eat-back.
3. Export format: are JSON plus CSV enough? Replace-only restore: is that
   acceptable?
4. When someone later connects Garmin, should standalone history ever be
   uploaded? That would need the quickAdd write contract documented first.
5. Goal calculator: 1200 kcal floor for everyone, or sex-specific (1200 or
   1500)? Protein g/kg defaults? Per-meal targets, or day targets only?
6. App name for her install: keep "GarminFood" or a neutral display name?
   (UI language is settled: Czech via `add-localization`.)
7. Does she prefer SideStore (no weekly PC dependence) over AltStore?
8. Owner side: is "Copy my last 90 days from Garmin" worth building now, or
   later?
