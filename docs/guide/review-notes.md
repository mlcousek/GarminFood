# Review notes

Things that looked wrong, inconsistent or undocumented while reading the
whole app for the guide (code at commit `c671907`). Nothing here was
changed. Paths are relative to `ios/`. Items marked "unverified" need a
closer look before acting on them.

## Gamification

1. **Completionist (`achv-meta-100`) can never be earned in practice.** It
   needs every other core achievement, including `achv-level-200`
   (`Achievements.swift:244`, `:423`). At the XP budget's typical day
   (128 XP, `XPBudget.swift`) level 200 takes about 472,600 days; the
   extractor gets level 106 after 10 years and 120 after 20. Also out of
   reach in a lifetime of normal use: `achv-level-125/150/175/200`,
   `achv-logs-100000` ("The Immortal Logger", about 78 years at 3.5 logs a
   day, `Achievements.swift:259`), `achv-funny-whale-10` and `-30` (15 M and
   45 M kcal). `LevelCurve.swift` calls high levels "honestly aspirational",
   but a meta badge that depends on them is permanently locked.
2. **"Midnight Snack Club" says "exactly midnight" but checks the whole
   00:00–00:59 hour.** Subtitle at `Achievements.swift:413`; rule at
   `AchievementSignals.swift:31-32` (`hour == 0`).
3. **The same name is used for different things.** Players will see two
   different "Dawn Patrol"s, "Halfway There"s and so on:
   - "Dawn Patrol": secret badge (`Features/Secret/SecretCatalog.swift:191`)
     and daily challenge `daily-early-7-2` (`DailyChallenges.swift:249`).
     The daily challenge shows the secret's name on the Today screen.
   - "Halfway There": `achv-meta-50` (`Achievements.swift:421`) and
     `body.halfway` (`Features/SportBody/SportBodyCatalog.swift:253`).
   - "Full House": `record.full-house` (`Features/Records/PersonalRecordCatalog.swift:229`)
     and challenge `multi-meal-4-3` (`ChallengeTemplates.swift:493`).
   - "Stack Week": supplement badge (`Features/Supplements/SupplementsCatalog.swift:101`)
     and challenge `supp-stack-5` (`Features/Supplements/ChallengeTemplates+Supplements.swift:64`).
     The Czech names differ ("Týden bez vynechání" vs "Týden s doplňky").
   - "Something Fishy", "Something New", "Clean Sweep", "Double Digits",
     "Connoisseur": each is used by two of challenge / daily challenge /
     bingo square / badge.
4. **Awkward generated English titles.** `goalHitDaysFamily` joins a macro
   name and a suffix (`Achievements.swift` `goalHitDaysFamily`), producing
   "Carb One Full Year", "Fat Two Full Years" and "Calorie Century Club".
   The Czech titles are hand-written and read fine.
5. **"Marathons' worth of energy burned" is counted from calories eaten.**
   `achv-funny-marathon-*` (`Achievements.swift:383-385`) uses lifetime
   logged calories, while the text says "energy burned".
6. **The XP budget's badge counts don't match the catalogs.** The
   `badgeXP(n)` terms in `XPBudget.swift:101-156` assume these feature badge
   counts over three years, against the catalog sizes:

   | Feature | Budget | Catalog |
   |---|---|---|
   | records | 3 | 4 |
   | bingo | 6 | 7 |
   | boss | 6 | 7 (5 boss + 2 freeze) |
   | journeys | 8 | 12 |
   | seasonal | 10 | 15 |
   | collections | 6 | 21 |
   | sport & body | 10 | 23 |

   These are "expected unlocks", so a smaller number can be deliberate. The
   records line comments "3 badges" while the catalog has 4, which looks
   like drift. The extra XP is small (30 per badge over three years), so
   the curve barely moves.
7. **Stale badge id in a comment.** `Features/ChallengeRotationPolicy.swift:17`
   names `achv-all-challenges`; the real id is `achv-challenges-all`.
8. **Anniversary rarity never reaches Legendary.** The breakpoints in
   `AchievementRarity.swift` go up to 4 years, but the catalog stops at
   `achv-anniversary-3`. This is harmless but may not be intended.
9. **Czech plurals in Gamification strings (unverified).** Gamification has
   no `.stringsdict`, so counted nouns use one fixed form. For example
   `cs.lproj/Localizable.strings:488` "tvoje série %lld dní" reads "1 dní"
   for a 1-day value. The freeze moment only fires for streaks of 3 or more
   days, so this particular line may never show 1; other `%lld` strings
   weren't checked.

## Logging and search

10. **Siri may log 100× the intended amount (unverified).**
    `Shortcuts/LogNamedFoodIntent.swift:95` falls back to
    `serving.numberOfUnits` as the multiplier when no serving is
    remembered. For a "100 g" serving that is 100 servings. The confirm
    screen documents and fixes exactly this case
    (`LogEntry/LogEntryConfirmView.swift:88-96`).
