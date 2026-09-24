## 0. Owner decisions (before wave 2)

Answered 2026-09-24; see design.md "Revision 2026-09-24" (R1–R7).

- [x] 0.1 **Theme list.** 13 themes, each paired with an icon: GF Teal, Classic Coral, Ocean, Forest, Sunset, Slate (light + dark); Indigo Night, Berry, Graphite, Gold (dark only); Pastel, Citrus (light only); High Contrast (light + dark). Mono, Czech Autumn and Night Run dropped.
- [x] 0.2 **Default theme.** GF Teal is the new default for everyone (intentional visible change). Today's coral is the Classic Coral theme.
- [ ] 0.3 **Classic's contrast.** Not answered: Classic Coral stays pixel-identical (exemption list kept); Increase Contrast still fixes it.
- [ ] 0.4 **Per-person layouts on one phone.** Not answered yet (wave 3).
- [ ] 0.5 **Share codes.** Not answered yet (wave 5).
- [ ] 0.6 **"GF by Jirka" signature.** Not answered yet (wave 3).
- [ ] 0.7 **Tabs.** Not answered yet (wave 4).
- [x] 0.8 **Icon suggestion.** Replaced by a "Match app icon to theme" toggle, default on; the icon can still be chosen independently.
- [x] 0.9 **Dark-only themes.** Yes: Indigo Night, Berry, Graphite and Gold are dark only; Pastel and Citrus light only.
- [x] 0.10 **Wave order.** Waves 1 + 2 + the icon part of 5 + the single Appearance page first (branch `mlcousek/add-themes-and-icons`); layout editing (waves 3–4) later, after the gamification slot views land.

## 1. Wave 1: token refactor and theme store, no visual change (size: L)

- [x] 1.1 **Create `ios/AppearanceKit/`.**
  - `Package.swift`: iOS 17 / macOS 14, Foundation only, one library and a test target.
  - Add a "Run AppearanceKit unit tests" step to `.github/workflows/build.yml`, matching the other packages.
  - Add a `packages:` entry to `ios/project.yml`, plus a dependency from both the `GarminFood` and `GarminFoodWidget` targets.
  - Validate `project.yml` with PyYAML locally. CI green.
- [x] 1.2 **`ColorMath`**: `RGBA` and hex, sRGB↔linear, WCAG luminance and contrast, OKLab/OKLCH, `deltaE_OK`, Machado CVD matrices. Tests: 21:1 white/black, `#777777` 4.48:1, OKLab round trip, CVD on the primaries. CI green.
- [x] 1.3 **`ThemeRole`, `TokenValue` (`.rgb` / `.system(name)`), `ThemeSpec`, and the Classic spec with today's values** (design D3 table), including the band colors from `Components.swift`, `water` = carbs, and `danger` = system red. `ClassicIdentityTests` compares each value with the literals in `Theme.swift` and `Components.swift`. CI green.
- [x] 1.4 **`AppearanceSettings` v1** with lenient `Codable`, and `AppearanceMigration` (does nothing at v1). Tests: absent, missing fields, unknown enum values, extra fields, garbage. CI green.
- [x] 1.5 **`PaletteResolver` for Classic**, both schemes. Test that it resolves to today's values. CI green.
- [x] 1.6 **App theming plumbing** (revised by design R4: the `Theme.*` API is kept, no `ThemeColor`/`\.palette` migration):
  - `Shared/ThemeRuntime.swift`: `ThemePalette` (dynamic light/dark `UIColor`-backed `Color`s) and the `@Observable` `ThemeRuntime.shared` that `Theme.*` tokens read
  - `ThemeStore` (`@MainActor @Observable`)
  - `AppPreferences` key `appearance.v1` plus quarantine and a `DiagnosticsLog` warning (`AppPreferences+Appearance.swift`)
  - register the store in `AppEnvironment`
  - a root `.themed(store)` in `ContentView` that replaces `.tint(Theme.accent)`

  Every new file gets a header comment. CI green.
- [x] 1.7 **Migrate `DesignSystem/`** to palette roles: `CardStyle`, `ProgressRing`, `MacroBar`, `PrimaryButton` (label uses `onAccent`), `StatTile`, `DaySwitcher`, `Tag`, `FavoriteToggleButton`, `GoalState.tint`, and `CalorieBand.tint` (whose literals move into Classic). `BadgeMedallion` rarity colors stay as they are. CI green.
- [x] 1.8 **Migrate batch A** (R4: only hard-coded colors are edited): `Today/`, `Fasting/`, `Weight/`, `Hydration/`. Hydration moves from `carbs` to `water`. CI green.
- [x] 1.9 **Migrate batch B**: `Catalog/`, `LogEntry/`, `CustomFood/`, `MealPreset/`, `Shortcuts/`. The 9 `.red` error texts become `danger`, and the `.green` swipe tint becomes `success`. CI green.
- [x] 1.10 **Migrate batch C**: `Progress/`, `Trends/`, `Profile/`, `Home/` (`MomentOverlay`), `App/` banners. Text on colored fills uses `onAccent`. CI green.
- [x] 1.11 **Lint**: `tools/lint-design-tokens.sh`, plus `tools/design-token-allowlist.txt` with a reason on every line (`Shared/Theme.swift`, `BadgeMedallion` rarity, scanner and moment scrims, the widget fallback). Run it locally in Git Bash until it passes, then add it as a CI step before "Install XcodeGen". CI green.
- [ ] 1.12 **On-device check** (AltStore build):
  - Take screenshots of Today, Log Food, Progress, a confirm sheet, the level-up overlay and Settings in light and dark mode, and compare them with screenshots from the previous build. They must look identical.
  - Settings → Diagnostics shows no `appearance` warnings.
  - Record the result here.

