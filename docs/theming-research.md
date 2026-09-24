# Theming and layout research

Research for the owner's request: *"the look of the app — can you introduce
themes and customizable screen, like colors, like layout? do also research
and plan for this"*. The plan built from this lives in
[`openspec/changes/add-themes-and-layout/`](../openspec/changes/add-themes-and-layout/).

Read on 2026-09-24 against `origin/main` @ `b117adf`. All numbers below come
from reading the code or from the contrast script described in §5. Nothing
here touched Garmin.

---

## 1. How the app is styled today

### 1.1 Tokens (`ios/Shared/Theme.swift`)

`Theme` is a caseless `enum` of `static let` values. It lives in `Shared/`,
so the app **and the widget extension** both compile it.

| Group | Tokens | Notes |
|---|---|---|
| Brand | `accent` `#F56B4A` (coral), `accentDeep` `#CC452E` | The header comment says coral was chosen on purpose so the app never reads as an official Garmin surface. |
| Macros | `carbs` `#4A8FE3`, `protein` `#8C66DB`, `fat` `#EDB033` | "One hue per macro, used consistently." |
| States | `success` `#33AD73`, `warning` `#E69921`, `over` `#C7527A`, `grace` `#8C9EB2`, `ember` `#FA8C29` | `over` is a muted red-violet on purpose ("information, not a failure"). |
| Gradient | `flameGradient` (ember to accent) | Used for the streak flame. |
| Surfaces | `cardBackground`, `groupedBackground`, `heroBackground` | These wrap UIKit semantic system colors, so they already adapt to light and dark mode. |
| Spacing | `xs 4, sm 8, md 16, lg 24, xl 32` | |
| Radius | `sm 8, md 14, lg 20, xl 28` | |
| Motion | `confirmAnimation(reduceMotion:)` | Falls back to a 0.12 s ease when Reduce Motion is on. |
| Type | `Font.foodTitle/foodSubtitle/macroBadge/sectionHeader/heroNumber/heroUnit/streakNumber/streakLabel/macroValue` | Numbers use `.rounded` with monospaced digits. |

Every brand and state color is a **single fixed sRGB value**. The same coral
is used in light and dark mode. Only the surfaces adapt, because they come
from the system.

### 1.2 Components (`ios/GarminFood/DesignSystem/`)

- `Components.swift`:
  - `CardStyle` / `.card()`: padding plus `heroBackground` in a continuous `RoundedRectangle(cornerRadius: Radius.lg)`. There's no shadow and no stroke. It's used 34 times across 13 files.
  - `GoalState.tint(base:)` maps a goal state to a color.
  - `CalorieBand.tint` is the stepped color scale for the home ring. It holds the only two colors not defined as tokens: yellow `#F5C92E` and red `#DB3D3B`.
  - `ProgressRing` (track `primary.opacity(0.08)`), `MacroBar`, `PrimaryButton` (`.borderedProminent.tint(Theme.accent)`), `StatTile`, `DaySwitcher`, `EmptyStateView`, `FoodListRow`, `Tag`.
- `BadgeMedallion.swift` has hard-coded rarity gradients (bronze, silver, gold and so on). **These should stay fixed.** Rarity colors carry meaning, the way a gold medal does. A theme shouldn't turn a legendary badge teal.
- `AppSignatureView.swift` is the "GF by Jirka" signature at the bottom of Today. It uses a fixed 15 pt rounded font.

### 1.3 How tokens are referenced across screens

`Theme.` is referenced from 44 of the 88 Swift files in the app, widget and Shared targets.

| Token | Uses |
|---|---|
| `Spacing.sm/xs/md/lg/xl` | 77 / 65 / 46 / 19 / 4 |
| `accent` | 42 (+2 `.opacity`) |
| `warning` | 21 (+2) |
| `success` | 14 (+1) |
| `carbs` | 12 (+1). **This includes hydration, which borrows `carbs` as its "water" color** (`HydrationComponents.swift`, `AddHydrationSheet.swift`). That means a water token is missing. |
| `groupedBackground` | 7 |
| `ember` / `flameGradient` | 6 / 5 |
| `Radius.*` | 13 total. No literal `cornerRadius: <number>` appears anywhere, which is good. |

Colors that bypass the tokens, all of which need migrating or an explicit allowlist entry:

- 9× `.foregroundStyle(.red)` for inline error text in sheets (`AuthBannerView`, `MatchConfirmationView`, `CustomFoodEditorView`, `AddHydrationSheet`, `AddWeightSheet`, `LogEntryConfirmView`, `MealPresetConfirmView`, `MealPresetEditorView` ×2). A `danger` token is missing.
- `.tint(.green)` on a swipe action (`EntryEditing.swift:100`).
- `.white` / `.black` over camera or scrim (`BarcodeScanScreen`, `MomentOverlay`) and over colored fills (`SettingsView:70`, `ProgressViews:398/402`, `ProfileView:121`, both widgets). Scrims are legitimately fixed. Text on a colored fill should use a derived `onAccent` color instead.
- 7 `Color(red:…)` literals outside `Theme.swift`: 5 in `BadgeMedallion` (keep them) and 2 in `CalorieBand.tint` (move them to tokens).
- 11 ad-hoc `design: .rounded` fonts. These are relevant to a "number font style" setting.
- 16 fixed `.font(.system(size:))` calls. Several are icon glyphs, which is fine. **`Font.heroNumber` (72 pt, used by the Weight and Hydration heroes) and the Level detail's 48 pt number don't scale with Dynamic Type.** That's an existing accessibility gap.

### 1.4 Appearance and accessibility today

- **Dark mode**: the app follows the system. No `preferredColorScheme` is set anywhere, and there's no `UIUserInterfaceStyle` in the plist. Surfaces adapt through system colors. Brand colors don't adapt.
- **Tint**: `ContentView` applies `.tint(Theme.accent)` at the `TabView`. There's **no `AccentColor` asset** in `Assets.xcassets`, so system controls outside that tree (for example alerts) use the default blue.
- **Dynamic Type**: text styles are used almost everywhere. Only 9 `@ScaledMetric` usages exist, and the gaps are listed above.
- **Reduce Motion**: respected in `confirmAnimation`, `ProgressRing`, `MacroBar`, `ProgressStrip` pulse and `MomentOverlay`.
- **Reduce Transparency, Increase Contrast, Differentiate Without Color**: **not read anywhere.** There's only one material, `MomentOverlay` `.regularMaterial` (the system handles Reduce Transparency for that one), plus `.thinMaterial` on the scanner.
- **Contrast**: see §5. The current light-mode palette misses WCAG thresholds in several places.

### 1.5 Icons and the asset catalog

