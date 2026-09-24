## Why

The owner, in his own words: *"my fiance likes the app as well but doesn't
have garmin to log it there, so map please how dependent the app is on garmin
and if it can work independently as well"*.

The map (`docs/garmin-dependency-map.md`, 2026-09-24) gives a plain answer:
**no**. The app opens without an account, but no food can be logged. Every
logging path ends in a Garmin `foodId`:

- Open Food Facts and offline-Czech results must first be matched to a
  Garmin food or created in Garmin.
- A custom food must name a "closest Garmin food" before it can be saved.
- Barcode misses lead to one of those two flows.

Beyond that, the food log itself exists only in Garmin (the outbox is a
queue, and `UsageHistory` is capped at 500 events with no nutrients). Every
calorie and macro target is Garmin's `dailyNutritionGoals`. A user without
Garmin also gets a permanent "Not connected to Garmin" banner and a sync
queue that never empties.

The rest of the app is already local-first: weight, water, notes, fasting,
streaks, XP, reminders and diagnostics. What is missing is a **local system
of record for food logs**, **local goals**, **food logging that doesn't need
a Garmin identity**, and a **per-install choice of data mode**.

## What Changes

- **Data mode per install.** The modes are "Garmin-connected" (today's
  behaviour) and "On this phone only" (standalone). The mode is chosen at a
  new first-launch onboarding and can be switched later in Settings.
  Existing installs are classified silently as Garmin-connected, so the
  owner's phone never sees onboarding and nothing changes for him.
- **Local food log (standalone system of record).** Each entry is a durable,
  month-sharded JSON store (`LocalFoodLogStore`) with a full nutrient
  snapshot and a food reference that isn't tied to Garmin. It is committed
  locally with no outbox, drain or sync state.
- **Two seams, so Garmin mode's code paths stay as they are:**
  - a read protocol, `NutritionLogReading` (day log, meals, calorie
    summary, daily summary). `GarminClient` conforms by extension, and
    `LocalNutritionReader` produces the same `DailyFoodLog`-shaped values
    from the local store;
  - a write protocol, `FoodLogging`, extracted from `LogEntryCoordinator`'s
    public API. It has a new `LocalLogEntryCoordinator`, and a
    mode-routing proxy chooses between the two.
  Through these seams, the dashboard, meal detail, edit, delete, duplicate,
  copy meal, Trends macro charts and goal status all work from the local
  store in standalone mode.
- **Food catalog without Garmin.** Search uses the user's own foods, the
  offline Czech index and Open Food Facts. OFF and Czech results can be
  logged directly (no Garmin match). A custom food's Garmin "backing food"
  becomes optional (decode-safe) and is hidden in standalone mode. Barcodes
  resolve through the offline index plus an online OFF product lookup
  (probed before use). Meal presets, quick picks, Siri "log X" and the
  quick-pick Controls all go through the same mode-aware logging.
- **Local nutrition goals.** A goal history keyed by effective date. It has
  an editable calorie target and protein/carbs/fat targets, plus a
  calculator (Mifflin–St Jeor × activity level ± goal pace, safe floors),
  used during onboarding and from Settings. The weight goal, start weight
  and water goal reuse the existing local overrides.
- **Weight and water stay on the phone** in standalone mode. There are no
  outbox deliveries, no Garmin health refresh and no "not in Garmin yet"
  state.
- **Garmin-only surfaces are hidden** in standalone mode: the auth and
  delivery banners, sync queue, sign-in, the read-only Garmin nutrition
  plan, "Use Garmin's goal", "Default meal from Garmin's schedule", "Sync to
  Garmin" for presets, the custom-food backing picker, the "Active today"
  line and background delivery.
- **Backup and restore.** A versioned JSON export of every local store,
  plus a CSV of the food log, shared through the share sheet. Import can
  replace all local data from a backup, and an automatic safety backup is
  taken first. Both modes get this, because iCloud isn't available on the
  free Personal Team.
- **Gamification in standalone mode** reads goal status from local goals
  and the local log. Activity- and active-kcal-based features (planned
  `add-sport-and-body-achievements` and parts of
  `add-journeys-and-records`, `add-weekly-bingo` and
  `add-gamification-signals`) are marked unavailable instead of offered.
- **Install guide for a second person:** her own iPhone and Apple ID, her
  own AltStore or SideStore, the same CI-built `.ipa`, and no shared data.

## Capabilities

### New Capabilities

