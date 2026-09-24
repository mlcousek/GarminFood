## Why

The owner's fiancée does not read English and is going to use GarminFood.
The owner asked to *"introduce multiple languages starting with Czech, but in
future maybe more … by best practices."* Today every piece of UI text is an
English literal; there is no string catalog, no `defaultLocalization` in any
package, and several screens build sentences from English fragments that
cannot be translated correctly into Czech (plurals `1 den / 2 dny / 5 dní`,
noun cases inside sentences, decimal comma). The full analysis — string
inventory per module, Czech-specific traps, and why each mechanism was
chosen — is in [`docs/localization-analysis.md`](../../../docs/localization-analysis.md).

## What Changes

- **Localization infrastructure** (Wave 1): English is the development
  language, Czech (`cs`) the first additional one.
  - App and widget: `Localizable.xcstrings` String Catalogs (later also
    `AppShortcuts.xcstrings`, `InfoPlist.xcstrings`), compiled by
    `xcodebuild` in CI; XcodeGen settings `developmentLanguage`,
    `CFBundleLocalizations`, `LOCALIZATION_PREFERS_STRING_CATALOGS`,
    `SWIFT_EMIT_LOC_STRINGS`.
  - SPM packages (FoodLogCore, Gamification, later GarminKit):
    `defaultLocalization: "en"` and `Resources/<lang>.lproj/Localizable.strings`
    (+ `.stringsdict`) looked up with `bundle: .module` — the format plain
    `swift test` can actually load, so Czech resolution is unit-tested.
  - `tools/check-localizations.mjs`, run in CI, fails on invalid catalogs,
    missing/unreviewed Czech, format-specifier mismatches and incomplete
    Czech plural sets; plus a non-blocking `xcodebuild -exportLocalizations`
    artifact (the compiler-extracted key list) and an `xcstringstool
    compile` check.
  - A smoke string end-to-end in the app, a plural in the app, one
    FoodLogCore string, one Gamification string and one widget string.
  - A convention in `CLAUDE.md`: new user-facing text is localizable and
    translated from day one.
- **Czech translation**, in waves: app shell + most-used screens (Wave 2),
  remaining screens + FoodLogCore texts incl. notifications (Wave 3),
  Gamification content after each gamification change lands (Wave 4),
  Siri/App Shortcuts phrases, widget/Controls, Info.plist (Wave 5), polish:
  locale-aware number formatting, plurals, truncation, accessibility labels,
  a Settings row that opens the per-app Language setting (Wave 6).
- **Language selection follows iOS** (system language or Settings › GarminFood
  › Language). No in-app language switcher.

## Capabilities

### New Capabilities

- `localization` - the app, its widget/Controls, Siri phrases, notifications
  and package-provided display text appear in the user's iOS language
  (English or Czech), with correct Czech plurals and number formatting, and
  CI rejects incomplete translations.

### Modified Capabilities

(none — existing capabilities' behaviour is unchanged; only the language of
their text changes.)

## Non-goals

- **Translating food data.** Food names from Garmin, Open Food Facts and the
  offline Czech index are shown as the source provides them. Czech food
  *search* is owned by `rebuild-food-search` / `add-offline-czech-food-index`.
- **An in-app language picker** (see design D1).
- **Localizing `DiagnosticsLog`** — developer-facing, stays English
  (`add-reminders-and-diagnostics` owns it).
- **Writing the new gamification copy itself.** The 8 in-flight gamification
  changes (`add-weekly-bingo`, `add-weekly-boss-and-streak-freezes`,
  `add-journeys-and-records`, `add-seasonal-events`,
  `add-secret-achievements`, `add-sport-and-body-achievements`,
  `add-gamification-signals`, `expand-gamification-depth`) own their English
  copy; this change owns only its Czech translation (Wave 4) and the rule
  that their strings are written localizable.
- **Themes / standalone mode** — owned by their own changes; they follow the
  same rule for new strings.
- **A third language.** The infrastructure supports it (design D8); choosing
  and translating one is a future change.

## Impact

Affected surfaces: `ios/project.yml`, the three `Package.swift` files, new
`Resources/` folders in the app, widget, FoodLogCore and Gamification,
`.github/workflows/build.yml`, new `tools/check-localizations.mjs`,
`CLAUDE.md` conventions; then, per wave, view files and package display-text
properties. No Garmin route, no store format, no network change.

**Depends on**: nothing (Wave 1 is standalone). Wave 4 depends on each
gamification change having landed on `main`.

**Unblocks**: the fiancée using the app in Czech; any future language.