- Primary icon: `AppIcon.appiconset/AppIcon-1024.png`, a single 1024 px universal image. **Since PR #37 it's a navy-to-cyan teal gradient with a white "GF / by Jirka"**, while the in-app accent is still coral. The icon and the app no longer share a color. A "GF Teal" theme would close that gap.
- 5 alternate icons (PR #27, `add-app-icon-picker`): Streak, Macro, Midnight, Mint, Pastel. They're loose `@2x`/`@3x` PNGs in `GarminFood/AppIcons/`, registered via `CFBundleIcons.CFBundleAlternateIcons` in `project.yml`. `AppIconPickerView` in Settings calls `setAlternateIconName`.
  - The alternates were designed around the **old coral primary**, so they now match neither the teal icon nor any planned theme.
  - Their tasks 4.1 and 4.2 (CI build, and on-device switching) are **still unchecked**.
  - Loose-file alternates can't carry iOS 18 dark or tinted variants. Only asset-catalog app icon sets can (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` / "include all app icon assets").
- `project.yml`: `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, deployment target iOS 17.0, iPhone only.

### 1.6 Widget styling (`ios/GarminFoodWidget/`)

- `GarminFoodHomeWidget` (Log Food, `systemSmall`) and `GarminFoodStreakWidget` both use `StaticConfiguration`, white text over a `LinearGradient(Theme.accent, Theme.accentDeep)` / ember `containerBackground`, and `.widgetAccentable()` on the glyph.
- Lock-screen widgets use system styling.
- Controls (`QuickPickControls`, `ScanBarcodeControl`) are system-rendered: only a symbol and a title, with no color control.

---

## 2. Screen structure: what could be reordered or hidden

### 2.1 Today (`Today/TodayView.swift`), in order

| # | Block | Shown when | Candidate variants |
|---|---|---|---|
| 1 | `DaySwitcher` | always | none (pinned: it's navigation) |
| 2 | `DaySummaryCard`: ring (132 pt scaled), consumed/goal, macros, active kcal | always | ring large / compact row / hero number |
| 3 | `ProgressStrip`: streak flame and level, taps to the Progress tab | always | full / compact |
| 4 | `FastingHomeSection` | fasting enabled | none |
| 5 | Meal cards (`MealSectionCard` per meal) | always | expanded (today) / collapsed (header, kcal and macros only) |
| 6 | "Log again" (`QuickPickShelf`) | today and non-empty | none |
| 7 | "Log a meal" (`MealPresetShelf`) | today and non-empty | none |
| 8 | "Weight & Water" (`TodayWeightCard` + `TodayHydrationCard`) | always | both / weight only / water only |
| 9 | `DayNoteCard` | always | none |
| 10 | `AppSignatureView` | always | none (pinned last) |

Planned additions from in-flight changes: `TodaySlotHost` with `SeasonalBannerSlot` and `BossBannerSlot`, "above the meals list" (`add-gamification-signals` D12, owned by the seasonal and boss changes).

### 2.2 Log Food (`Catalog/FoodCatalogView.swift`)

With no query there are five shelves in a fixed order: Quick pick, Favorites, "Usual for <meal>", Meals (presets), Recent. After those comes the "Your custom foods" list. Each shelf already hides when empty or in picker modes. These are all `List` sections built by `shelfSection(title:)`, so reordering them is a `ForEach` over an ordered ID list.

### 2.3 Progress (`Progress/ProgressViews.swift` `ProgressHomeView`)

Fixed order: Streak, Level, Challenges, Achievements, Weight, Hydration, Trends, "Goals, last 14 days".

`add-gamification-signals` D12 adds `ProgressSlotHost()` "under the level card", with 8 slot views in a fixed order: Boss, Bingo, Seasonal, Journeys, Records, Collections, SportBody, Secrets. Wave-2 and wave-3 changes each fill **only their own slot file** ("May touch: none"). That's the seam a layout registry can plug into without editing any of those plans (§4).

### 2.4 Tabs (`ContentView.swift`)

There are three tabs: Today, Progress, Profile, and `AppRouter.Tab` drives them. Settings lives under Profile, so Profile can never be hidden. Reordering three tabs has little value. **Picking the tab the app opens on** is the useful part.

---

## 3. iOS 17 capabilities and constraints

| Topic | Finding | Consequence |
|---|---|---|
| Color scheme | `.preferredColorScheme(_:)` on the root view applies to the whole window, including sheets. `nil` means follow the system. | The per-app "Light / Dark / System" setting is one root modifier. |
| Tint | `.tint(_:)` accepts any `ShapeStyle`, and the root tint already exists. | Swapping it is free. An `AccentColor` asset would be a *static* fallback only, so don't add one. |
| Environment-driven colors | A custom `EnvironmentKey` holding a `ThemePalette` value at the root is idiomatic. **iOS 17 also added `ShapeStyle.resolve(in: EnvironmentValues)`**, so a custom `ShapeStyle` can look up the current palette at render time. | `.foregroundStyle(Theme.accent)`-style call sites can keep their shape. Only sites that need a concrete `Color` (gradients, `ProgressRing(tint:)`, `.opacity` math) read `@Environment(\.palette)`. |
| Dynamic `UIColor` + custom `UITrait` (iOS 17) | Possible (`UITraitDefinition` bridged to SwiftUI via `UITraitBridgedEnvironmentKey`), but how SwiftUI resolves `Color(uiColor:)` against a custom trait can't be checked without a device or simulator. | Rejected as the primary mechanism: it's too clever to verify on this pipeline. |
| Performance | A theme change invalidates every view that reads the palette, which is fine because it's rare and user-initiated. Per-frame work is unchanged: the palette is a small `Equatable` struct of precomputed `Color`s, never computed in `body`. `@Observable` stores only re-render the views that read the property that changed. | Keep the palette a value in the environment, and layout state in an `@Observable` store. |
| Persistence | `AppPreferences` (an `@Observable` class over `UserDefaults.standard`) is the established pattern: keyed values, `defaults.object(forKey:) as? T ?? default`. `@AppStorage` isn't used anywhere. | Store the appearance and layout as **versioned JSON `Data` blobs** under new keys. A missing or undecodable blob means the default, which is today's look. |
| Alternate icons | `UIApplication.setAlternateIconName(_:)` needs **no entitlement or capability**. It depends only on `CFBundleAlternateIcons` in the Info.plist, so nothing about a free Personal Team or AltStore signing blocks it in principle. The mechanism is **already in the app** (PR #27) but still **unverified on a device** (tasks 4.1 and 4.2 are open). iOS always shows its own "You have changed the icon" alert, which can't be suppressed legitimately. Only the user can change the icon: it can't be done silently when a theme is picked. | Themes may *suggest* a matching icon ("Also switch icon?") and call the existing API. First, finish verifying PR #27 on a device. |
| Icon variants | Asset-catalog alternates (Xcode 13+, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` or `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: YES`) support iOS 18 dark and tinted appearances. Loose files don't. | Optional migration. It's risky without Xcode to preview, so it's gated behind the PR #27 device check. |
| App ID quota | AltStore allows about 10 new App IDs per week. Every new target costs one. | **No new targets.** A widget moving from `StaticConfiguration` to `AppIntentConfiguration` keeps the same `kind` and extension, so it costs no App ID. |
| Widgets without App Groups | The widget process **can't read the app's `UserDefaults`**, so it can't follow the in-app theme. **`AppIntentConfiguration` (iOS 17) with a `WidgetConfigurationIntent` parameter backed by an `AppEnum` of theme IDs is stored by the system per widget instance.** No shared container is involved. | Each widget can get its own "Theme" picker (long-press → Edit Widget), defaulting to Classic. It's honest, it works, and the widget just won't change automatically when the app theme changes. iOS 18 tinted and clear Home Screen modes already restyle via `.widgetAccentable()` / `widgetRenderingMode`. |
| Controls | Controls render as system chrome, with only symbol and title. | Out of scope. |
| Drag to reorder | `List` + `ForEach.onMove` + `EditMode.active` (`.environment(\.editMode, .constant(.active))`) gives native drag handles, VoiceOver "Move up/down" actions and haptics for free. Free-form drag inside a `ScrollView`/`VStack` needs custom `.draggable`/`.dropDestination`, with no VoiceOver reorder and fiddly auto-scroll. | Use the List-based editor. |
| Live preview | `.presentationDetents([.medium, .large])` + `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` (iOS 16.4) keeps the screen underneath visible and live while a sheet is open. | "Edit layout" is a half-height sheet over the real Today screen, which updates as you drag. That's a real preview with no mock renderer. |
| Materials | `.regularMaterial` / `.thinMaterial` and friends automatically become opaque under Reduce Transparency. iOS 26's Liquid Glass `.glassEffect()` needs the iOS 26 SDK. | A "Glass" card style uses materials over a tinted or gradient background. `.glassEffect` would be an `#available` extra only if CI's Xcode has the SDK. |
| SF Symbols | `.symbolRenderingMode(.hierarchical/.palette/.multicolor)` can follow the palette through `foregroundStyle` layers. | Themed symbols come for free once call sites use palette styles. |
| Accessibility env | `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `colorSchemeContrast` (`.increased`), `accessibilityDifferentiateWithoutColor`, `dynamicTypeSize` | All are readable at the root and folded into the resolved palette and style (§5). |
| Sharing text | `ShareLink(item: String)` exports. **`PasteButton` imports without the "Allow Paste" prompt** that reading `UIPasteboard` programmatically triggers. `.onOpenURL` is already routed through `AppRouter`. | Theme codes can travel as text, as a `garminfood://theme?c=…` link, or as a QR code, with no server involved. |