- `data-mode` - per-install Garmin-connected vs standalone mode:
  onboarding, classification of existing installs, switching, hiding
  Garmin-only surfaces, local-only weight and water, and gamification
  availability.
- `local-food-log` - the standalone system of record for food entries and
  everything that reads it (dashboard, edit/delete/duplicate/copy, trends,
  goal status).
- `standalone-food-catalog` - searching, scanning, creating and logging
  foods with no Garmin food identity.
- `local-nutrition-goals` - local calorie and macro targets with history,
  and the goal calculator.
- `data-backup` - export and import of all local data.

### Modified Capabilities

None. Existing specs (`food-log-entry`, `food-catalog`,
`garmin-food-matching`, `challenges`, `streaks`, `levels`) keep their
behaviour in Garmin-connected mode. Standalone behaviour is specified in
the new capabilities above.

## Non-goals

- **Uploading or backfilling standalone history into Garmin** when a user
  later connects Garmin. The only route that could carry foods without a
  Garmin `foodId` is `PUT /nutrition-service/food/logs/quickAdd`, which is
  "documented, not exercised" in `docs/garmin-routes.json`. Per
  `openspec/config.yaml` no write task may exist before that contract is
  documented. This is left to a future `backfill-local-log-to-garmin`
  change.
- **Local goal overrides for Garmin-connected users.** Garmin mode keeps
  Garmin's targets read-only, as `add-app-shell-and-meal-dashboard`
  decided.
- **HealthKit, iCloud, App Groups or any cloud sync.** None are available
  on the free Personal Team (`openspec/config.yaml`).
- **Manual activity entry.** This is an open question for the owner. If he
  wants it, it becomes its own change feeding
  `add-gamification-signals`' `DaySignals.activities`.
- **Multiple people on one phone, or shared data between two phones.**
  Each install serves one person. The existing "one person, one Garmin
  account" rule (`add-garmin-auth-and-sync`) still holds within Garmin
  mode.
- **Building the planned gamification features.** Those are owned by the
  eight gamification changes. This change only fixes how they must behave
  in standalone mode (availability gating).
- **Renaming the app or localising it into Czech.** Open question.

## Impact

Affected code:

- `GarminKit`: a new `NutritionLogReading` protocol, a `GarminClient`
  conformance, and additive `public init`s on the read DTOs (`DailyFoodLog`,
  `MealDetail`, `Meal`, `LoggedFood`, `DailyNutritionContent`,
  `NutritionGoals`, calorie-summary types). No request or response
  behaviour changes.
- `FoodLogCore`: `DataMode` plus migration, `LocalFoodLogStore`,
  `LocalLogEntryCoordinator`, the `FoodLogging` protocol,
  `LocalNutritionReader`, `LocalGoalStore`, `GoalCalculator`,
  `GoalStatusEvaluator`, `BackupBundle` and CSV writer, an optional backing
  food on `CustomFoodDraft`, mode-aware loggable origins, and
  `OpenFoodFactsClient.product(barcode:)`.
- `Gamification`: none directly. Goal status arrives through the existing
  `DailyGoalStatus`.
- App: `AppServices`, `AppEnvironment`, `DayLogLoader`, `MacroTrendLoader`,
  `GamificationEngine`, `ContentView`, a new `Onboarding/` folder,
  `Settings`/`Goals`/`Profile` views, `FoodCatalogView`,
  `CustomFoodEditorView`, `MealPresetEditorView`, `BarcodeScanScreen`, the
  weight and water coordinators and loaders, `BackgroundRefresh`, the Siri
  and Control intents, and new `Backup/` views.
- `project.yml`: a neutral `NSCameraUsageDescription` only.
- Docs: `docs/install-second-phone.md`.

**Depends on**: nothing unshipped. Built on `origin/main` @ `b117adf`
(`sync-weight-hydration-with-garmin`, `add-log-entry-editing`,
`rebuild-food-search`, `add-offline-czech-food-index` and
`fix-silent-store-wipe` all shipped).

**Coordinates with**: `add-gamification-signals` (its `DaySignals` builder
should read day totals through `NutritionLogReading`, so standalone days
count as having a full food log). Whichever change ships second adapts to
the other; see design D11.

**Unblocks**: the fiancée using the app on her own iPhone; a future
`backfill-local-log-to-garmin`; a future `add-manual-activity`. It also
gives the owner a working fallback if Garmin's private API disappears
altogether.