## 2. Wave 2: built-in themes, appearance and style options (size: M)

- [x] 2.1 **`ThemeCatalog` built-ins** (R2) as data: the Legible and CVD-safe macro and state sets and the 13 themes, brand colors from their icons, fitted by the resolver (R3). `BuiltInThemeContrastTests` and `DistinctnessTests` (D5) run over every theme, scheme and contrast mode, with Classic's closed exemption list. Record any value nudged to pass in the catalog comment. CI green.
- [x] 2.2 **`PaletteResolver` steps 2 to 5** (D4): the macro set override, Differentiate Without Color mapped to CVD-safe, increased contrast (Classic included), and `onAccent` derivation. Tests. CI green.
- [x] 2.3 **`AccentAdjuster`** plus the custom accent in the settings. Tests: coral in light is fitted with the hue kept, a passing color is unchanged, `#FFFF00` terminates, lime is darkened. Also test the macro-collision warning. CI green.
- [x] 2.4 **Settings → Appearance screen** (`Profile/Appearance/`, structure per R6, including the app icon grid and a disabled "Customize layout — Coming soon" row):
  - a theme gallery grid of live mini previews (a small summary ring and macro bars drawn with that theme's palette)
  - an appearance picker (with Light and System hidden for dark-only themes)
  - custom accent: `ColorPicker(supportsOpacity: false)` plus curated swatches, the "Adjusted for light/dark mode" note, and the collision warning
  - a "Fine-tune" section
  - a "Reset all appearance" action

  Add a row for it in `SettingsView`. CI green.
- [ ] 2.5 **Style options** (D6):
  - Card styles: Filled, Elevated, Outlined, Glass. Glass falls back to Filled under Reduce Transparency, and outlined borders are 2 pt under Increase Contrast.
  - Corner scale.
  - Container-level density.
  - Number font through `.numberStyle()` and `.fontDesign`.
  - Make `heroNumber` and the Level 48 pt number `@ScaledMetric`.
  - *Status:* card styles, corners, container density (Today/Progress stacks, card padding) and number font are built (`CardStyle`, `Theme.Radius`, `Theme.Density`, `Font.heroNumber` etc. read `ThemeRuntime`). **Still open:** the `@ScaledMetric` hero/Level numbers (needs call-site edits in Today/Progress files other agents are translating; do after those land).

  CI green.
- [x] 2.6 **Optional Today gradient header** (off by default), with the Reduce Transparency flat tint. Add a contrast test of `.primary` against the blended stops. CI green.
- [ ] 2.7 **Per-theme appearance** applied through `.preferredColorScheme` at the root. Any presenter found not inheriting the palette gets an explicit `.themed(store)`. CI green.
- [ ] 2.8 **On-device check**:
  - Go through every theme in light and dark: Today, Log Food, the confirm sheet, Progress, the level-up overlay, alerts.
  - Repeat with Increase Contrast, Reduce Transparency, Differentiate Without Color and the largest Dynamic Type.
  - Check VoiceOver on the gallery and the accent picker.
  - Confirm that sheets and the overlay follow the theme.
  - Record the result here.

## 3. Wave 3: Today card registry and edit layout (size: L)

- [ ] 3.1 **AppearanceKit layout model**: `TodayCardID`, `LogFoodShelfID`, `ProgressCardID`, `CardSpec` catalogs, `CardPlacement`, `ScreenLayout`, `LayoutConfig` v1 (lenient `Codable`), `LayoutResolver` (D8 rules 1–6), and `LayoutPreset` (Full, Minimal, Athlete). `LayoutResolverTests` includes a golden default order per screen that equals today's code, and a round trip with a card unknown to this build. CI green.
- [ ] 3.2 **`LayoutStore`** (`@Observable`), `AppPreferences` key `layout.v1` plus quarantine (`AppPreferences+Layout.swift`), registered in `AppEnvironment`. CI green.
- [ ] 3.3 **`TodayView` renders the resolved order** through one `@ViewBuilder switch` over `TodayCardID`. The existing show-when conditions (today and non-empty, fasting enabled) move into `availability(_:)` unchanged. CI green.
- [ ] 3.4 **Variants**: summary `compact` and `hero`, `MealSectionCard` `collapsed`, and Weight & Water `weight` / `water`. CI green.
- [ ] 3.5 **`LayoutEditorSheet`** (generic over a screen):
  - `List` with `onMove` and edit mode active
  - visibility toggles, variant menus, greyed rows with their reason, locked pinned rows
  - the Presets menu, Reset with confirmation plus in-session Undo, and Done
  - `.presentationDetents([.medium, .large])` plus background interaction, for the live preview
  - VoiceOver labels and Move actions

  CI green.
- [ ] 3.6 **Entry points**: an "Edit layout…" item in Today's toolbar menu, and Settings → Appearance → Layout → Today. CI green.
- [ ] 3.7 **Banners card**: if `add-gamification-signals` has merged, the `banners` card hosts `TodaySlotHost()` above `meals`. If it hasn't, leave the case returning `.unavailable` and make this a one-line follow-up in whichever change merges second. CI green.
- [ ] 3.8 **On-device check**:
  - An upgrade with nothing stored shows the same order.
  - Drag and hide persist across a relaunch.
  - The live preview updates behind the half-height sheet.
  - Each preset looks right.
  - Reset and Undo work.
  - VoiceOver reorder works.
  - Collapsed meals open their detail.

  Record the result here.

## 4. Wave 4: Log Food shelves, Progress sections and start tab (size: M)

- [ ] 4.1 **`FoodCatalogView` shelves** render through a `ForEach` over the resolved `LogFoodShelfID` order. The picker-mode, `pickBackingFood` and empty-shelf rules stay as availability. Search results are untouched. Add the editor entry at Settings → Appearance → Layout → Log Food. CI green.
- [ ] 4.2 **`ProgressHomeView`** renders the resolved `ProgressCardID` order, with each gamification slot view as its own entry, replacing the single `ProgressSlotHost()` call. Slot files stay untouched. The default order is today's order plus D12's slot block under Level. Add the editor entry at Settings → Appearance → Layout → Progress. *Precondition:* `add-gamification-signals` has merged; if it hasn't, ship the built-in cards only and add the slots in a follow-up. CI green.
- [ ] 4.3 **Start tab** (`LayoutConfig.startTab`): `AppRouter`'s initial selection reads it at launch, and deep links and widget routes keep priority. It's set in Settings → Appearance → Layout. CI green.
- [ ] 4.4 **On-device check**:
  - Shelf order persists.
  - Picker modes still hide the Meals shelf.
  - Hiding Bingo keeps Boss.
  - The start tab is honored from the icon but not from the widget.

  Record the result here.

## 5. Wave 5: icons, sharing and widgets (size: M)

- [ ] 5.1 **Precondition: confirm `add-app-icon-picker` 4.2 on device.** Does `setAlternateIconName` work on an AltStore-signed build, and does it survive a 7-day re-sign? Record the result. If it fails, skip 5.2 and 5.3 and note why.
- [ ] 5.2 **Replace the alternates (R5)**: remove Streak, Macro, Midnight, Mint and Pastel; add the 11 GF-style icons (Indigo, Sunset, Forest, Pastel, Slate, Citrus, Ocean, Coral, Berry, Graphite, Gold) as @2x/@3x in `GarminFood/AppIcons/`. Update `project.yml` `CFBundleAlternateIcons` (validated with PyYAML), `AppIconOption`, and `ThemeSpec.iconName`. Reset a stale removed alternate to the primary icon on launch. CI green.
- [ ] 5.3 **Icon follows theme** (R5): a "Match app icon to theme" toggle, default on; picking a theme switches the icon when it's on. CI green.
- [ ] 5.4 **`ThemeShareCode`** (AppearanceKit), D11. Tests: round trip, prefix, tampered payload, 2 KB cap, unknown theme, accent re-fit, layout merge. CI green.
- [ ] 5.5 **Share UI**:
  - Export: `ShareLink` with the code and `garminfood://theme?c=…`, plus a QR code from `CIQRCodeGenerator`.
  - Import: `PasteButton` and an `AppRouter` route, both leading to a preview sheet with Apply and Cancel.

  CI green.
- [ ] 5.6 **Widgets**: `WidgetThemeIntent` with a `WidgetThemeOption` `AppEnum`, and `AppIntentConfiguration` for `GarminFoodHomeWidget` and `GarminFoodStreakWidget`, keeping their `kind`s and the `.never` timeline. The gradient resolves from `ThemeCatalog`. Add the Settings footnote explaining that widgets are themed per widget. CI green.
- [ ] 5.7 **On-device check**:
  - A code shared from the owner's phone and applied on the fiancée's phone.
  - Invalid-code handling.
  - An existing widget is still coral after the update.
  - Edit Widget → Forest works.
  - The icon prompt behaves in both Ask and Never modes.

  Record the result here.