---

## 4. Interplay with in-flight plans

- **`add-gamification-signals` D12** creates `ProgressSlotHost` (8 slot views in a fixed order) and `TodaySlotHost` (2 banner slots). The layout registry **reuses those slot views as registry entries**, keyed by the same feature names. The fixed order D12 declares becomes the *default order*. The host file is edited once, after wave 1 merges, to read its order from the layout store. **Wave-2 and wave-3 changes don't change**: they still fill their own slot file, and their card then shows up in the editor automatically. A slot whose feature has nothing to show still renders `EmptyView`, so the registry also asks it "have content?" through an availability flag.
- **`add-standalone-mode`** (being planned in parallel, branch `mlcousek/plan-standalone-mode`) adds a `DataMode` (`garminConnected` / `standalone`) and hides Garmin-only surfaces. The registry models this as **availability**, which is separate from the user's **visibility** choice. A card that's unavailable in the current mode is skipped and shown greyed out in the editor ("Needs Garmin"), but the user's hidden or shown choice for it is kept. Switching modes then never loses a layout. This plan takes no dependency on the exact name the standalone change picks: the availability closure reads whatever the environment exposes.
- **`add-streak-widget`** (the streak widget already exists) and **`add-app-icon-picker`**: the widget theme parameter and icon suggestions build on them.
- **`improve-log-food-shelves`**: its fixed shelf order becomes the default shelf layout.

