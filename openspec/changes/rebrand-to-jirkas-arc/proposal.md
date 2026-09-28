## Why

The app is becoming more than a food logger. The owner decided on
2026-09-28 (his decisions A2, A11, A16 and A18) that it turns into his
training hub on the phone, with the training plan at its heart and food
logging kept as a feature. He picked the name **"Jirka's Arc"**: a training
phase is an arc, a season is one big arc, and the name sits next to his
other personal system.

Three things about today's build make that awkward:

- The only name the phone shows is the bundle name, "GarminFood". Neither
  target sets `CFBundleDisplayName`, and 48 user-facing strings (33 in the
  app catalog, 15 in the widget catalog) say "GarminFood".
- The icon and the in-app signature are a "GF" monogram.
- No version is set. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are
  unset, so every build calls itself 1.0 (1). Backups, diagnostics and
  (later) vault events record that meaningless value.

The navigation also needs a place for the plan. Today there are three tabs:
Today (the food log), Progress and Profile. The planned training screens
(`add-training-today-and-plan`, and later season, phase, race and stats
screens) need a Plan tab and a training-first Today. At the same time, the
second install (the fiancée's, standalone mode, no Garmin, no vault) must
keep the food-first app she already uses.

A bundle-id change is not an option. On a free Personal Team a new bundle
id is a different app: an empty container (every JSON store gone) and an
unreachable Keychain (Garmin sign-in gone). So this is a **display-name and
look** change, with every identifier kept.

## What Changes

- **Display name "Jirka's Arc"** on the home screen, in the widget
  gallery, in Siri and in every user-facing string that names the app, in
  English and Czech. The Czech form is the same brand name, untranslated
  (design D2). The display name comes from one build setting, so a
  differently named build for the second install stays a one-line change.
- **Every identifier stays**: bundle ids `com.mlcousek.garminfood` and
  `com.mlcousek.garminfood.widget`, the `garminfood` URL scheme (Garmin
  sign-in callback, widget links, theme links), the Keychain service
  strings, the background task id, store file paths, the backup manifest
  marker, the `GFT1.` theme-code prefix, alternate icon names and layout
  card ids. Target, scheme and product names stay `GarminFood` too.
- **A new arc icon.** The glyph becomes an arc mark (a rising arc with a
  "you are here" dot) above the existing "by Jirka" line. The gradient
  backgrounds stay, so every one of the 13 themes keeps its paired icon.
  The committed generator draws the glyph itself and rebuilds the primary
  plus all 11 alternates.
- **The in-app signature** ("GF / by Jirka") becomes the same arc mark
  drawn as a SwiftUI shape with theme tokens.
- **Versioning.** `MARKETING_VERSION` 2.0 and a build number that CI sets
  from the workflow run number, identical for the app and the widget.
- **Two experiences, one shell.**
  - *Food-first* (the default, and every install without a vault
    connection, including every standalone install): exactly today's three
    tabs, titles, icons and Today screen.
  - *Training* (only when a vault connection is enabled): four tabs,
    **Today · Plan · Progress · Profile**. Today is titled "Today" and
    becomes training-first. Its food cards stay on it (the "Log again"
    quick picks, the calorie summary, meals, weight and water), so a food
    still logs in two taps.
  - This change builds the shell, the Plan tab's empty state, the start
    tab, and a `garminfood://plan` route. The training cards and the plan
    screens themselves come in `add-training-today-and-plan`. Until the
    vault connection exists, a hidden Diagnostics toggle previews the
    training shell for device checks.
- All new and changed text in English and Czech.

## Capabilities

### New Capabilities

- `app-identity`: the app's name, icon, signature and version, and the
  identifiers that must never change.
- `experience-shell`: the food-first and training experiences, the tab set
  each one shows, the start tab and the external routes into it.

### Modified Capabilities

None. The tab behaviour of the unarchived `add-app-shell-and-meal-dashboard`
(`app-navigation`) stays exactly as it is in the food-first experience,
which is the default. The training experience is specified as new
behaviour in `experience-shell`.

## Non-goals

- **Changing any identifier**: bundle ids, URL scheme, Keychain services,
  BG task id, target/scheme/product names, store paths or the CI artifact
  name. See design D1 for why each one stays.
- **Renaming the GitHub repository.** GitHub redirects a renamed repo, but
  nothing needs it; the owner may do it later by hand.
- **The training content of Today and the Plan tab** (sessions, the
  green/amber/red options, habits, race countdown, weekly note, week and
  month views). Owned by `add-training-today-and-plan`.
- **The vault connection** that turns the training experience on. Owned by
  `add-vault-connection`; wiring it to the shell is a task of
  `add-training-today-and-plan`.
- **Season, phase, race and statistics screens.** Owned by the later
  `add-season-phase-race-screens` and `add-training-stats`. Design D7 says
  where they will live.
- **iOS 18 dark and tinted icon variants.** They need the asset-catalog
  alternate-icon mechanism; still out of scope, as in
  `add-themes-and-layout` D10.
- **A separate build or name for the second install.** The build setting
  makes it possible; producing it is an owner decision (tasks 0.3).
- **Training gamification.** Later (`add-training-gamification`).

## Impact

- `ios/project.yml`: `CFBundleDisplayName: $(APP_DISPLAY_NAME)` for the app
  and the widget, `APP_DISPLAY_NAME`, `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` settings, explicit
  `CFBundleShortVersionString`/`CFBundleVersion` properties for both
  targets. No identifier changes.
- `.github/workflows/build.yml`: passes `CURRENT_PROJECT_VERSION` from the
  run number to the archive and prints the archived version keys.
- `tools/generate-app-icons.py`: draws the arc glyph; also writes the
  primary icon. New `tools/icon-src/by-jirka-mask.png`.
- New icon PNGs: the primary `AppIcon-1024.png` and 22 alternate files
  (same names).
- `AppearanceKit`: new `AppExperience` and `AppShell` (pure tab-set and
  start-tab rules), `StartTab.plan`. Tests.
- App: `ContentView`, `AppRouter` (`Tab.plan`, the `plan` route),
  `AppSignatureView` (arc mark), a new `Plan/PlanTabView.swift` (empty
  state only), the Diagnostics preview toggle, `Shared/GarminFoodDeepLink`
  (new action), the Appearance start-tab picker, and the catalogs
  (`Localizable`, `InfoPlist`, widget catalogs, FoodLogCore's
  `Localizable.strings` for one notification).
- `FoodLogCore`: the backup export file name only (`BackupVault`); the
  manifest marker is unchanged, so old backups still import.
- Docs: `README.md` and `CLAUDE.md` name the app "Jirka's Arc (repository
  and targets still named GarminFood)".

**Depends on**: nothing unshipped. Built on `origin/main` @ `a4ee380`
(`add-themes-and-layout`, `add-localization`, `add-standalone-mode` and
`add-data-safety` merged).

**Parallel with**: `add-vault-connection` (no shared files except the
catalogs, where both only add keys).

**Unblocks**: `add-training-today-and-plan` (the Plan tab, the training
experience and the experience-dependent Today catalog it fills in), and the
later `add-season-phase-race-screens` and `add-training-stats`.