11. **A search tap ignores the remembered amount.**
    `Catalog/FoodCatalogView.swift:559-561` pre-selects the remembered
    serving but starts at 1×. Shelf cards and Siri use the remembered
    amount.
12. **OFF → Garmin matching compares calories on different sizes.**
    `GarminFoodMatching.swift:46,66` compares OFF kcal per 100 g with the
    Garmin candidate's first serving, which may not be 100 g. It also
    normalizes names with its own folding (line 100) instead of `SearchText`.
13. **Garmin-mode barcode fallback is narrower than standalone.** The
    offline-index fallback in `BarcodeResolution.swift:84,90` tries only
    the raw code, not the UPC-A variant without the leading zero, and
    never checks barcodes saved on custom foods. Standalone does both
    (`StandaloneBarcodeResolution.swift:47-53`).
14. **Custom foods can't be edited or deleted from the UI.**
    `CustomFoodStore.delete` (`CustomFood.swift:264`) has no caller. The
    editor also doesn't expose the model's `fiber` and `saturatedFat`.
15. **The confirm Date picker allows future dates**
    (`LogEntryConfirmView.swift:247`), but the day switcher can't go past
    today, so a future entry isn't visible until that day.

## Screens

16. **"Today" and "Yesterday" on the day switcher may not be translated.**
    `DesignSystem/Components.swift:580-581` returns plain `String` literals
    shown with `Text(title)`, which doesn't look up translations.
17. **Water totals disagree between screens.** Trends, the water streak and
    the Progress Trends card count only drinks logged in this app
    (`Trends/TrendsView.swift:26-29`). Today includes Garmin's total. The
    water streak also starts from today, so it reads 0 every morning until
    today's goal is met (`HydrationTracking.swift:137-147`).
18. **Two "on target" rules.** The day ring uses 95–105%
    (`CalorieBand.swift`); meal cards and macro bars use 90–110%
    (`MealDashboard.swift:55-61`). This is documented in
    `CalorieBand.swift:5-8`, but it can look contradictory.
19. **Copy from… says "Garmin" in standalone mode.**
    `Today/EntryEditing.swift:411,519` ("Reading that day from Garmin…"),
    `Progress/ProgressViews.swift:949`, and the Siri description
    `LogNamedFoodIntent.swift:41` ("Searches … Garmin's food database").
20. **There is no undo** for delete, edit or move of food entries. Only the
    layout editor has "Undo reset".
21. **Meal, streak and challenge reminders fire only on days the app was
    opened.** They are today-only requests (`App/NotificationScheduler.swift:12-14`).
    The Reminders screen doesn't say so; fasting reminders repeat without
    the app.

## Data and appearance

22. **Restoring a backup can switch the data mode.** `dataMode.v1` isn't
    excluded from backed-up preferences (`Backup/BackupExclusions.swift:53-55,73-80`).
    This is not documented in the UI, and may or may not be intended.
23. **Quarantined files end up in backups.** `*.unreadable-<stamp>.json`
    (`GarminKit/PersistedJSON.swift:217`) passes the backup filter and
    shows under "Other files" in the import preview.
24. **The unknown-theme fallback disagrees.** Share codes fall back to
    Classic (`AppearanceKit/ThemeShareCode.swift:21-22,206`), while
    `ThemeCatalog.themeOrDefault` (`ThemeCatalog.swift:82-84`) and widgets
    use Teal.

## Stale comments

25. Out-of-date comments:
    - `FoodLogCore/DataMode.swift:16-21` and `Profile/DiagnosticsLogView.swift:9-11`
      say standalone is unreachable until onboarding exists. Onboarding
      and Settings → Data now both switch modes.
    - `DesignSystem/BadgeMedallion.swift:8-9` says the glow is for the top
      two rarities. The coloured shadow is on every unlocked badge; only
      the shine is Epic/Legendary.
    - `AchievementRarity.swift:36` says "three ascending breakpoints"; there
      are four.
    - `Today/TodayView.swift:14-22` and `Today/DayNoteCard.swift:3` describe
      an old card order.
    - The `Progress/Slots/*SlotView.swift` headers refer to
      `ProgressSlotHost`, which no longer exists.
    - `project.yml:143-146` says "11 icons, one per theme"; there are 13
      themes and 12 icon options.
26. **Route confirmation status is described inconsistently.**
    `App/GarminSSOWebView.swift:46-49` and `App/AuthBannerView.swift:15-17,64-67`
    call the ticket exchange and write routes unconfirmed, but
    `GarminAuthSession.swift:27-31` says sign-in was confirmed end to end on
    2026-09-16. Reconcile against `docs/garmin-routes.json`.

## Localization check

The extractor found **no catalog string without Czech** (achievements,
challenges, daily challenges, tiers, bingo, bosses, journeys, records,
collections, seasonal events, secrets, sport & body, supplements, evidence
cards). The app String Catalog has Czech for every translatable key.