---

## 5. Contrast audit (WCAG 2.x relative luminance)

Method: a throwaway Python script computing WCAG contrast `(L1+0.05)/(L2+0.05)` with sRGB linearisation (threshold 0.04045). Light card = `#FFFFFF` (`secondarySystemGroupedBackground`), dark card = `#1C1C1E`. Targets: **4.5:1** for normal text, **3:1** for large text and for graphics or UI parts needed to understand content (SC 1.4.11).

**Today's palette, measured**:

| Token | Hex | vs white card | vs dark card | White text on it |
|---|---|---|---|---|
| accent | `#F56B4A` | **2.96** ✗ | 5.74 | **2.96** ✗ |
| accentDeep | `#CC452E` | 4.71 | 3.61 | 4.71 |
| carbs | `#4A8FE3` | 3.32 | 5.13 | |
| protein | `#8C66DB` | 4.17 | 4.08 | |
| fat | `#EDB033` | **1.93** ✗ | 8.80 | |
| success | `#33AD73` | **2.85** ✗ | 5.97 | |
| warning | `#E69921` | **2.35** ✗ | 7.25 | |
| ember | `#FA8C29` | **2.37** ✗ | 7.17 | |
| grace | `#8C9EB2` | **2.75** ✗ | 6.20 | |
| over | `#C7527A` | 4.27 | 3.98 | |
| band yellow | `#F5C92E` | **1.58** ✗ | 10.76 | |
| band red | `#DB3D3B` | 4.43 | 3.84 | |

What stands out:

1. **The "Log it" `PrimaryButton` puts white text on coral at 2.96:1**, which is below AA for its 17 pt semibold label.
2. In **light mode** the fat bar, the ring's yellow "approaching" band, success, warning, ember and grace all fall below the 3:1 graphics threshold on white cards.
3. Dark mode is fine across the board.

