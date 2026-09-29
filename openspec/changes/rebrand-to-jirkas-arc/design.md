## Context

Written 2026-09-28 against `origin/main` @ `a4ee380`, from reading the code.
The owner's decisions it rests on (dated 2026-09-28): the app becomes his
training hub with the plan at its heart (A2, A11); it is called "Jirka's
Arc", display name and icon only, bundle id kept (A16); its screens are
Today, Plan (week and month), later Season, Phase, Race and Statistics, plus
the existing food and weight (A18); and he likes the current look and
themes and wants to keep them.

What the code says today:

- `ios/project.yml`: neither target sets `CFBundleDisplayName`, so the home
  screen shows the product name, "GarminFood". The widget sets
  `CFBundleDisplayName: GarminFood Widget`, translated in
  `GarminFoodWidget/Resources/InfoPlist.xcstrings` as "Widget GarminFood".
  Neither `MARKETING_VERSION` nor `CURRENT_PROJECT_VERSION` is set; every
  build reports 1.0 (1), which `DataSafetyPreferences.appVersion` writes
  into every backup manifest.
- Catalogs: 33 of 1261 keys in the app's `Localizable.xcstrings` and 15 of
  53 in the widget's contain "GarminFood". Examples: "Welcome to
  GarminFood", "This isn't a GarminFood backup.", "Opens GarminFood". Siri
  phrases in `AppShortcuts.xcstrings` use `${applicationName}` and follow
  the display name by themselves. FoodLogCore has one ("Check today's
  challenges in GarminFood.").
- Icons: the primary is white "GF / by Jirka" letterforms on a navy-to-cyan
  diagonal gradient. `tools/generate-app-icons.py` recolours that gradient
  into 11 alternates (`AppIcon-Indigo` … `AppIcon-Gold`), deriving the
  glyph's coverage from the primary PNG. Each theme is paired with one
  (`add-themes-and-layout` R2, R5). `AppIconSwitcher` resets an alternate
  name that no longer exists.
- `AppSignatureView`: "GF" in `Theme.flameGradient` over "by Jirka", pinned
  to the bottom of Today (`TodayCardID.signature`, not hideable).
- Navigation: `ContentView` has three tabs, each with its own
  `NavigationStack` (`AppRouter.Tab.today/.progress/.profile`). Today's tab
  label is "Today" (`fork.knife`), its title "Food log". The start tab
  (`StartTab`, AppearanceKit) is `.today` or `.progress`. External routes
  (`garminfood://logFood`, the barcode Control) switch to Today and open the
  catalog.
- Today is a card screen: `LayoutCatalog.today` lists 12 cards in a default
  order, the user can reorder, hide and vary them, and `LayoutResolver`
  rule 3 inserts a card new to the catalog right after its nearest
  predecessor in the default order.
- `add-standalone-mode`: the fiancée's install is standalone (no Garmin).
  Its open question 0.5 ("keep GarminFood or a neutral name") was defaulted
  to "keep GarminFood". This change answers it again, see D2 and tasks 0.3.

## Evidence (probes)

No live probe. Nothing here calls a network route. Three platform facts the
design relies on are documented Apple behaviour, re-checked on the device
in the tasks rather than assumed:

| Fact | Source | Checked on device in |
|---|---|---|
| iOS keys an app's identity on its bundle id; the display name can change freely between updates without touching the container or the Keychain | Apple's bundle documentation; the whole `add-garmin-auth-and-sync` D8 update-in-place model already relies on it | task 5.2 |
| An `InfoPlist.strings` value for a key overrides the `Info.plist` value in that language | Apple's localization documentation; how `NSCameraUsageDescription` is already translated here | task 5.2 (Czech phone) |
| Xcode expands `$(BUILD_SETTING)` references in `Info.plist` values at build time (`INFOPLIST_EXPAND_BUILD_SETTINGS`, default on) | Apple's build-settings reference | task 3.3 (CI prints the archived plist) |

## Goals / Non-Goals

**Goals**
- The phone, the widget gallery, Siri and every screen say "Jirka's Arc".
- An update in place keeps every byte of data, the Garmin sign-in, the
  chosen icon, placed widgets and Controls, and the Siri phrases.
- A new icon that is recognisably the same family as today's.
- A real version and build number.
- A tab shell with a Plan tab for the training experience, while the
  food-first experience stays pixel-identical.

**Non-goals**: see proposal.md.

## Decisions

### D1 — Display name only; every identifier stays

| Identifier | Value (unchanged) | Why it must stay |
|---|---|---|
| App bundle id | `com.mlcousek.garminfood` | A new id is a new app: empty container, unreachable Keychain, new AltStore App IDs (2 of ~10 a week), Controls and widgets removed |
| Widget bundle id | `com.mlcousek.garminfood.widget` | Must stay a child of the app id |
| URL scheme | `garminfood` | Garmin SSO callback (`GarminSSOEndpoints.callbackURLScheme`), widget `widgetURL`s, shared theme links already sent to people |
| Keychain services | `com.mlcousek.garminfood.garminkit` (and any later) | Items are found by service name; renaming loses the Garmin token |
| BG task id | `com.mlcousek.garminfood.refresh` | Must match `BGTaskSchedulerPermittedIdentifiers` |
| Store paths | `Application Support/GarminKit/…`, `FoodLogCore/…`, `GarminFood/donations.json`, … | Moving them is a migration for nothing |
| Backup manifest marker | as in `BackupManifest` | Old backups must still import |
| Theme code prefix | `GFT1.` | Codes already shared must still import |
| Alternate icon names | `AppIcon-Indigo` … `AppIcon-Gold` | iOS remembers the chosen alternate by name; same names mean the new artwork appears after the update with the user's choice intact |
| Layout card ids | `signature`, … | Stored layouts and shared theme codes name them |
| Target, scheme, product, `.ipa` artifact name | `GarminFood` | Every doc, CI path and header comment names them; nothing user-facing does |

The rule for code: identifiers and storage keep "GarminFood"; only
user-facing text changes. Swift type names (`GarminFoodDeepLink`,
`GarminFoodApp`) stay.

### D2 — The name in English and Czech, from one build setting

- **English: "Jirka's Arc". Czech: the same, "Jirka's Arc"**, untranslated,
  like a product name. "Jirkův oblouk" was considered and rejected: it
  reads as a description, not a name, and the owner chose the English
  wording. Owner may override (tasks 0.2).
- **ASCII apostrophe** (`'`, not `’`) everywhere, including in-app prose,
  so Spotlight and Siri match what people type and say, and so catalog
  keys have one spelling.
- **One build setting.** Both targets get
  `CFBundleDisplayName: $(APP_DISPLAY_NAME)`, with
  `APP_DISPLAY_NAME: "Jirka's Arc"` in `project.yml`'s base settings.
  - The app's `InfoPlist.xcstrings` gets **no** Czech value for
    `CFBundleDisplayName` (`shouldTranslate: false`, as `CFBundleName`
    already is): a Czech `InfoPlist.strings` value would override the build
    setting on a Czech phone.
  - The widget's existing Czech entry ("Widget GarminFood") is removed the
    same way, and its display name becomes the app's name. The widget
    gallery already groups widgets under the app, so "Jirka's Arc" alone is
    clearer than "Jirka's Arc Widget".
  - A differently named build for the second install is then one
    `xcodebuild … APP_DISPLAY_NAME="…"` argument (tasks 0.3). Nothing
    builds it in this change.
- **"Jirka's Arc" is 11 characters** and fits under a home-screen icon
  without truncation at the default text size (checked on device, 5.2).
- **Strings that name the app.** Each of the 48 catalog keys (and the one
  FoodLogCore string, the `Summary("Log … in GarminFood")` of
  `LogNamedFoodIntent`, the `"GarminFood Screen"` type display name, the
  two widget accessibility hints and the Profile fallback name) is
  classified:
  - it names **the app** → "Jirka's Arc" (e.g. "Welcome to Jirka's Arc",
    "Opens Jirka's Arc");
  - it names **Garmin, the service** → unchanged ("Couldn't search Garmin:
    sign in again in Jirka's Arc first" changes only the app part).

  Keys are the English text, so each change is a new key with its Czech
  value and the old key removed; `tools/check-localizations.mjs` catches a
  missed one. Czech keeps the name indeclinable ("v Jirka's Arc", "do
  Jirka's Arc"), matching how "GarminFood" is used today.
- **Backups.** The export file name becomes
  `JirkasArc-backup-yyyy-MM-dd.json` (no apostrophe in file names). Import
  never looked at the file name, and the manifest marker is unchanged, so
  an old `GarminFood-backup-…json` still imports.
- **The About text** in Settings depends on the experience (owner review,
  2026-09-28): in the training experience "Jirka's Arc: training plan, food
  and weight, by Jirka."; in the food-first experience (every install
  without a vault connection, so every standalone install, the second
  install included) "Jirka's Arc: food and weight, by Jirka." Either is
  followed by the mode-specific sentence about Garmin (or this phone) and
  the existing Open Food Facts credit. The rule is AppearanceKit's
  `AppExperience.mentionsTrainingPlan`, from the same experience input as
  the tab shell (D6), and is unit-tested.

### D3 — The icon: an arc mark above "by Jirka"

**Concept A (proposed default).** Keep everything that makes the current
icon recognisable: the full-bleed diagonal gradient, the white glyph, the
small "by Jirka" line in its current place and size. Replace only the "GF"
letters with an **arc mark**:

- a thick white arc with rounded caps, opening downwards and rising from
  lower left to a shoulder right of centre, like a season's build curve or
  a hill profile;
- a solid white dot riding the arc just past its peak: "you are here in the
  arc";
- stroke weight equal to the old "GF" stems, so the visual weight and the
  contrast policy of the paired themes are unchanged.

Two alternatives go to the owner with a rendered PNG each (tasks 0.1): **B**
a lowercase "j" whose hook sweeps up into the arc, and **C** an "A" drawn as
an arc (no apex) with the dot as its crossbar.

**Generation (no Mac, reviewable on Windows).** `tools/generate-app-icons.py`
today derives the glyph's coverage from the primary PNG. It changes to:

1. A one-time step extracts the "by Jirka" coverage from the **current**
   primary with the existing alpha code and commits it as
   `tools/icon-src/by-jirka-mask.png` (1024 px, 8-bit). The current
   primary's corner colours are recorded as a new `Teal` entry in `ICONS`
   first, because the primary itself is about to be regenerated.
2. The arc and dot are drawn procedurally with Pillow at 4096 px and
   downsampled to 1024 px (anti-aliasing without a font or vector tool).
3. Glyph coverage = max(arc, "by Jirka" mask). Every icon, now **including
   the primary**, is `lerp(gradient(t), white, coverage)` as before.
4. Outputs: `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` and the
   22 alternate PNGs, same names and sizes. `--check` still compares
   without writing.

The owner reviews the PNGs in the pull request; GitHub renders them. No
alternate is renamed or removed, so `project.yml`'s
`CFBundleAlternateIcons` and `AppIconOption.swift` need no edit and
`AppIconSwitcher.resetRemovedAlternateIfNeeded` has nothing to reset.

### D4 — The in-app signature

`AppSignatureView` keeps its size, place and role (the Today footer, the
`signature` card id). "GF" becomes `ArcMark`, a small SwiftUI `Shape`
(`Path.addArc` plus a circle) filled with the same flame-gradient token the
"GF" used, above the existing "by Jirka" caption. VoiceOver reads "Jirka's
Arc, by Jirka". It uses theme tokens only; the design-token lint passes
without an allowlist entry. The same shape is reused by the onboarding
welcome page instead of any "GF" text.

### D5 — Version and build number

- `project.yml` base settings: `MARKETING_VERSION: "2.0"`,
  `CURRENT_PROJECT_VERSION: "1"`. The rebrand is the natural 2.0; 1.x was
  GarminFood. Owner may override (tasks 0.4).
- Both targets' `info.properties` set
  `CFBundleShortVersionString: $(MARKETING_VERSION)` and
  `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` explicitly. XcodeGen's
  generated defaults are not relied on, and the widget always matches the
  app (Xcode warns when an extension's version differs from its parent's).
- **The build number is CI's run number.** The archive step passes
  `CURRENT_PROJECT_VERSION=${{ github.run_number }}`. It increases on every
  run of the workflow, on any branch, with nothing to remember. A local or
  Simulator build keeps "1".
- A CI step prints both keys from the archived app and widget `Info.plist`
  (`plutil -p`), so the value is visible evidence, not an assumption.
- Where it shows: Settings → About (already reads both keys), backup
  manifests (`DataSafetyPreferences.appVersion`) and, later, the vault
  events' `src.build`.
- Marketing-version bumps stay manual: one line in `project.yml`, in the PR
  that deserves it.

### D6 — Two experiences, one tab shell

`AppExperience` (AppearanceKit, pure, tested) has two values:

- **`.foodFirst`**: the default, and the value for every install without an
  enabled vault connection. That includes every standalone install, so the
  fiancée's phone is always here.
- **`.training`**: only when the app says a vault connection is enabled.
  AppearanceKit doesn't know what a vault is; it takes one Bool. Until
  `add-training-today-and-plan` wires that Bool to the vault settings, the
  only way in is the preview toggle (D9).

`AppShell.tabs(for:)` is the single source of the tab set:

| Experience | Tabs (in order) | Today's title | Today's tab icon |
|---|---|---|---|
| `.foodFirst` | Today · Progress · Profile | "Food log" (unchanged) | `fork.knife` (unchanged) |
| `.training` | **Today · Plan · Progress · Profile** | "Today" | `sun.max` |

Plan uses `calendar`; Progress and Profile keep their icons. Every tab
keeps its own `NavigationStack`, so switching tabs keeps each one's place.

**Today in the training experience is the same card screen**, not a new
one. `TodayView` already renders a user-ordered card list through
`LayoutCatalog`. `add-training-today-and-plan` adds the training cards to a
training-only catalog (`LayoutCatalog.today(for: .training)`), placed right
after the day switcher, so they lead the screen. The food cards stay on it
below them: the calorie summary, "Log again" quick picks, meals, "Log a
meal", weight and water. The toolbar "+" stays. So:

- a food still logs in two taps from Today ("Log again" → confirm), as it
  does now;
- the full food day (meals, editing, day switching, notes, fasting,
  supplements) is still one scroll away, with no new screen to learn;
- the owner can reorder or hide any of it with the existing layout editor.

`LayoutCatalog.today(for: .foodFirst)` is exactly today's 12 cards, and the
existing golden test pins it. A training card is never in the food-first
catalog, so the fiancée's editor never lists one. A layout stored in one
experience keeps the other experience's cards through `LayoutResolver` rule
2 (unknown ids are kept, not rendered), so switching back and forth loses
no arrangement. This change adds only the `for:` parameter and the golden
test; the training catalog stays equal to the food-first one until
`add-training-today-and-plan` adds its cards.

**Alternative considered: a fifth "Food" tab** (Today · Plan · Food ·
Progress · Profile), with the current Today moved there unchanged and a
small quick-log card on a new training Today. Rejected as the default:

- five tabs is the iOS maximum, leaving no room for later growth;
- food logging would split across two tabs, and Controls and widget links
  would have to pick one;
- the card screen already solves "training first, food kept" with
  reordering the owner controls.

It stays open for the owner (tasks 0.5).

### D7 — Where the later screens go

Decided now so later changes don't reshuffle the tab bar:

| Screen (owner's A18) | Home | Change |
|---|---|---|
| Today | Today tab | this change (shell) + `add-training-today-and-plan` |
| Plan: week, month, session detail | Plan tab, segmented Week · Month | `add-training-today-and-plan` |
| Season timeline | Plan tab, a third segment "Season" | `add-season-phase-race-screens` |
| Phase (+ recap) | pushed from Season and from the week header | same |
| Race (prep, countdown, race-day timeline, result) | pushed from Season, from the month calendar's race day, and from Today's countdown chip | same |
| Statistics | Progress tab, a "Training" section at the top | `add-training-stats` |
| Food & weight | Today (cards) and Progress (Weight, Trends), as today | existing |

The tab bar stays at four in the training experience.

### D8 — Start tab and routes

- `StartTab` gains `.plan`. `AppShell.resolvedStartTab(stored:experience:)`
  returns the stored tab only when that experience shows it, else Today. A
  food-first install that somehow stored `plan` opens on Today. The
  Appearance "Start on" picker lists only the tabs the current experience
  shows.
- `AppRouter.Tab` gains `.plan`. `selectedTab` is corrected to Today
  whenever the experience changes and the selected tab isn't in the new
  set.
- `GarminFoodDeepLink` gains `plan` (`garminfood://plan`, optional
  `?date=YYYY-MM-DD`, kept on the router for the Plan tab to consume). In
  the food-first experience it opens Today. `logFood`, theme links and the
  barcode Control keep their behaviour: Today plus the catalog, in both
  experiences.
- The `plan` route exists now so notifications and the countdown chip in
  later changes have a target. Nothing sends it yet.

### D9 — Previewing the training shell before the vault exists

A hidden Settings → Diagnostics toggle, "Preview training shell (testing)"
(English only, a developer surface, like "Force standalone mode
(testing)"), forces `.training`. With it on:

- the tab bar shows Today · Plan · Progress · Profile and Today's title is
  "Today";
- the Plan tab shows its real empty state: "Your plan shows here once a
  vault is connected" with an SF Symbol and a short explanation. That is
  the same screen a connected install shows before its first projection
  arrives, so it isn't throwaway work.

The toggle is removed by `add-training-today-and-plan` once the real input
exists (its tasks own that removal).

### D10 — What the fiancée's install sees

A new name and icon (the same binary), a version in About, and otherwise
nothing: her install is standalone, has no vault connection, and is
therefore `.foodFirst` with today's tabs, titles, cards and layout editor.
The preview toggle is in Diagnostics, which she doesn't use. If she (or
the owner) wants a different name on her phone, D2's build setting makes
that one CI argument; the name inside the app's own text would still say
"Jirka's Arc" (tasks 0.3).

### D11 — Testing

- AppearanceKit (`swift test`):
  - `AppShellTests`: the tab set per experience, food-first equal to
    today's three tabs; the resolved start tab for every stored value ×
    experience (including an unknown string and `plan` in food-first).
  - `LayoutResolverTests` golden: `today(for: .foodFirst)` equals today's
    catalog byte for byte.
- `generate-app-icons.py --check` passes on the committed PNGs (run locally
  on Windows; Pillow only).
- CI prints the archived version keys (D5).
- Localization job: every new and changed key has Czech.
- UI is checked on the device (tasks group 5).

## Fallbacks for private-API dependencies

This change adds none and changes no Garmin route. The URL scheme, the SSO
callback and the Keychain service it depends on are kept exactly.

## Risks / Trade-offs

- **A missed "GarminFood" string** looks unfinished, not broken. Mitigated
  by the audit task and a grep in the PR description for any remaining
  user-facing occurrence (comments and identifiers excepted).
- **The apostrophe in Siri phrases.** `${applicationName}` becomes "Jirka's
  Arc". If Siri doesn't match it in Czech, the fallback is
  `INAlternativeAppNames` in the app's Info.plist ("Jirkas Arc", "Arc"),
  added only if the device check (5.4) fails.
- **Icon taste.** The concept is a proposal. Tasks 0.1 asks before the
  generator runs; the generator makes a second iteration cheap.
- **Placed widgets and Controls.** They are keyed by bundle id and kind,
  both unchanged, so they should survive the update in place. Checked on
  device (5.2); if one disappears, the owner re-adds it and the finding is
  recorded here.
- **Two experiences mean two tab sets** to keep working. The shell's rules
  are pure and tested, and the food-first set is pinned by a golden test.

## Migration Plan

1. Merge; CI builds 2.0 (run number). The owner updates in place through
   AltStore, as every week.
2. Nothing migrates: identifiers are unchanged, no store changes format.
3. Rollback: sideload the previous build. Only the name, icon and version
   go back; data is untouched (no store format changed, so the downgrade
   caveat of `add-data-safety` does not apply).

## Open Questions

Carried into tasks.md group 0 with proposed defaults:

1. Icon concept A (arc + dot), B ("j" into arc) or C (arc "A")?
2. Czech display name: "Jirka's Arc" (default) or a Czech form?
3. The fiancée's install: the same "Jirka's Arc" (default), or a second CI
   artifact with a neutral name (e.g. "Arc")?
4. Version 2.0 (default) or 1.x?
5. Four tabs with food on Today (default), or five with a Food tab?
