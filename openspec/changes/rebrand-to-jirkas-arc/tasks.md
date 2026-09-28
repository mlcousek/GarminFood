Every task ends with CI green: `swift test` for every package, the design-token
lint, the app and widget `xcodebuild`, and the `localization` job. Every new
`.swift` file starts with a header comment saying why it exists and what
depends on it. All new and changed user-facing text is in English and Czech
(Czech plural forms for counts). Branch `mlcousek/rebrand-to-jirkas-arc`,
one PR per wave. Relative size: S / M / L. Built in parallel with
`add-vault-connection`.

## 0. Owner decisions (before wave 2)

Each has a proposed default. If no answer arrives before the wave that
needs it, the default is built and marked *defaulted, owner may override*.

- [ ] 0.1 Icon concept: A (arc + "you are here" dot, default), B ("j" sweeping into the arc) or C (arc-shaped "A" with the dot as crossbar). Answer after seeing one rendered 1024 px PNG of each, attached to the PR (design D3).
- [ ] 0.2 Czech display name: "Jirka's Arc" unchanged (default) or a Czech form (design D2).
- [ ] 0.3 The fiancée's install: the same "Jirka's Arc" build (default), or a second CI artifact built with `APP_DISPLAY_NAME="Arc"` (design D2, D10).
- [ ] 0.4 Marketing version 2.0 (default) or 1.x (design D5).
- [ ] 0.5 Four tabs with food on Today (default), or five with a separate Food tab (design D6).

## 1. Wave 1 — Experience shell (pure logic first) (M)

- [ ] 1.1 AppearanceKit: `AppExperience` (`foodFirst`, `training`) and `AppShell` (`tabs(for:)`, `resolvedStartTab(stored:experience:)`); `StartTab.plan`. Tests `AppShellTests`: the food-first tab set equals today's three tabs in order; training is Today · Plan · Progress · Profile; resolved start tab for every stored value × experience, including an unknown string and `plan` in food-first.
- [ ] 1.2 AppearanceKit: `LayoutCatalog.today(for:)` and `specs(for:experience:)`; the training catalog equals the food-first one for now. Golden test: `today(for: .foodFirst)` equals the pre-change catalog exactly. Existing callers pass the current experience.
- [ ] 1.3 App: `AppRouter.Tab.plan`; `selectedTab` corrected to Today when the experience changes and the tab isn't shown; start tab from `AppShell.resolvedStartTab`.
- [ ] 1.4 App: `ContentView` builds its tabs from `AppShell.tabs(for:)`, each in its own `NavigationStack` with `withStatusBanners()`; Today's title "Food log" (food-first) or "Today" (training); Today's tab icon `fork.knife` or `sun.max`; Plan `calendar`.
- [ ] 1.5 App: `Plan/PlanTabView.swift`: the empty state only ("Your plan shows here once a vault is connected" plus a one-line explanation), built from the design-system `EmptyStateView`.
- [ ] 1.6 `Shared/GarminFoodDeepLink`: `plan` action with optional `date`; `AppRouter.handle(url:)` opens Plan in training and Today in food-first; the pending date is kept on the router for the Plan tab (consumed in `add-training-today-and-plan`). `logFood`, theme links and the barcode route unchanged. Parsing tests where the parser is pure.
- [ ] 1.7 Settings → Diagnostics: "Preview training shell (testing)" toggle (English only, developer surface), stored in `AppPreferences`; the app's experience input is `previewTraining` until `add-training-today-and-plan` adds the vault input.
- [ ] 1.8 Appearance → Layout: the "Start on" picker lists only the current experience's tabs.
- [ ] 1.9 Czech strings for every new key (tab title "Today"/"Dnes" is existing; "Plan", the empty state, the picker option). `node tools/check-localizations.mjs --scan` passes.
- [ ] 1.10 On-device: with the toggle off, the app is indistinguishable from the previous build (tabs, titles, Today order, start tab). With it on: four tabs, "Today" title, Plan empty state, `garminfood://plan` from Safari opens Plan, the barcode Control from the Plan tab still opens the scanner on Today.

## 2. Wave 2 — Name and version (M)

