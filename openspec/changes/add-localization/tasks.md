Every task ends with: CI green (`swift test` per touched package, app +
widget `xcodebuild`, localization check), and — where it changes visible
text — an on-device check on a phone set to Czech (the fiancée's). Each wave
is its own branch + PR (`mlcousek/add-localization-wN`).

## 1. Wave 1 — Infrastructure (no mass translation)

- [x] 1.1 `ios/project.yml`: `options.developmentLanguage: en`; base settings `LOCALIZATION_PREFERS_STRING_CATALOGS`, `SWIFT_EMIT_LOC_STRINGS`; `CFBundleDevelopmentRegion: en` + `CFBundleLocalizations: [en, cs]` in both Info.plists.
- [x] 1.2 `defaultLocalization: "en"` + `resources: [.process("Resources")]` in FoodLogCore and Gamification `Package.swift` (GarminKit only when it gets its first user-facing string, Wave 3).
- [x] 1.3 Catalogs: `GarminFood/Resources/Localizable.xcstrings`, `GarminFoodWidget/Resources/Localizable.xcstrings`; package `Resources/{en,cs}.lproj/Localizable.strings` (a `.stringsdict` is added per package with its first plural; the checker already validates them).
- [x] 1.4 Smoke strings end-to-end: app "Food log" title + "Level %lld" (no code change) and the `timeLeftText` plural (`String(localized:)`, Czech one/few/many/other); FoodLogCore `LogQuantity.invalidMessage`; Gamification `AchievementRarity.displayName`; widget "Log Food".
- [x] 1.5 `tools/check-localizations.mjs` (catalog JSON, Czech present + `translated`, specifier parity, Czech plural categories, `.strings`/`.stringsdict` parsing, `Shared/` keys in both catalogs, `--scan` report of unlocalized literals) + a blocking `localization` job in `build.yml`.
- [x] 1.6 Non-blocking macOS CI steps: `xcrun xcstringstool compile` per catalog; `xcodebuild -exportLocalizations -exportLanguage cs` uploaded as an artifact.
- [x] 1.7 Package tests: `cs` in `Bundle.module.localizations`, a Czech key resolves via the `cs.lproj` bundle (FoodLogCore, Gamification); English output unchanged.
- [x] 1.8 `CLAUDE.md` convention: new user-facing text localizable + translated from day one.
- [ ] 1.9 CI green on the Wave 1 PR; read the `-exportLocalizations` artifact and confirm the smoke keys (`Level %lld`, `%lld days left`) match the catalog exactly; record whether `xcstringstool compile` passed and make it blocking if so.
- [ ] 1.10 On-device: phone in Czech → Today title "Deník jídla", "Úroveň N", a challenge "Zbývají 3 dny", rarity "Legendární", widget gallery "Zapsat jídlo"; Settings › GarminFood › Language appears and switching to English reverts.

## 2. Wave 2 — App shell + most-used screens

- [x] 2.1 `docs/localization-glossary.md` (ty-form, domain terms: zapsat, série, úroveň, výzva, odznak, půst, jídlo/chod, porce). (Wave 6 added food/meal/preset terms and the VoiceOver-units and decimal-comma rules.)
- [x] 2.2 Tab bar, `ContentView`, `AuthBannerView`, `GarminErrorPresentation` (loud auth errors must be clear in Czech).
- [x] 2.3 Today (`TodayView`, `MealDetailView`, `DayNoteCard`, weight/hydration section): replace `n == 1 ?` ternaries and `+`-assembled accessibility labels with localizable strings/plurals.
- [x] 2.4 Log Food / search (`Catalog/*`), serving picker, barcode screen.
- [x] 2.5 Confirm + edit (`LogEntry/*`, `EntryEditing`), `MatchConfirmationView`. (Wave 6 closed the last confirm-screen literals: "When", "Date", "Confirm", "Choose…" and the save error.)
- [x] 2.6 Settings/Profile (sign-in, sync queue, diagnostics screen chrome — not log text).
- [ ] 2.7 Checker `--scan` clean for all Wave 2 files; on-device review with the fiancée.

## 3. Wave 3 — Remaining screens + FoodLogCore

- [ ] 3.1 Fasting, Hydration, Weight, Trends, Meal presets, Custom food, Home `MomentOverlay`.
- [x] 3.2 FoodLogCore display text: `NutrientKind`/`NutrientGroup`, meal type names, `CalorieBand`, `ServingAmount`/`LogEntryEditError`/`OfflineFoodIndex` errors, `CustomFood` note, `FastingSession`, `DayNote`.
- [ ] 3.3 `NotificationPlanning`: one full sentence per meal type (Czech accusative), fasting texts; `NotificationScheduler` diff compares title/body so a language change re-plans (spec: pending reminder).
  - [x] 3.3a Texts: every `NotificationPlanning` title/body is `String(localized:bundle: .module)` with en + cs `.lproj` entries; per-meal full sentences replace the `displayNameLowercased` insertion; the "eating opens in N minutes" body is FoodLogCore's first `.stringsdict` plural (Czech one/few/many/other). `LocalizationTests` pins a Czech meal title and the plural body.
  - [ ] 3.3b Scheduler diff: still identifier-only, so **already-pending notifications keep the text they were scheduled with** after a language change. Date-scoped meal/streak/challenge reminders self-heal with the next day's requests; the *repeating* fasting reminders keep the old language until their schedule or lead time changes. Fix: include title/body in the diff (remove + re-add when content differs).
- [x] 3.4 GarminKit: `defaultLocalization` + resources; `PersistedJSONUnreadFileError` text. GarminKit has `defaultLocalization: "en"`, `resources: [.process("Resources")]` and en/cs `.lproj`; `GarminKitTests/LocalizationTests` pins the Czech text.
- [x] 3.5 Tests pin Czech output for representative FoodLogCore strings via the `cs.lproj` bundle. (`LocalizationTests`: quantity message, meal reminder, fasting plural, nutrient/section names, an edit error, the custom-food note.)

## 4. Wave 4 — Gamification (after each gamification change lands)

- [ ] 4.1 Existing catalog: level tiers, rarity, daily challenges, challenge templates (per-macro/per-bucket full sentences instead of `rawValue` insertion), achievement families (title tables + plural subtitles), moments.
- [ ] 4.2 One follow-up task per merged gamification change (`add-gamification-signals`, `expand-gamification-depth`, `add-weekly-bingo`, `add-weekly-boss-and-streak-freezes`, `add-journeys-and-records`, `add-seasonal-events`, `add-secret-achievements`, `add-sport-and-body-achievements`) — translate its new strings in a small PR after it merges.
- [ ] 4.3 Test: every achievement/challenge id has a non-empty Czech title (catalog coverage test against the `cs.lproj` bundle).

## 5. Wave 5 — Siri, widget/Controls, Info.plist

- [x] 5.1 `GarminFood/Resources/AppShortcuts.xcstrings`: Czech phrases (with `${applicationName}`) and short titles; intent titles and `ActionError` texts in both catalogs (`Shared/`). Short titles, intent titles/descriptions/parameter titles, Siri dialogs and the `LogNamedFoodIntent` parameter summary (keyed `Log ${foodName} in GarminFood` -- the App Intents summary key format, unverified until the CI export/on-device check) are in `Localizable.xcstrings`; the ambiguous-match reply uses `.formatted(.list(type: .or))` instead of a glued `", or "`.
- [x] 5.2 Widget/Control names, labels and gallery descriptions (rewrite developer-facing "design.md D2" wording in both languages).
- [x] 5.3 `InfoPlist.xcstrings` for the app (`NSCameraUsageDescription`) and widget (`CFBundleDisplayName`). The app sets no `CFBundleDisplayName` of its own, so there is none to translate.
  - [ ] 5.3a TODO (CI): confirm XcodeGen puts both `InfoPlist.xcstrings` files in the Resources phase and the built `.app`/`.appex` contain `cs.lproj/InfoPlist.strings` (the "Show the app's compiled localizations" step). No build setting was changed; if they don't compile, the fallback is per-target `cs.lproj/InfoPlist.strings` files.
- [ ] 5.4 On-device: Siri Czech phrases, Shortcuts app, Control Center, camera prompt in Czech. Note: Czech is not a Siri voice language, so the Czech phrases surface in the Shortcuts app/Spotlight; spoken Siri uses the phrases of the Siri language (e.g. English) -- check what iOS actually shows.

## 6. Wave 6 — Polish

- [ ] 6.1 Locale-aware number display (`NumberDisplay`, `ServingAmount`, app `NumberFormatting`) via `FormatStyle`; tests pin `en` and `cs` output.
- [ ] 6.2 Plural audit: no `== 1 ?` ternaries left (checker rule).
- [ ] 6.3 Truncation pass: pseudo-localized build (+40 % length) sideloaded; fix Today hero, stat tiles, widgets, tab labels.
- [ ] 6.4 Accessibility labels/hints/values fully localized (units spelled out in Czech).
- [ ] 6.5 Settings row "Jazyk / Language" opening the per-app Settings page.
- [ ] 6.6 Promote checker `--scan` and the export-comparison to blocking.

## 7. Verify

- [ ] 7.1 `openspec validate add-localization --strict` passes.
- [ ] 7.2 Fiancée uses the app for a week in Czech; remaining awkward strings fixed; archive the change.
