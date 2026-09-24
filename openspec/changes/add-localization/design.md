## Context

No Mac: Swift is compiled only in CI (`.github/workflows/build.yml` — three
`swift test` steps on macOS, then `xcodegen generate` + `xcodebuild` for the
app with its embedded widget). Nobody can open Xcode's String Catalog
editor, so every catalog is hand-authored or script-generated JSON, and
"does it work" is answered by CI and by a sideloaded build on a phone set to
Czech. Full inventory and rationale: `docs/localization-analysis.md`.

Evidence gathered 2026-09-24 (web research, no probing needed — nothing here
touches Garmin):

- XcodeGen 2.39.0 added `.xcstrings` support (PR #1421): catalogs go into the
  Resources build phase and **locales found in a catalog are added to the
  project's `knownRegions`**. CI installs XcodeGen via `brew` (latest).
- SwiftPM on the command line (`swift build` / `swift test`) does **not**
  compile `.xcstrings` (only Xcode/xcodebuild does), and a package whose only
  resource is a catalog has failed to get `Bundle.module` under `swift build`
  (swiftlang/swift-package-manager#6993, FB13261704; Apple forums 739447;
  elegantchaos.com 2026-02-12).
- SwiftPM has supported `<lang>.lproj/*.strings` / `*.stringsdict` package
  resources with `defaultLocalization` since tools-version 5.3, identically
  in `swift build` and Xcode.

## Decisions

### D1 — Follow the iOS language; no in-app picker

The app declares `en` + `cs`; iOS then offers Settings › GarminFood ›
Language automatically. The fiancée's Czech phone gets Czech with no setup;
the owner (phone also set to Czech) can pin English there. An in-app
`AppleLanguages` override is rejected: needs a relaunch anyway, does not
reach the widget extension (separate process, no App Group on a free
account), App Intents or system UI, and yields mixed-language screens.
Wave 6 adds one Settings row that opens `UIApplication.openSettingsURLString`.

### D2 — App + widget: String Catalogs

`ios/GarminFood/Resources/Localizable.xcstrings` and
`ios/GarminFoodWidget/Resources/Localizable.xcstrings` (widget has its own
because it's a separate bundle). Later `AppShortcuts.xcstrings` (Siri phrases
must live there, keyed with `${applicationName}`) and `InfoPlist.xcstrings`
(keys = plist key names). `Shared/` files are compiled into both targets, so
their strings must exist in **both** catalogs — the checker fails when a
`Shared/` literal is in one catalog but not the other.
Project settings: `options.developmentLanguage: en`; base build settings
`LOCALIZATION_PREFERS_STRING_CATALOGS: YES`, `SWIFT_EMIT_LOC_STRINGS: YES`;
Info.plist `CFBundleDevelopmentRegion: en`, `CFBundleLocalizations: [en, cs]`
for both targets.

### D3 — Packages: `.lproj` strings files, looked up via `bundle: .module`

Because plain `swift test` can't compile catalogs (Context), packages use
`Sources/<Target>/Resources/{en,cs}.lproj/Localizable.strings` (+
`Localizable.stringsdict` for plurals) and `resources: [.process("Resources")]`,
`defaultLocalization: "en"`. Code: `String(localized: "English source",
bundle: .module, comment: "…")`. This is the only format where CI can prove
Czech resolves in a package. `en.lproj` lists **every** key mapped to
itself (plus English plurals in `.stringsdict`): it must exist, or a phone
preferring English would get the only localization present — Czech — and
the checker enforces en/cs key parity. Revisit when SwiftPM CLI compiles
`.xcstrings` or package tests move to `xcodebuild test`; conversion is
mechanical.

The Wave 1 package tests fail loudly if the `.lproj` resources don't ship
under `swift test`. If that turns out to be a SwiftPM limitation rather
than a mistake, the fallback is `XCTSkip` with a clear message and moving
the assertion to the app's CI build (the "Show the app's compiled
localizations" step) — never a silently green test.

### D4 — Keys are the English source text

SwiftUI literals already are keys, so ~450 app/widget call sites need no
code change. Semantic keys (`String(localized: "nutrient.fat",
defaultValue: "Fat")`) only where one English string needs two Czech ones.
Every non-obvious key carries a `comment:` (placeholder meaning, what an
adjective agrees with, length budget).

Specifier mapping (catalog key must match what Swift generates exactly):
`Int` → `%lld`, `Double` → `%lf`, `String`/formatted text → `%@`.
Reordered placeholders use positional `%1$@`.

### D5 — Czech grammar rules

- Plurals always via catalog plural variations / `.stringsdict`
  (`one`/`few`/`many`/`other`), never `n == 1 ?` ternaries.
- No sentence assembly from translated fragments; one full localizable
  sentence per enum case (e.g. per meal type in notifications, per macro in
  challenge subtitles).
- Informal *ty* register; glossary in `docs/localization-glossary.md`
  (Wave 2).
- Adjectives carry a comment naming the noun they agree with
  (rarity → *odznak*, masculine).

### D6 — Persist ids, resolve text at render time

Stores already persist ids (achievements: id → unlock date). Keep it so: no
store may persist display text. Scheduled local notifications are the one
place text is frozen; `NotificationScheduler`'s diff must compare content
(title/body), not only ids, so a language change re-plans them (Wave 3).

### D7 — Numbers

`NumberDisplay`/`ServingAmount` use `String(format: "%.2f")` (always a dot).
Wave 6 switches display formatting to `FormatStyle` with the current locale
(decimal comma in Czech), keeping the non-trapping guarantees and existing
English output; tests pin both `en` and `cs` outputs with an explicit
`Locale`. Input already accepts `,` and `.` (`DecimalInput`).

### D8 — Adding a language later

Add the language to every catalog (script), a `<lang>.lproj` per package,
`CFBundleLocalizations` in `project.yml`, and the checker's language list
(which also carries the CLDR plural categories required per language). No
code change.

### D9 — QA pipeline (no Mac)

1. `tools/check-localizations.mjs` — blocking CI job (ubuntu, Node, seconds):
   JSON validity; each catalog key has a `cs` unit in state `translated`
   (`needs_review`/`new` fail); placeholder specifiers in `cs` equal the
   key's (multiset of types); `cs` plural variations include `one`, `few`,
   `other`; `.strings` files parse; `.stringsdict` entries exist for `en`
   and `cs` with the same keys; keys used by `Shared/` present in both
   catalogs. `--scan` reports Swift literals not in any catalog (report-only
   until Wave 6).
2. macOS job, non-blocking: `xcrun xcstringstool compile` on each catalog
   (Apple's own compiler); `xcodebuild -exportLocalizations -exportLanguage cs`
   uploaded as an artifact — the compiler-extracted, specifier-exact key list
   that translation work on Windows is done against.
3. Package unit tests: `cs` in `Bundle.module.localizations`; a known key
   resolves to its Czech text through the `cs.lproj` bundle; English lookups
   unchanged.
4. On-device: the fiancée's phone (Czech) after each wave.

### D10 — Coordination with in-flight changes

Wave 1 touches infrastructure plus a handful of smoke strings in files no in-flight
plan rewrites. Gamification copy is translated **after** each gamification
change merges (Wave 4), in its own small PR, never by editing a file another
open branch is changing. From Wave 1 on, `CLAUDE.md` requires new copy to be
localizable, so later changes arrive translation-ready.

## Risks / Trade-offs

- **Hand-typed keys drift from generated keys** (wrong specifier → English
  fallback, no error). Mitigated by D9.2's extracted key list and the
  on-device check; becomes blocking in Wave 6.
- **Two formats** (catalogs in app, `.lproj` in packages) — accepted for
  testability; the checker understands both.
- **`xcstringstool` CLI flags** are not documented publicly; the step is
  non-blocking until proven in CI.
- **Czech text is longer** — truncation in the Today hero, stat tiles and
  widget titles; Wave 6 pass plus `.minimumScaleFactor`/`lineLimit` review.
- **The owner's own phone switches to Czech** as soon as `cs` ships (it is
  set to Czech). He can pin English per app — called out in the Wave 2 PR.
