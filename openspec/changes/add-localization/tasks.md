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

- [ ] 2.1 `docs/localization-glossary.md` (ty-form, domain terms: zapsat, série, úroveň, výzva, odznak, půst, jídlo/chod, porce).
- [ ] 2.2 Tab bar, `ContentView`, `AuthBannerView`, `GarminErrorPresentation` (loud auth errors must be clear in Czech).
- [ ] 2.3 Today (`TodayView`, `MealDetailView`, `DayNoteCard`, weight/hydration section): replace `n == 1 ?` ternaries and `+`-assembled accessibility labels with localizable strings/plurals.
- [ ] 2.4 Log Food / search (`Catalog/*`), serving picker, barcode screen.
- [ ] 2.5 Confirm + edit (`LogEntry/*`, `EntryEditing`), `MatchConfirmationView`.
- [ ] 2.6 Settings/Profile (sign-in, sync queue, diagnostics screen chrome — not log text).
- [ ] 2.7 Checker `--scan` clean for all Wave 2 files; on-device review with the fiancée.

## 3. Wave 3 — Remaining screens + FoodLogCore

- [ ] 3.1 Fasting, Hydration, Weight, Trends, Meal presets, Custom food, Home `MomentOverlay`.
- [ ] 3.2 FoodLogCore display text: `NutrientKind`/`NutrientGroup`, meal type names, `CalorieBand`, `ServingAmount`/`LogEntryEditError`/`OfflineFoodIndex` errors, `CustomFood` note, `FastingSession`, `DayNote`.
- [ ] 3.3 `NotificationPlanning`: one full sentence per meal type (Czech accusative), fasting texts; `NotificationScheduler` diff compares title/body so a language change re-plans (spec: pending reminder).
- [ ] 3.4 GarminKit: `defaultLocalization` + resources; `PersistedJSONUnreadFileError` text.
- [ ] 3.5 Tests pin Czech output for representative FoodLogCore strings via the `cs.lproj` bundle.

## 4. Wave 4 — Gamification (after each gamification change lands)

- [ ] 4.1 Existing catalog: level tiers, rarity, daily challenges, challenge templates (per-macro/per-bucket full sentences instead of `rawValue` insertion), achievement families (title tables + plural subtitles), moments.
- [ ] 4.2 One follow-up task per merged gamification change (`add-gamification-signals`, `expand-gamification-depth`, `add-weekly-bingo`, `add-weekly-boss-and-streak-freezes`, `add-journeys-and-records`, `add-seasonal-events`, `add-secret-achievements`, `add-sport-and-body-achievements`) — translate its new strings in a small PR after it merges.
- [ ] 4.3 Test: every achievement/challenge id has a non-empty Czech title (catalog coverage test against the `cs.lproj` bundle).

## 5. Wave 5 — Siri, widget/Controls, Info.plist

- [ ] 5.1 `GarminFood/Resources/AppShortcuts.xcstrings`: Czech phrases (with `${applicationName}`) and short titles; intent titles and `ActionError` texts in both catalogs (`Shared/`).
- [ ] 5.2 Widget/Control names, labels and gallery descriptions (rewrite developer-facing "design.md D2" wording in both languages).
- [ ] 5.3 `InfoPlist.xcstrings` for the app (`NSCameraUsageDescription`) and widget (`CFBundleDisplayName`).
- [ ] 5.4 On-device: Siri Czech phrases, Shortcuts app, Control Center, camera prompt in Czech.

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
