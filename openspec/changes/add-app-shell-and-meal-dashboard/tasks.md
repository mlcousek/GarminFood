## 1. Foundations that the new screens depend on

- [x] 1.1 Give the app one process-wide set of local stores (`Outbox`, `UsageHistoryStore`, and the rest), shared by `AppEnvironment` and the in-app intents (`QuickPickLoggingIntents.performLog`, `LogNamedFoodIntent`). Today each intent opens its own copy of the same JSON files. Each copy reads its file only once, so an entry logged from a Control while the app is running can be overwritten by the app's next save (found by the 2026-09-16 task audit).
- [x] 1.2 Record the logged nutrition date on each usage event (optional field, so older files still decode). Streaks, XP and goal status then key on the same date the entry was sent to Garmin, instead of mixing a midnight date and a 04:00 date (`add-gamification` 23.1; goal-status lookup mismatch at `GamificationEngine.swift:113` vs `:150`).
- [x] 1.3 Move `Theme` into `ios/Shared` so the widget extension uses the same tokens instead of hand-copied colours (`add-gamification` 26.1). Add `@ScaledMetric` for the fixed sizes and a `Haptics` helper that honours preferences (design D11).
- [x] 1.4 Add `AppPreferences` (`UserDefaults`-backed; haptics, celebrations, Garmin meal windows, Czech-only search) (design D9).

## 2. GarminKit reads

- [x] 2.1 `GarminClient.nutritionSettings(date:)` for `GET /nutrition-service/settings/{date}` (probed 200, 2026-09-16; shape recorded in design.md) and the `NutritionSettings` model.
- [x] 2.2 `GarminClient.socialProfile()` for `GET /userprofile-service/socialProfile` (probed 200, 2026-09-16) and a `SocialProfile` model holding only the fields shown.
- [x] 2.3 Record both routes in `docs/garmin-routes.json`, with status 200 and the date observed.

## 3. Dashboard domain (FoodLogCore, unit-tested)

- [x] 3.1 `MacroProgress` (consumed / goal / fraction / state), using the same ±10% band as `TodaySummary.GoalState`.
- [x] 3.2 `MealDashboard.build(...)`: ordered sections, adjusted-over-base goals, an empty meal counted as zero, pending entries joined to cached foods, a delivered-but-unreconciled entry shown once, and day totals.
- [x] 3.3 `MealWindowDefaulting`: meal from Garmin windows, SNACKS outside every window, and fallback to `MealTypeDefaulting`.
- [x] 3.4 Unit tests for 3.1–3.3, including every scenario in `specs/meal-dashboard`.

## 4. Gamification additions (unit-tested)

- [x] 4.1 `StreakHistory`: logged days, longest streak under the grace rule, and a recent-weeks calendar with logged/missed/grace marks.
- [x] 4.2 `ChallengeHistoryStore`: completed challenges (template, date, XP), capped and persisted. `GamificationEngine` writes to it when a challenge completes.
- [x] 4.3 Read-only accessors on `GamificationEngine`: catalog, active window end, goal history, challenge history, streak history, total logs.
- [x] 4.4 Tests for `StreakHistory` and `ChallengeHistoryStore`, plus the missing challenge-template tests (`add-gamification` 25.4: calorie-control, carb-cutback, explorer, dinner-discipline, and the incomplete cases for full-plate and triple-threat).

## 5. App shell

- [x] 5.1 `AppShell` `TabView` (Today / Progress / Profile), with each tab keeping its own navigation stack.
- [x] 5.2 Route handling at the shell: `onOpenURL` for `garminfood://open`, and `AppNavigationBridge` consumed on activation to select Today and present the scanner.
- [x] 5.3 Keep the auth and delivery banners visible across tabs.

## 6. Today

