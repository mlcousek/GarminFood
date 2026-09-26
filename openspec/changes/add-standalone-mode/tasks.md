Every task ends with CI green (`swift test` per touched package, app +
widget `xcodebuild`, the `localization` job). Every wave is its own branch
and PR (`mlcousek/add-standalone-mode-wN`) and ends with an on-device check.
All new user-facing text is localizable and translated into Czech from day
one (CLAUDE.md "Localization"), because the fiancée uses the app in Czech.
Relative size per wave: S / M / L.

## 0. Owner decisions (before wave 2)

No owner answer arrived before waves 4–7 were built (2026-09-25), so each
question below takes the design's proposed default. Each is **defaulted,
owner may override** — a later answer becomes its own small follow-up.

- [x] 0.1 Her data leaving the phone: manual export only, or also a shared-folder backup? (design Open Question 1) — *Defaulted, owner may override:* manual export only (Settings → Data, moved to `add-data-safety`); no automatic shared-folder backup.
- [x] 0.2 Manual activity entry: yes/no (default: no; separate change if yes). — *Defaulted, owner may override:* no; standalone has no activity data and no eat-back (owner's 2026-09-23 decision).
- [x] 0.3 Backup: JSON + CSV and replace-only restore acceptable? — *Defaulted, owner may override:* yes, JSON + CSV and replace-only restore (built in `add-data-safety`).
- [x] 0.4 Goal calculator: 1200 kcal floor for everyone or sex-specific; protein g/kg defaults; day targets only or per-meal too. — *Defaulted, owner may override:* one 1200 kcal floor for everyone (plus never below BMR); protein 1.6 g/kg when losing, 1.4 g/kg otherwise; day targets only (no per-meal split in the UI; `mealSplit` stays in the stored shape for later).
- [x] 0.5 Display name for her install ("GarminFood" or a neutral name like "GF"); language is Czech via add-localization. — *Defaulted, owner may override:* keep "GarminFood" (no second bundle display name); the Profile header shows her own local display name in standalone mode.
- [x] 0.6 AltStore or SideStore for her phone. — *Defaulted, owner may override:* the install guide documents both, recommending SideStore (no weekly PC dependence), AltStore as the fallback the owner already runs.
- [x] 0.7 Build "Copy my last 90 days from Garmin" now or later. — *Defaulted, owner may override:* later (task 5.5 skipped).

## 1. Wave 1 — Seams, zero behaviour change (M)

- [x] 1.1 `DataMode` + `DataModeMigration.decide(storedMode:hasGarminToken:hasLocalHistory:)` in FoodLogCore; stored via `AppPreferences` (`dataMode.v1`). Tests: `DataModeMigrationTests` (token → Garmin; history → Garmin; neither → unset).
- [x] 1.2 GarminKit: `NutritionLogReading` protocol; `extension GarminClient: NutritionLogReading {}`; additive `public init` on `DailyFoodLog`, `MealDetail`, `Meal`, `LoggedFood`, `LoggedNutritionContent`, `FoodMetaData`, `DailyNutritionContent`, `NutritionGoals`, calorie-summary DTOs. Tests: inits build values equal to decoded fixtures.
- [x] 1.3 Consumers hold `any NutritionLogReading`: `DayLogLoader`, `MacroTrendLoader`, `GamificationEngine`, `AppEnvironment.copyMealPlan` (same `GarminClient` instance in Garmin mode).
- [x] 1.4 `FoodLogging` protocol (FoodLogCore) = `LogEntryCoordinator`'s public API + `deleteCommitted(logId:date:)` (moved from `DayLogLoader.delete`'s synced branch); `LogEntryCoordinator` conforms; `ModeRoutingFoodLogging` in `AppServices` (always Garmin until wave 2).
- [x] 1.5 Hidden Diagnostics toggle "Force standalone mode (testing)" (English only; developer surface).
- [ ] 1.6 On-device: the owner's phone behaves exactly as before (log, edit, delete, copy meal, Trends, goals).

## 2. Wave 2 — Local food log (L)

