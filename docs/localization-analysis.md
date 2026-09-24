# Localization analysis — Czech first, more languages later

Date: 2026-09-24. Owner ask: *"my fiancée does not use English … introduce
multiple languages starting with Czech, but in future maybe more."*
Plan: [`openspec/changes/add-localization/`](../openspec/changes/add-localization/).

This document is the "why" behind that plan: where user-facing text lives
today, what makes Czech harder than a word-for-word swap, which Apple
mechanism to use given that **nothing here can be built on a Mac**, and the
rules new code must follow so we never have to do this sweep twice.

---

## 1. Inventory — where user-facing text lives

Counts are grep estimates (`node` scan of non-comment lines, 2026-09-24,
`origin/main` @ b117adf) — good for sizing, not exact.

| Module | Swift files | SwiftUI literal calls¹ | Interpolated strings² | Sentence-like literals³ | a11y label/hint/value | DiagnosticsLog calls (stay English) |
|---|---:|---:|---:|---:|---:|---:|
| `GarminFood/` (app) | 76 | ~428 | ~239 | ~333 | 78 | 11 |
| `GarminFoodWidget/` | 6 | ~17 | 0 | ~18 | 6 | 0 |
| `Shared/` (App Intents) | 6 | 0 | 1 | ~5 | 0 | 0 |
| `FoodLogCore` | 56 | 0 | ~47 | ~26 | 0 | 9 |
| `Gamification` | 22 | 0 | ~72 | ~320 | 0 | 0 |
| `GarminKit` | 14 | 0 | ~55 | 2 | 0 | 21 |

¹ `Text/Label/Button/navigationTitle/Section/Toggle/TextField/Picker/alert/…("…")`
² any `"…\(…)…"` — includes ids/cache keys/log lines, which are NOT user text.
³ literals that look like English words/sentences.

**Realistic translation volume: ~900–1,100 unique user-facing strings**,
roughly 45 % app UI, 35 % Gamification catalog content, 10 % FoodLogCore,
10 % widget/intents/Info.plist/notifications. The 8 in-flight gamification
changes (weekly bingo, boss, journeys, seasonal events, secret achievements,
…) will add several hundred more.

### 1.1 What localizes "for free" once a catalog exists (app + widget)

SwiftUI initialisers that take a **string literal** treat it as a
`LocalizedStringKey`: `Text("Food log")`, `Label("Log Food", systemImage:)`,
`Button("Save")`, `.navigationTitle(…)`, `.alert(…)`, `.confirmationDialog`,
`Section("…")`, `Toggle("…")`, `.accessibilityLabel("…")`,
`.configurationDisplayName`/`.description` on widgets and Controls. With
interpolation the key gets format specifiers: `Text("Level \(level.level)")`
→ key `Level %lld`. **No code change** — only a catalog entry. This is
most of the ~450 app/widget literal calls.

### 1.2 What does NOT localize automatically (needs code changes)

1. **`String` values built in code and shown via `Text(someString)`** —
   `Text(_: String)` is *verbatim*. Examples: `timeLeftText(until:)`
   (Progress), `MomentOverlay`'s titles, accessibility labels assembled with
   `+`, `"\(count.formatted()) products"`, `AuthBannerView`'s
   `"… entries haven't reached Garmin yet"`, ternaries like
   `Text(streak.length == 1 ? "day" : "days")`. Fix: `String(localized: "…")`
   at the point of construction (app target) or
   `String(localized: "…", bundle: .module)` (packages).
2. **Package-provided display text** (packages never import SwiftUI):
   - FoodLogCore: `NutrientKind.displayName` (~35 nutrients),
     `NutrientGroup.displayName`, `MealType` display names,
     `LogQuantity.invalidMessage`, `ServingAmount` validation text,
     `LogEntryEditError`, `OfflineFoodIndex` errors, `CustomFood`'s
     "Recorded in Garmin as …" note, `CalorieBand` descriptions,
     `FastingSession.displayName`, `DayNote.title`, **all notification
     titles/bodies in `NotificationPlanning`**.
   - Gamification: achievement titles/subtitles (~120 definitions, many
     generated from threshold tables), challenge templates (~54 titles),
     daily challenges (~12), level tiers (~20), `AchievementRarity`,
     moment copy.
   - GarminKit: only `PersistedJSONUnreadFileError.errorDescription`
     (user-visible via Settings); everything else is log text.
3. **App Intents / Siri** — `static var title: LocalizedStringResource`
   (already the right type), `ActionError.localizedStringResource`,
   and `AppShortcutsProvider` **phrases**, which Apple localizes from a
   separate `AppShortcuts.xcstrings` catalog (not `Localizable`), keyed with
   `${applicationName}` in place of `\(.applicationName)`.
