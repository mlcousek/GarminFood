## Why

The app works end to end since 2026-09-16: sign-in, reading the day, and writing food all run on a real device. But it is one screen. Today shows a single calorie total, even though Garmin already returns a suggested calorie and macro target for every meal. Levels and challenges exist only as one row. There is no settings screen, no way to sign out, and no profile. The owner asked for the app to become a complete product: meals laid out the way Garmin's own food page does, dedicated progress screens, and settings and a profile.

## What Changes

- Add an **app shell** with three tabs: **Today**, **Progress**, **Profile**. Widget taps and the barcode Control resolve at the shell, not inside one nested screen.
- Rebuild **Today** around meals. Breakfast, Lunch, Dinner and Snacks each show logged foods and consumed vs suggested calories and macros, using Garmin's own per-meal goals. Entries still waiting to sync appear in their meal. Any day can be viewed.
- Add a **meal detail** screen: the full nutrient breakdown, logging straight into that meal, and deleting an entry.
- Add **Progress** screens: level and XP (and how XP is earned), a streak calendar with the longest streak, and challenges (active, all, completed).
- Add **Profile** (Garmin name and photo, lifetime stats) and **Settings** (Garmin account and sign-out, Garmin nutrition goals, sync queue with retry and delete, logging and feedback preferences, about).
- Pre-select the meal from **Garmin's meal windows** instead of a fixed hour table.
- **Background sync**, so queued entries are delivered even when the app isn't open (carries `add-garmin-auth-and-sync` task 9.5).

## Capabilities

### New Capabilities

- `app-navigation` - the tab shell and how external entry points (widget, Control, Siri) land in it.
- `meal-dashboard` - the day organised by meal, with Garmin's per-meal targets, pending entries, day navigation, meal detail and entry deletion.
- `progress-screens` - level/XP, streak history and challenge screens.
- `profile-and-settings` - profile, account, nutrition goals, sync queue, preferences and about.

### Modified Capabilities

None of the archived specs change in behaviour. `food-log-entry`'s "meal type defaults sensibly" is satisfied more precisely (by Garmin's windows), not redefined.

## Non-goals

- **Editing Garmin nutrition goals or meal windows from the app.** They are shown read-only; changing them stays in Garmin Connect. A write route for settings exists (`garmin_mcp` `set_nutrition_daily_settings`) but is out of scope.
- **Editing a logged entry's quantity in place.** No update route is known (`establish-garmin-nutrition-contract` 4.2). Delete and re-log covers it.
- **Streak/level widgets.** Still impossible without an App Group (`add-glanceable-surfaces` D2).
- **New challenge templates or XP rules.** Owned by `add-gamification`; this change only gives them screens.
- **Social features**, as in `add-gamification`.
- **Control Center/lock-screen polish** (`add-glanceable-surfaces` 17.3) is carried by that change, not this one.

## Impact

App target: new `Shell`, `Today`, `Progress`, `Profile`, `Settings` view groups; `AppEnvironment` gains a day loader, preferences and profile state. FoodLogCore gains pure, unit-tested dashboard logic (meal sections, macro progress, meal-window defaulting). Gamification gains streak history and a completed-challenge record. GarminKit gains two read routes, `GET /nutrition-service/settings/{date}` and `GET /userprofile-service/socialProfile`, both probed 200 on 2026-09-16. The app starts calling `DELETE /nutrition-service/food/logs/{date}` from a user action for the first time. `project.yml` gains the background-refresh Info.plist keys.

**Depends on**: `add-garmin-auth-and-sync` (auth and the confirmed write), `add-gamification` (engines the progress screens display), the archived `food-log-entry` and `food-catalog` specs.

**Unblocks**: `add-glanceable-surfaces` 20.2 (a user-facing delete flow now exists to hook donation deletion into), and every future "add-on" screen, which now has a place to live.