- [x] 6.1 A `DayLogLoader` that replaces `TodaySummaryLoader`: loads any date and keeps the full `DailyFoodLog` plus the meal windows, and the last good data per date on failure.
- [x] 6.2 A day header with a `DaySwitcher` and totals against targets (a calorie ring and macro bars).
- [x] 6.3 Meal sections in Garmin order: consumed/suggested kcal and macros, the food list, syncing entries, and an add action that pre-selects the meal and date.
- [x] 6.4 A compact streak and level strip linking to Progress, plus the existing quick-pick shelf.
- [x] 6.5 `MealDetailView`: the full nutrient breakdown, the food list, add to this meal, and delete with confirmation (Garmin delete route or local queue removal), with a visible error on failure.
- [x] 6.6 `LogEntryConfirmView`: optional initial meal and date, meals listed in dashboard order, and the default meal from Garmin windows when the preference is on.
- [x] 6.7 Refresh the day after a delivery or delete, and when the date changes.

## 7. Progress

- [x] 7.1 `ProgressHomeView`: level, streak and challenge summary cards, plus goal history.
- [x] 7.2 `LevelDetailView`: progress, the next levels' thresholds, and how XP is earned.
- [x] 7.3 `StreakDetailView`: current and longest streak, and the calendar grid with grace days.
- [x] 7.4 `ChallengesView`: the active challenge with time left, all challenges, and completed ones.
- [x] 7.5 Gate every repeating or celebratory animation on Reduce Motion and the celebrations preference, including the existing `symbolEffect(.bounce)` in `MomentOverlay` and `.pulse` in the streak flame (`add-gamification` 26.3). Stop the moment haptic from firing again on dismiss.

## 8. Profile and settings

- [x] 8.1 `ProfileView`: the Garmin name and avatar with a fallback, and stat tiles.
- [x] 8.2 `SettingsView` sections: Garmin account (status, sign in, sign out with confirmation), nutrition goals and meal windows (read-only), sync queue, preferences, about.
- [x] 8.3 `SyncQueueView`: pending and failed entries with meal/date/state/error, retry, delete with confirmation, and sync now.
- [x] 8.4 Background delivery: `BGTaskSchedulerPermittedIdentifiers` (`com.mlcousek.garminfood.refresh`) and `UIBackgroundModes: fetch` in `project.yml`, a `.backgroundTask(.appRefresh)` handler that drains and reschedules, and scheduling on entering the background with queued entries (`add-garmin-auth-and-sync` 9.5).

## 9. Carried code work from other changes

- [x] 9.1 Bound the Control/Siri inline delivery to about 2 s and surface an auth failure instead of discarding it (`add-garmin-auth-and-sync` 9.6).
- [x] 9.2 Control action hint (`add-glanceable-surfaces` 17.3); CI compile decides where the modifier attaches. A dynamic "Logged N kcal" status is not possible without shared data (glanceable D2), so record that instead of faking it.
- [x] 9.3 Donate app- and Control-initiated logs too, and remove the donation when the user deletes that entry (`add-glanceable-surfaces` 20.2).
- [x] 9.4 `probe-garmin-nutrition.mjs`: always print 400 bodies, and report how many routes remained unverified when a 429 stops the run (`establish-garmin-nutrition-contract` 3.3).

## 10. Device verification checklist (owner, on iPhone)

- [ ] 10.1 Tabs, day switching, meal sections and meal detail render correctly in light/dark and at the largest Dynamic Type size; VoiceOver reads every control.
- [ ] 10.2 Per-meal targets match Garmin Connect's food page for the same day.
- [ ] 10.3 Add from a meal pre-selects it; the default meal follows the Garmin windows.
- [ ] 10.4 Delete a synced entry (the first real use of the delete route) and a queued entry; record the observed status in `docs/garmin-routes.json`.
- [ ] 10.5 Sign out and sign in again from Settings; queued entries survive.
- [ ] 10.6 A background refresh delivers a queued entry with the app closed, or the result is recorded if iOS never grants time to a sideloaded app.
- [ ] 10.7 The barcode Control opens the scanner from any tab; the widget opens Today.
- [ ] 10.8 Airplane-mode logging commits instantly (from archived `add-food-log-core` 16.3).
- [ ] 10.9 Reduce Motion: no pulsing or bouncing; celebrations off: no overlay animation.
- [ ] 10.10 Carried device checks: `add-garmin-auth-and-sync` 6.5, 10.4; `add-glanceable-surfaces` 17.2, 18.2, 19.5, 20.3, 21.1–21.3; `add-gamification` 26.2.