4. **Info.plist** — `NSCameraUsageDescription`, `CFBundleDisplayName`
   (widget: "GarminFood Widget") → `InfoPlist.xcstrings`, keyed by the plist
   key name.
5. **Pending local notifications** carry text frozen at scheduling time. After
   a language switch they stay in the old language until re-planned
   (`NotificationScheduler` re-plans on every foreground, but diffs by id —
   the diff must also compare content, or language changes must force a
   full re-plan).

### 1.3 What must stay English

- `DiagnosticsLog` messages and categories (41 call sites) — they are for
  the developer/AI reading a copied log, and must be grep-able.
- Garmin/OFF wire values, ids, cache keys, `rawValue`s, file names.
- Food names from Garmin, Open Food Facts and the offline Czech index — they
  are data, shown as the source provides them (Czech products are already
  Czech; the owner's custom foods are whatever he typed). Search already
  handles Czech diacritics/stemming (`CzechDiacritics`, `CzechLightStemmer`).

### 1.4 Czech-specific traps found in the code

- **Sentence assembly from fragments breaks Czech grammar.** Examples:
  `"Log your \(mealType.displayNameLowercased)"` (Czech needs the
  accusative: *snídani*, *oběd*, *večeři*), `"Hit your \(macro.rawValue)
  goal on \(n) days"` (a raw English enum value inside a sentence),
  `"\(macroDisplayName(macro)) \(suffixes[i])"` for achievement titles.
  Rule: one full sentence per variant (switch over the enum, each case a
  complete localizable string), never a translated noun dropped into a
  translated frame.
- **Plurals: Czech has `one` / `few` / `many` / `other`** (CLDR): 1 den,
  2–4 dny, 5+ dní (and `many` = fractions: 1,5 dne). The verb can change too:
  *Zbývá 1 den / Zbývají 3 dny / Zbývá 5 dní*. Every `n == 1 ? "x" : "xs"`
  ternary (found in Today, Progress, Achievements' elephant/whale copy) must
  become a plural variation, never a ternary.
- **Gender/adjective agreement**: rarity names describe a badge (*odznak*,
  masculine) → *Běžný, Neobvyklý, Vzácný, Epický, Legendární*. Translators
  need a `comment:` saying what the adjective qualifies.
- **Length**: Czech runs ~15–30 % longer than English and has long compound
  words (*Sacharidy*, *Mononenasycené tuky*). Tight spots: the Today hero
  card, stat tiles, widget/Control titles, tab bar labels.
- **Informal "ty" vs formal "vy"**: a personal, playful app → informal *ty*
  (*Zapiš*, *Dosáhni*). Decide once, record it in the glossary.

## 2. Formatting — numbers, units, dates

- **Dates are already mostly right**: 50 call sites use `FormatStyle`
  (`.formatted(date:time:)`, `.dateTime.weekday(.wide)…`,
  `.relative(presentation: .named)`), which follows the app's resolved
  locale automatically — they will print *pondělí 24. září* and *před
  5 minutami* for free once Czech is a supported localization. The one
  `en_US_POSIX` formatter (`NutritionDayBoundary`) parses a wire date and
  is correct as is.
- **Numbers are NOT locale-aware today**: `NumberDisplay.quantity` and
  `ServingAmount` use `String(format: "%.2f")`, which always prints a dot.
  Czech expects a decimal comma (`0,70`). Fix in Wave 6 by switching to
  `value.formatted(.number.precision(.fractionLength(…)))` (or passing an
  explicit `Locale`), keeping `NumberDisplay`'s non-trapping guarantees.
  **Input** already accepts both separators (`DecimalInput`). Thousands
  separators: Czech uses a (narrow) no-break space — `FormatStyle` handles it.
- **Units**: `kcal`, `g`, `ml`, `kg`, `min` are the same in Czech; keep them
  outside translation where they are just symbols, but inside the string
  where word order matters (`"%lld kcal"` is fine either way). Spelled-out
  units in accessibility labels ("milliliters", "kilograms") need
  translating.
- **Weekday/month names** come from `FormatStyle` — never hardcode.
- **Time**: Czech uses 24 h; `.shortened` follows the device setting.

## 3. Language selection — follow the system, no in-app switcher

**Recommendation: follow iOS's per-app language setting; do not build an
in-app language picker.**

- Since iOS 13, once an app bundle contains ≥ 2 localizations, iOS shows
  **Settings › GarminFood › Language** automatically. The fiancée's phone
  (system language Czech) gets Czech with zero taps; the owner — whose phone
  is also set to Czech (see `DecimalInput`'s header) — can pin GarminFood to
  English in that same screen if he prefers.
- An in-app override (writing `AppleLanguages` to `UserDefaults`, or
  swapping bundles at runtime) is discouraged by Apple, needs an app
  restart anyway, does not reach the widget extension (separate process,
  no App Group on a free account — see CLAUDE.md), App Intents or Siri,
  and leaves system UI (share sheets, pickers, permission prompts) in the
  other language. Mixed-language UI is worse than either language.
- A Settings row "Language → opens `UIApplication.openSettingsURLString`"
  is the one piece of in-app UI worth adding (Wave 6), because users rarely
  know the per-app setting exists.
- **Widget, Controls, Siri** follow the system/per-app language on their own.

## 4. Mechanism — what to use and why

### 4.1 App + widget: String Catalogs (`.xcstrings`)

- One JSON file per table per target, all languages in one file, plural
  and device variations built in, and a per-string `state`
  (`translated` / `needs_review` / `new`) that a CI script can check.
- JSON is safe to hand-author/generate on Windows and diff in review.
- Xcode compiles `.xcstrings` into `cs.lproj/*.strings(dict)` during
  `xcodebuild` — which is exactly what CI runs for the app and widget.
- XcodeGen ≥ 2.39 puts `.xcstrings` in the Resources phase and **adds every
  locale found in a catalog to the project's `knownRegions`** (PR #1421), so
  no hand-maintained region list is needed; we still set
  `options.developmentLanguage: en` and declare `CFBundleLocalizations`
  explicitly in both Info.plists (belt and braces for the per-app Language
  setting and for system UI inside the app).
- Build settings set explicitly (XcodeGen-generated projects don't inherit
  Xcode 15's new-project defaults): `LOCALIZATION_PREFERS_STRING_CATALOGS
  = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`.

### 4.2 SPM packages: `.lproj/Localizable.strings` + `.stringsdict` — **not** String Catalogs (for now)

This is the one place the no-Mac constraint changes the textbook answer.

- `swift build` / `swift test` (plain SwiftPM, which is how CI tests the
  three packages) **does not compile `.xcstrings`** — only Xcode/xcodebuild
  does. Worse, a package whose only resource is an `.xcstrings` file has
  historically failed to get a `Bundle.module` at all under `swift build`
  (swiftlang/swift-package-manager#6993, FB13261704). Either outcome would
  make package translations untestable, or break all three `swift test`
  steps outright.
- Classic `cs.lproj/Localizable.strings` + `Localizable.stringsdict` are
  handled identically by SwiftPM CLI and Xcode, so `swift test` can
  **actually assert that Czech resolves** — the only automated proof we
  can get without a device.
- Package code uses `String(localized: "English source", bundle: .module,
  comment: "…")`; the app shows the resulting `String` verbatim.
- Revisit trigger: if a future SwiftPM compiles `.xcstrings` on the command
  line (or CI moves package tests to `xcodebuild test`), migrate each package
  to a catalog — a mechanical conversion `tools/` can script.

### 4.3 Keys: English source strings, not semantic keys

- SwiftUI already uses the literal as the key (`Text("Save")` → key `Save`),
  so English-as-key means **zero code churn** for ~450 call sites and a
  missing translation degrades to readable English, not `today.title`.
- Semantic keys are used **only** when one English string needs two
  translations (e.g. "Fat" the nutrient vs "Fat" in a title) — via
  `String(localized: "nutrient.fat", defaultValue: "Fat", …)`.
- Every new key gets a `comment:` when context isn't obvious (what a
  placeholder is, what an adjective qualifies, max length for a widget).

### 4.4 The hard part without Xcode: keys must match exactly

Xcode's catalog editor normally *extracts* keys from code. We can't open it,
so keys are hand-written — and a key typed as `Level %d` when SwiftUI
generates `Level %lld` silently falls back to English. Mitigations:

1. `tools/check-localizations.mjs` (Wave 1, blocking in CI): valid JSON;
   every key has a `cs` value in state `translated`; no `needs_review`/`new`;
   format specifiers in `cs` match the source key's specifiers
   (count and type); plural variations for `cs` cover `one`/`few`/`other`
   (and `many`, allowed); `.strings` files parse, and `.stringsdict` keys
   have matching `en` entries; a heuristic scan of Swift code for literal
   keys missing from the catalog (report-only at first).
2. CI step `xcodebuild -exportLocalizations` (Wave 1, non-blocking, uploads
   the `.xcloc` as an artifact): this runs the **real compiler-driven
   extraction**, so it is the authoritative list of keys the code produces,
   with exact specifiers — usable from Windows as the translation work list.
   Wave 6 promotes the comparison against it to blocking.
3. CI step `xcrun xcstringstool compile` on each catalog (non-blocking in
   Wave 1): proves each catalog compiles with Apple's own tool.
4. Package `swift test` assertions that Czech resolves (Wave 1).
5. On-device check with the phone set to Czech (every wave).

### 4.5 Specifier cheat-sheet (Swift interpolation → catalog key)

| Swift type interpolated | Key specifier |
|---|---|
| `Int` | `%lld` |
| `Double` | `%lf` |
| `String`, `Text`, formatted values (`x.formatted()`) | `%@` |
| `Date` inside `Text("\(date, style: .date)")` | `%@` |

Multiple placeholders → positional in translations (`%1$@`, `%2$lld`) when
Czech word order differs.

## 5. Quality assurance

- **CI checker** (above) blocks: missing/untranslated Czech, specifier
  mismatches, broken plural sets, invalid JSON.
- **Pseudo-localization** for truncation: Xcode's scheme option isn't
  available to us; instead the checker can emit an `en-XA`-style
  pseudo catalog (`[!!! Ďéšťíňáťíóň +40% !!!]`) into a throwaway branch for a
  sideloaded build (Wave 6). Cheaper alternative: review screenshots from
  the fiancée's phone on the smallest supported iPhone with the largest
  Dynamic Type size she uses.
- **Glossary** (`docs/localization-glossary.md`, Wave 2): *zapsat* (log),
  *série* (streak), *úroveň* (level), *výzva* (challenge), *odznak/úspěch*
  (achievement), *jídlo* (meal/food), *půst* (fasting), *ty*-form.
- **Native review**: the fiancée is the acceptance tester — each wave ends
  with her using the build for a day and reporting awkward strings.

## 6. Adding a third language later

1. Add a `"<lang>"` entry to every `.xcstrings` (script-generated, state
   `new`), and a `<lang>.lproj/` folder to each package's `Resources/`.
2. Add `<lang>` to `CFBundleLocalizations` in `project.yml` (both targets)
   and to the checker's `--languages` list. XcodeGen adds it to
   `knownRegions` from the catalogs automatically.
3. Translate until the checker is green. No code change: plural rules come
   from CLDR per language (e.g. Polish/Slovak/Ukrainian also use
   `few`/`many`; the checker's required-category table is per language).

## 7. Conflicts with in-flight work, and the rule for new code

In flight under `openspec/changes/`: 8 gamification changes (weekly bingo,
weekly boss & streak freezes, journeys & records, seasonal events, secret
achievements, sport & body achievements, gamification signals, expand
depth) plus theme and standalone-mode plans being written in parallel. All
of them add English copy, mostly in `Gamification` catalogs.

To avoid a merge war:

- **Wave 1 touches only infrastructure** plus a handful of smoke strings in files no
  in-flight change is rewriting.
- **Gamification content is translated per gamification wave, after it
  lands** (Wave 4), never by rewriting a catalog file another branch is
  editing.
- **Rule for all new code from Wave 1 onward** (added to CLAUDE.md
  Conventions):
  - UI copy in the app/widget: string *literals* in SwiftUI APIs (so they are
    keys), or `String(localized:)` when a `String` must be built. Never
    `Text(someEnglishString)` for fixed copy.
  - Package copy: `String(localized: "…", bundle: .module, comment: "…")`.
  - Persist ids, never display text; resolve text at render time.
  - No sentence assembly from translated fragments; no `n == 1 ?` plural
    ternaries — use plural variations.
  - Add the Czech translation in the same PR (the CI checker enforces it
    once a file has been migrated), or mark it `needs_review` with an
    English copy so it's visibly pending.
  - `DiagnosticsLog` stays English.

## 8. Recommendation summary

| Decision | Choice |
|---|---|
| Language selection | System / per-app Language setting; no in-app switcher; a Settings shortcut row |
| App + widget format | `Localizable.xcstrings` (+ `AppShortcuts.xcstrings`, `InfoPlist.xcstrings`) |
| Package format | `Resources/<lang>.lproj/Localizable.strings(dict)` via `bundle: .module` (revisit when SwiftPM CLI compiles catalogs) |
| Keys | English source text; semantic keys only for ambiguity |
| Register / tone | Informal *ty*, playful but clear |
| Numbers | `FormatStyle` everywhere; retire `String(format: "%.2f")` for display |
| QA | Node checker in CI (blocking) + `-exportLocalizations` artifact + `xcstringstool compile` + package tests + native speaker on device |
| New code | Localizable from day one (rule in CLAUDE.md) |

Sources consulted (2026-09-24): XcodeGen CHANGELOG / PR #1421 (xcstrings
support, locales → knownRegions); swiftlang/swift-package-manager#6993 and
Apple Developer Forums thread 739447 (SwiftPM CLI and `.xcstrings`);
elegantchaos.com "Localizable String Catalogues in Swift Packages"
(2026-02-12; `swift build` does not process catalogs).