The default theme must look exactly like today (the owner's zero-change requirement), so these stay as they are in "Classic". They're fixed in three ways instead:

- The **High Contrast** theme.
- An **automatic increased-contrast variant** of every theme whenever iOS "Increase Contrast" is on (`colorSchemeContrast == .increased`), which nothing reads today.
- An open question to the owner about darkening Classic's button fill.

**Candidate theme colors, measured**, with a light / dark pair per theme:

| Color | Hex | vs white | vs `#1C1C1E` | Best text on it |
|---|---|---|---|---|
| Teal L / D | `#15808C` / `#3CC8D4` | 4.67 / 2.02 | 3.64 / 8.43 | white 4.67 / black 10.4 |
| Forest L / D | `#2E7D4F` / `#5CC98A` | 5.05 / 2.06 | 3.37 / 8.25 | white 5.05 / black 10.2 |
| Sunset L / D | `#C2255C` / `#F06595` | 5.66 / 3.00 | 3.01 / 5.67 | white 5.66 / black 7.0 |
| Ocean L / D | `#1D5FA8` / `#5AA9F0` | 6.45 / 2.51 | 2.64 / 6.78 | white 6.45 / black 8.4 |
| Mono L / D | `#3A3A3C` / `#E5E5EA` | 11.35 / 1.26 | 1.50 / 13.55 | white 11.4 / black 16.7 |
| High Contrast L / D | `#0040DD` / `#409CFF` | 7.56 / 2.83 | 2.25 / 6.01 | white 7.56 / black 7.4 |
| Autumn rust L / D | `#A84A14` / `#F08A4B` | 5.75 (5.34 on cream `#FBF6EE`) / 2.49 | 2.96 / 6.84 | white 5.75 / black 8.4 |
| Autumn plum L / D | `#6B3E75` / `#C39BD3` | 8.17 / 2.35 | 2.08 / 7.25 | |
| Night Run lime | `#C6F432` | 1.28 | 13.28 (16.4 on black) | black 16.4 |

So **every theme needs a separate light and dark value per brand token**. A single hex that works on both white and near-black is rare: only mid-luminance colors like Sunset D at 3.0 / 5.7 manage it. Text on the accent must be *derived* (white or black, whichever contrasts more), not fixed at white. Night Run's lime needs black text.

**A colour-blind-safe macro set** (Okabe-Ito hues, darkened in light mode until they reach 3:1 on white):

| Macro | Light | Dark | vs white | vs dark card |
|---|---|---|---|---|
| Carbs (blue) | `#0072B2` | `#56B4E9` | 5.19 | 7.37 |
| Protein (vermillion) | `#D55E00` | `#F28A3C` | 3.87 | 6.87 |
| Fat (yellow-ochre) | `#8A6D00` | `#F0E442` | 4.92 | 12.87 |

Blue, vermillion and yellow stay distinct under deuteranopia, protanopia and tritanopia, which the standard blue, purple and amber set doesn't: blue and purple collapse for protan and deutan viewers. The macro bars also keep their "C / P / F" letters, so color is never the only cue (SC 1.4.1).

---

## 6. Recommendations carried into the plan

1. **Tokens become a value (`ThemePalette`), not constants.** `Theme.swift` keeps today's values as the `classic` palette, so the widget and any not-yet-migrated call site still compile and look the same.
2. **The pure logic goes into a new, dependency-free SPM package, `AppearanceKit`**, which holds:
   - RGB/OKLab color math and WCAG contrast
   - the theme spec model and the built-in catalog as data
   - the layout model with merge and migration rules
   - share-code encoding

   This buys fast `swift test` in CI and a clean boundary, and it doesn't edit FoodLogCore while the 8 gamification changes do. The cost is one CI step plus a `project.yml` package entry. Alternative considered: a folder inside FoodLogCore. It was rejected because FoodLogCore is the domain layer and is under heavy parallel edit.
3. **A CI lint, `tools/lint-design-tokens.sh`**, a grep over `ios/GarminFood`, `ios/Shared` and `ios/GarminFoodWidget` with an allowlist file. It's runnable in Git Bash on this Windows machine, which makes it the one design check that can run locally.
4. **The layout editor is a List in a half-height sheet over the live screen.** There's no in-place jiggle mode.
5. **Widgets get a per-instance theme parameter** through `AppIntentConfiguration`. They can never follow the app automatically.
6. **Icons: finish PR #27's device verification first.** Then add teal-era alternates that match the themes, and have themes *offer* the matching icon.
7. **Don't name anything after Garmin.** A "Garmin Night" theme would go against `Theme.swift`'s explicit "never read as an official Garmin surface" rule, so the dark sporty theme is called **Night Run**.

## Sources

- Apple: [`setAlternateIconName(_:completionHandler:)`](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:)), [`AppIntentConfiguration`](https://developer.apple.com/documentation/widgetkit/appintentconfiguration), [`WidgetConfigurationIntent`](https://developer.apple.com/documentation/appintents/widgetconfigurationintent), [`ShapeStyle.resolve(in:)`](https://developer.apple.com/documentation/swiftui/shapestyle/resolve(in:)), [`presentationBackgroundInteraction(_:)`](https://developer.apple.com/documentation/swiftui/view/presentationbackgroundinteraction(_:)), [`PasteButton`](https://developer.apple.com/documentation/swiftui/pastebutton)
- [Kyle Bashour — Advanced WidgetKit configuration with AppIntents](https://kylebashour.com/posts/advanced-widgetkit)
- [AltStore FAQ](https://faq.altstore.io/altstore-classic/your-altstore) (free-account limits: 7-day signing, 3 active apps)
- W3C WCAG 2.2: [SC 1.4.3 Contrast (Minimum)](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum), [SC 1.4.11 Non-text Contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast), [relative luminance](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance)
- Okabe & Ito, *Color Universal Design* (2008): the colour-blind-safe 8-colour palette
- Repo: `openspec/changes/add-gamification-signals/design.md` D12 and wave plan; `openspec/changes/add-app-icon-picker/`; branch `mlcousek/plan-standalone-mode` `openspec/changes/add-standalone-mode/design.md` D1