- [x] 2.1 `LocalLogEntry` + `LocalFoodLogStore` (month-sharded JSON, unreadable-file contract, atomic writes). Tests: commit/edit/delete, sharding across months, quarantine, unknown-key decode.
- [x] 2.2 `LocalLogEntryCoordinator: FoodLogging` (nutrient snapshot = serving × quantity; custom foods use their own macros; presets; edit rescales; move; duplicate; copyMeal; deletes; usage/serving-default/food-cache side effects identical to Garmin's). Tests.
- [x] 2.3 `LocalNutritionReader: NutritionLogReading` (day log with meal details and sums, goals from `LocalGoalStore` once wave 4 lands, `mealsForDate` default meals, `calorieSummaryDaily`, `dailyUserSummary` throws `.unavailable`). Golden tests through `MealDashboard.build` and `CopyMealPlanner`.
- [x] 2.4 `GoalStatusEvaluator` (pure): move the goal-met judgement out of `GamificationEngine`; both modes use it. Tests (same results as before for Garmin logs).
- [x] 2.5 Routing: `ModeRoutingFoodLogging` and the reader choose the local implementation when standalone.
- [ ] 2.6 On-device (testing toggle on): log, edit, move, duplicate, copy, delete offline; totals and Trends correct.

## 3. Wave 3 — Food catalog without Garmin (M)

- [x] 3.1 `FoodSearchEngine.standard(garmin:)` accepts nil; standalone gets Local + offline index + OFF.
- [x] 3.2 `SearchOrigin.isDirectlyLoggable(in:)`; OFF/offline results go to the serving picker in standalone; calories required, other missing macros shown as "some values missing". Tests.
- [x] 3.3 `CustomFoodDraft` backing food optional (decode-safe); editor hides the Garmin section in standalone; Garmin mode asks for a match for backing-less foods. Tests: old files decode unchanged, new ones without backing.
- [x] 3.4 Meal presets with any origin; "Sync to Garmin" hidden in standalone.
- [x] 3.5 Probe (read-only, no Garmin) `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`; record the status and payload shape in `docs/`; then `OpenFoodFactsClient.product(barcode:)` and the standalone barcode chain (offline index → OFF product → custom-food editor with the code). Tests.
- [x] 3.6 Siri "log X" (`[.local, .offlineIndex]`) and quick-pick intent/Controls log through `FoodLogging`; no `briefDelivery` in standalone.
- [x] 3.7 Czech strings for every new/changed screen text; `node tools/check-localizations.mjs` passes.
- [ ] 3.8 On-device: search "tvaroh", scan a Czech barcode, create "Babiččiny buchty", log via Siri — all offline-capable, no Garmin screens.

## 4. Wave 4 — Local goals, weight and water (M)

- [x] 4.1 `LocalGoalStore` (history by `effectiveFrom`). Tests: goal in effect per day, editing keeps history.
- [x] 4.2 `GoalCalculator` (Mifflin-St Jeor × activity ± pace; floors 1200 kcal / BMR; pace cap 0.75 kg/wk and 1 % body weight; macros). Tests with reference people and floors.
- [x] 4.3 Settings "Nutrition plan" becomes the editable local goal with "Recalculate" in standalone; disclaimer text; Czech strings.
- [x] 4.4 `WeightLogCoordinator`/`HydrationLogCoordinator` `deliversToGarmin` flag from `DataMode`; skip `refreshGarminHealth` and the weight/water drains in standalone; hide "not in Garmin yet" badges; local water total. Tests.
- [ ] 4.5 On-device: set goals with the calculator, edit them, log weight and water; Today ring and water card correct.

## 5. Wave 5 — Onboarding, hidden surfaces, switching (L)

- [ ] 5.1 `Onboarding/` flow (welcome → mode choice → standalone goal setup (skippable) → backup explainer); shown only when the mode is unset. Czech strings.
- [ ] 5.2 Hide Garmin-only surfaces in standalone (banners, sync queue row, Garmin account section → "Data" section, Garmin nutrition plan, "Use Garmin's goal", "Default meal from Garmin's schedule", backing picker, "Active today", Garmin profile → local display name).
- [ ] 5.3 Foreground/background in standalone skip every Garmin call; `BackgroundRefresh` not scheduled. Test the planning function if extracted.
- [ ] 5.4 Switching (Settings → Data): standalone → Garmin after successful sign-in (local log kept, backing-less custom foods flagged); Garmin → standalone refused during a drain, undelivered entries "Deliver first" / "Keep on this phone" (converted to local entries via `FoodCacheStore`). Tests for the conversion.
- [ ] 5.5 Optional (per 0.7): "Copy my last 90 days from Garmin" via the confirmed read route, read-only. — *Skipped: 0.7 defaulted to "later".*
- [ ] 5.6 Mode-neutral `NSCameraUsageDescription` (en + cs via InfoPlist catalog).
- [ ] 5.7 On-device: fresh install → choose "Just on this phone" in Czech → log a day with zero Garmin calls; the owner's phone skips onboarding.

## 6. Wave 6 — Backup and restore (M) — required before the fiancée relies on the app

Moved to the `add-data-safety` change (PR #87), which builds Settings → Data
with backup and restore for both modes. Tracked there, not here.

- [ ] 6.1 `BackupBundle` (schema/version, every local store, non-device preferences; excludes tokens, health cache, outboxes, offline index, diagnostics) + `food-log.csv` writer. Tests: round trip, CSV escaping, no secrets.
- [ ] 6.2 Settings → Data: "Back up now" (ShareLink), "Restore from backup…" (fileImporter → version check → preview → safety backup → replace → reload). Tests for version refusal and replace.
- [ ] 6.3 "Last backup: N days ago" + Today reminder card after 14 days (dismiss for 14 days). Czech strings.
- [ ] 6.4 On-device: back up, reinstall, restore — food log, goals, custom foods, weight, water and progress return.

## 7. Wave 7 — Gamification gating, install guide, her first install (S)

- [ ] 7.1 Standalone availability: activity/active-kcal challenges, bingo squares, bosses, journeys and records never offered; Garmin-only achievements hidden (not locked). Coordinate with `add-gamification-signals` (`DaySignals` reads totals via `NutritionLogReading`; `hasFoodLog` true for local days). Tests.
- [ ] 7.2 Adapt whichever of this change and `add-gamification-signals` ships second (design D11).
- [ ] 7.3 `docs/install-second-phone.md` (her iPhone, her Apple ID, AltStore/SideStore, 7-day re-sign, 3-app limit, 10 App IDs/week, bundle-ID suffixing, no shared data, don't downgrade), in English and Czech.
- [ ] 7.4 CI green on every wave PR.
- [ ] 7.5 Her first install on her iPhone: onboarding in Czech, standalone, a first logged day, a backup; record the bundle-ID behaviour and any surprises.
