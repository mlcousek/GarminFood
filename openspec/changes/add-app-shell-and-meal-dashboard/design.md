## Context

The app has a working pipeline (sign-in → read day → confirm → outbox → PUT → reconcile). Every step was confirmed on a real device on 2026-09-16. The UI on top of it is one `NavigationStack` rooted at `HomeView`:

- a single calorie hero
- a one-line level/challenge row
- a quick-pick shelf
- a push to the catalog

A survey of the code (2026-09-16) found these gaps:

- `TodaySummaryLoader` discards `mealDetails` and every macro goal.
- There is no `TabView`, and no settings or profile UI. `TokenProvider.signOut()` exists but nothing calls it.
- No `onOpenURL` handler exists, although widget comments claim one.
- The barcode Control's `AppNavigationBridge` route is consumed only inside `FoodCatalogView`, so tapping the Control lands on Home and does nothing until the user opens the catalog.
- `LogEntryConfirmView` has no initial-meal parameter and lists meals in `MealType.allCases` order: Breakfast, Lunch, Snacks, Dinner.
- The default meal comes from a fixed hour table, not from the account's meal windows.
- No `UserDefaults` is used anywhere, so no preference survives a relaunch.

### Probed evidence (read-only, owner's account, 2026-09-16)

| Route | Status | What it gives this change |
|---|---|---|
| `GET /nutrition-service/food/logs/{date}` | 200 | `mealDetails[]` each carry `mealNutritionGoals` {calories, carbs, fat, protein and their `adjusted*` variants} and `mealNutritionContent` {calories, macros, and for meals with food: fiber, sugar, saturated/mono/polyunsaturated fat, cholesterol, sodium, potassium, vitamins A/C, calcium, iron}. Goal split on this account: 25 / 30 / 35 / 10 % (breakfast / lunch / dinner / snacks). A meal with nothing logged returns an **empty** content object. |
| `GET /nutrition-service/meals/{date}` | 200 | per-date `mealId`, `mealName`, and `startTime`/`endTime` for BREAKFAST 04:00–07:00, LUNCH 10:00–12:00, DINNER 14:00–17:00; SNACKS has no window |
| `GET /nutrition-service/settings/{date}` | 200 | `calorieGoal`, `macroGoals {carbs, fat, protein}`, `weightChangeType`, `weightChangeRate`, `targetWeightGoal`, `startingWeight`, `targetDate`, `activeDailyCalories`, `autoCalorieAdjustment`, `dailyTimelineStartTime/EndTime`, `nutritionStatus` |
| `GET /userprofile-service/socialProfile` | 200 | `displayName`, `fullName`, `profileImageUrlSmall/Medium/Large`, `location`, and Garmin's own `userLevel`/`userPoint` |
| `DELETE /nutrition-service/food/logs/{date}` body `{logIds}` | not exercised by this project | contract from garmin_mcp `delete_food_log`, which covers it with live tests |

## Goals / Non-Goals

**Goals:**
- A shell that makes every current and future screen one tap away.
- A Today screen as informative as Garmin's food page.
- Progress, profile and settings screens that make the gamification layer and the account feel like a product, not internals.

**Non-Goals:** see proposal.md.

## Decisions

### D1. Three tabs: Today, Progress, Profile; Settings is pushed from Profile

- Three tabs keep the thumb path short and match the three questions the app answers: what did I eat, how am I doing, who am I and how is this set up.
- Settings is a push from Profile, not a fourth tab, because it is visited rarely.
- The shell owns deep-link and Control routing (`onOpenURL`, `AppNavigationBridge.consume()` on activation), and selects the Today tab before presenting the scanner. The catalog keeps consuming the bridge too, as a fallback.

### D2. The dashboard is a pure value built in FoodLogCore

`MealDashboard.build(log:pending:foodNames:mealOrder:)` turns a `DailyFoodLog` plus the outbox's not-yet-delivered entries into ordered `MealSection`s:
- consumed and suggested calories/macros
- confirmed entries
- pending entries

It lives in FoodLogCore, which already depends on GarminKit, so every rule is unit-tested without a device:
- meal order
- the empty-content case
- pending entries showing up in their meal
- adjusted-vs-base goals

Details:
- **Goals:** use `adjusted*` values when present, else the base values. Garmin's own page shows the adjusted target when auto-adjustment is on.
- **Meal order:** `Meal.displayOrder` when present, else Breakfast, Lunch, Dinner, Snacks.
- **Pending entries** have no name or calories in the outbox, so they are joined against `FoodCacheStore` by `foodId`. If the food isn't cached, they show as "Syncing…" without calories rather than being hidden.
- **Confirmed entries** use `LoggedFood.logId` as identity. A pending entry that also appears in the log (delivered but not yet reconciled) is shown once.

**Fallback if the log route breaks:** sections still render from the meals route plus pending entries, with no confirmed data and a stale marker, so the day never blanks.

### D3. Macro progress has its own small model, matching `TodaySummary.GoalState`

`MacroProgress(consumed:goal:)` exposes `fraction` (clamped to 0...1 for bars) and `state` (under / onTarget / over / noGoal). It reuses the same ±10% band as `TodaySummary`, so a meal row and the day hero never disagree about "on target".

### D4. Default meal comes from Garmin's windows