- [ ] 2.1 `project.yml`: `APP_DISPLAY_NAME: "Jirka's Arc"`, `MARKETING_VERSION: "2.0"`, `CURRENT_PROJECT_VERSION: "1"` in base settings; `CFBundleDisplayName: $(APP_DISPLAY_NAME)`, `CFBundleShortVersionString: $(MARKETING_VERSION)`, `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` in both targets' `info.properties`. No identifier changes; update the manifest's header comment (why display-name-only, D1).
- [ ] 2.2 `InfoPlist.xcstrings` (app and widget): `CFBundleDisplayName` with `shouldTranslate: false` and no Czech value (the widget's "Widget GarminFood" entry removed); `NSCameraUsageDescription` English value in `project.yml` and its Czech value name "Jirka's Arc".
- [ ] 2.3 `build.yml`: pass `CURRENT_PROJECT_VERSION=${{ github.run_number }}` to the archive step; add a non-blocking step that prints `CFBundleShortVersionString`/`CFBundleVersion`/`CFBundleDisplayName` from the archived app and widget `Info.plist`s. Record the first run's output (run number and printed values) here.
- [ ] 2.4 String audit (design D2): each of the 33 app-catalog and 15 widget-catalog keys naming GarminFood, FoodLogCore's challenge notification (`en`/`cs` `.lproj`), `LogNamedFoodIntent`'s `Summary`, `OpenBarcodeScannerIntent`'s type display name, the two widget accessibility hints and `ProfileView`'s fallback name: app → "Jirka's Arc", Garmin-the-service unchanged. New keys with Czech, old keys removed. PR description lists a grep showing no user-facing "GarminFood" left (comments and identifiers excepted).
- [ ] 2.5 Settings → About text (design D2) in both data modes.
- [ ] 2.6 FoodLogCore `BackupVault`: export file name `JirkasArc-backup-yyyy-MM-dd.json`; manifest marker unchanged. Test: the new name; a container written by the previous build (existing fixture) still passes `BackupCompatibility`.
- [ ] 2.7 `README.md` and `CLAUDE.md`: name the app "Jirka's Arc (repository, targets and identifiers still named GarminFood)"; keep every path as is.

## 3. Wave 3 — Icon and signature (M)

- [ ] 3.1 `tools/generate-app-icons.py`: record the current primary's corner colours as a `Teal` entry; add the one-time extraction of `tools/icon-src/by-jirka-mask.png` from the current primary (commit the mask); draw the chosen concept (0.1) procedurally at 4096 px and downsample; coverage = max(glyph, mask); write the primary `AppIcon-1024.png` and the 22 alternates (same names); keep `--check`. Update the script's docstring (why, inputs, outputs).
- [ ] 3.2 Run the generator on Windows, commit the PNGs, attach a contact sheet of all 12 icons to the PR for the owner's review; `--check` exits 0.
- [ ] 3.3 `DesignSystem/ArcMark.swift` (the `Shape`) and `AppSignatureView` using it with the existing gradient token; VoiceOver label "Jirka's Arc, by Jirka"; the onboarding welcome page shows `ArcMark` instead of any "GF" text. Design-token lint passes with no new allowlist entry.
- [ ] 3.4 On-device: every theme's icon from Settings → Appearance switches and shows the arc; the signature redraws on a theme switch; Dynamic Type at the largest size keeps the footer legible.

## 4. Wave 4 — Close-out (S)

- [ ] 4.1 CI green on every wave PR; `openspec validate rebrand-to-jirkas-arc --strict` passes.
- [ ] 4.2 Identifier check: confirm by diff that no bundle id, URL scheme, Keychain service, BG task id, store path, alternate icon name or card id changed.

## 5. On-device verification (owner, AltStore update in place)

- [ ] 5.1 Before updating: note the current icon choice, placed widgets and Controls, the sync queue count, and Settings → About.
- [ ] 5.2 After updating: the home screen says "Jirka's Arc" (untruncated) in English and in Czech; the chosen alternate icon shows the arc; all data present; Garmin still signed in (no sign-in banner); widgets and Controls still placed and working; About shows "2.0 (<run number>)". Record anything that had to be re-added.
- [ ] 5.3 Export a backup: the file is `JirkasArc-backup-<date>.json`; import an old `GarminFood-backup-…json`: the preview opens.
- [ ] 5.4 Siri: "Log the usual in Jirka's Arc" in English and the Czech phrase on a Czech phone. If Siri doesn't recognise the name, add `INAlternativeAppNames` (design Risks) and re-check.
- [ ] 5.5 The fiancée's phone (her next update): standalone, food-first, three tabs, nothing changed but the name, icon and version.