`MealWindowDefaulting.mealType(at:windows:)` picks the meal whose window contains the time. Outside every window it returns SNACKS, which mirrors how garmin_mcp maps a time to a meal.

- The windows come from the dashboard's already-loaded day, so there is no extra request at confirm time.
- If no windows are loaded yet, it falls back to the existing `MealTypeDefaulting` hour table.
- Opening the catalog from a meal section pre-selects that meal, overriding any default.

### D5. Deleting an entry

- **Confirmed entry:** the Garmin delete route, then a day reload.
- **Pending entry:** `Outbox.delete(id:)`. It never reached Garmin, so there is nothing remote to delete.

Both ask for confirmation.

The delete route is modelled on garmin_mcp and has **not been exercised by this project**. So:
- The first delete of a confirmed entry is a real-device check (task in section 9).
- A failure keeps the entry visible and says why, reusing `GarminErrorPresentation`'s approach.

**Fallback:** "Delete in Garmin Connect" guidance in the error message.

### D6. Day navigation reads any date; logging for a past date stays in the confirm screen

- The Today tab gets previous/next day controls, and "Today" snaps back.
- Viewing is read-only apart from delete.
- Adding from a past day's meal section pre-fills that date in the confirm screen, which already supports an editable date.

### D7. Progress data needs two small additions to Gamification, nothing else

Everything else already exists (`LevelCurve`, `XPAward`, `StreakEngine`, `ChallengeCatalog`, `ChallengeEngine`, `GoalStatusStore`). The two additions are:

- `StreakHistory`: pure. From event timestamps it computes:
  - the set of nutrition days logged
  - the longest streak, under the same grace rule `StreakEngine` uses
  - a calendar grid for the last N weeks

  Tested against the same edge cases as `StreakEngine`.
- `ChallengeHistoryStore`: an actor, JSON file like the other stores. It records `(templateId, completedAt, xpAwarded)` when `GamificationEngine` completes a challenge, and is capped. Completed challenges could not be listed before, because `ChallengeStore` keeps only private recent ids.

`GamificationEngine` exposes read-only accessors (catalog, goal history, challenge window end, history) instead of making its stores public.

### D8. Profile and settings data

- **Profile** reads `socialProfile` once per launch and caches the last good value in memory. On failure it shows local data only: level, streak, stats.
- **Avatar:** `AsyncImage` of `profileImageUrlMedium`.
- **Garmin's own `userLevel`/`userPoint` are not shown.** They are unrelated to this app's XP, and showing both would confuse.
- **Nutrition goals** come from `GET /nutrition-service/settings/{today}`, read-only, with a "Change in Garmin Connect" note.

**Fallback for both:** the section says "Couldn't load from Garmin" and the rest of the screen works.

### D9. Preferences are a small `@Observable` backed by `UserDefaults`

`AppPreferences` lives in the app target. Its keys:

| Key | Default |
|---|---|
| `haptics` | on |
| `celebrations` | on (Reduce Motion always wins) |
| `czechOnlySearch` | off (now persisted) |
| `useGarminMealWindows` | on |

It uses standard `UserDefaults`: there's no App Group, so extensions can't read it, and nothing in an extension needs it.

### D10. Background delivery uses `BGAppRefreshTask` through SwiftUI's `.backgroundTask(.appRefresh)`

- Identifier: `cz.mlcousek.garminfood.refresh`.
- Registered in `BGTaskSchedulerPermittedIdentifiers`, with `UIBackgroundModes: [fetch]`.
- The handler runs `drainAndReconcile()` and then schedules the next request (earliest ≥ 30 min).
- The request is also scheduled when the app goes to the background with undelivered entries.

`UIBackgroundModes: fetch` needs no provisioning entitlement, so it works on a free Personal Team. Whether iOS actually grants refresh time to a sideloaded app is a device check, not an assumption.

**Fallback:** the existing foreground drain, unchanged.

### D11. Design system grows, it doesn't fork

- New components go in `DesignSystem/Components.swift`: `ProgressRing`, `MacroBar`, `StatTile`, `CardContainer`, `DaySwitcher`, `MealSectionHeader`.
- `@ScaledMetric` replaces the fixed sizes the survey found (hero number, flame, empty-state icon, quick-pick card width).
- The streak flame's repeating pulse becomes conditional on Reduce Motion, which is a gap the survey found.
- Every new interactive element gets a VoiceOver label.
- Haptics go through one `Haptics` helper that honours the preference.

## Risks / Trade-offs

- **The delete route is unexercised.** Mitigation: user-initiated only, confirmation first, loud failure.
- **No device here; SwiftUI is only compiled.** Mitigation:
  - keep logic in tested packages
  - keep views small and previewable
  - list every visual and behavioural check in the device checklist
- **Two meal-day notions remain.** `NutritionDate` is calendar midnight; gamification uses a 04:00 boundary. They disagree between 00:00 and 04:00. This change doesn't widen the gap. Unifying them is future work, noted rather than silently "fixed".
- **The logging intents create their own `Outbox(processName: "app")` on the same file as the app's.** A drain from Siri and one from the app can overlap. Reconciliation still dedupes against Garmin, so the worst case is a duplicate that gets cleaned up. This is unchanged by this change and noted for `add-glanceable-surfaces`.
- **Many screens at once.** Mitigation: build in vertical slices, each compiled and tested in CI before the next.
