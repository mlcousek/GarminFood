## Context

This design was written after reading the following on 2026-09-24, on
`origin/main` @ `b117adf`:

- **Design system:** `ios/Shared/Theme.swift` (fixed static tokens,
  compiled into the app and the widget), `ios/GarminFood/DesignSystem/
  Components.swift` (`CardStyle`/`.card()`, `GoalState.tint`,
  `CalorieBand.tint` with 2 literal colors, `ProgressRing`, `MacroBar`,
  `PrimaryButton`, `StatTile`, `DaySwitcher`), `BadgeMedallion.swift` and
  `AppSignatureView.swift`.
- **Screens:** `Today/TodayView.swift` (fixed card stack),
  `Catalog/FoodCatalogView.swift` (5 fixed shelves plus custom foods),
  `Progress/ProgressViews.swift` (`ProgressHomeView`, 8 fixed cards) and
  `ContentView.swift` (3 tabs, root `.tint`).
- **Preferences:** `App/AppPreferences.swift`, which uses keyed
  `UserDefaults` and the `object(forKey:) as? T ?? default` pattern.
- **Widgets:** `GarminFoodWidget/*`, two `StaticConfiguration` Home Screen
  widgets drawing gradients from `Theme`.
- **Icons and build:** `ios/project.yml` (5 loose-file
  `CFBundleAlternateIcons`) and `.github/workflows/build.yml` (one
  `swift test` step per package).
- **Other plans:** `openspec/changes/add-app-icon-picker/` (device check
  still open), `openspec/changes/add-gamification-signals/design.md` D12
  (slot hosts) and its wave plan, and branch
  `mlcousek/plan-standalone-mode` `add-standalone-mode/design.md` D1
  (`DataMode`).

The full audit, with measured contrast numbers, is in
[`docs/theming-research.md`](../../../docs/theming-research.md). The facts
that shape this design:

1. **One fixed palette.** Brand and state colors are single sRGB values
   used in both light and dark mode. Surfaces are system colors.
2. **Several light-mode colors fail WCAG** on white cards. The accent is
   2.96:1 (and so is white text on the accent button), fat 1.93, the band
   yellow 1.58, success 2.85, warning 2.35, ember 2.37 and grace 2.75. In
   dark mode everything is at least 3.6:1.
3. **About 44 files reference `Theme.*` colors directly**, plus 9 `.red`
   error texts, a `.green` swipe tint, hydration reusing `carbs`, and 2
   literal band colors.
4. **The widget process can't read app settings**, because there's no App
   Group. What it *can* have is a per-instance intent parameter stored by
   the system.
5. **Nothing can be compiled locally.** Pure logic must sit in an SPM
   package that CI tests. A grep lint is the only design check that also
   runs in Git Bash on Windows.

No Garmin route is involved. There is nothing to probe, and no private-API
fallback is needed.

## Goals / Non-Goals

**Goals:**

- Curated themes with a light and a dark value per token.
- User style options, a custom accent with guaranteed contrast, and
  adaptation to accessibility settings.
- A card registry for Today, Log Food and Progress, with reorder, hide,
  variants and presets.
- Theme sharing between two phones.
- Honest widget theming.
- **With nothing stored, the app looks exactly as it does today.**

**Non-goals:** see the proposal. In short:

- no live or auto-following widgets
- no per-person profiles
- no rarity recoloring
- no new gamification cards
- no hiding of Garmin-only surfaces (that's standalone mode's job)
- no free-form editing of every token

---

## D1 — `AppearanceKit`: a new dependency-free SPM package for the pure logic

`ios/AppearanceKit/` imports Foundation only. It has no SwiftUI, GarminKit
or FoodLogCore dependency. Both the app and the widget link it. It holds:

- **`ColorMath`:**
  - `RGBA` (sRGB doubles) and hex parsing and formatting
  - sRGB↔linear conversion and WCAG relative luminance
  - `contrast(_:_:)`
  - OKLab and OKLCH conversion
  - `deltaE_OK`
  - CVD simulation (Machado 2009 matrices for protan, deutan and tritan at
    severity 1.0)
- **`ThemeRole`, `TokenValue`, `ThemeSpec`, `ThemeCatalog`:** the themes
  as data (D3).
- **`AppearanceSettings`:** the user's choices (D6), with lenient
  `Codable`.
- **`PaletteResolver`:** `(ThemeSpec, AppearanceSettings, scheme,
  AccessibilityFlags) → ResolvedPalette`, where every role maps to a
  `TokenValue` (D4).
- **`ContrastPolicy`, `AccentAdjuster`:** thresholds and automatic fitting
  (D5).
- **Layout:** `CardSpec`, `ScreenLayout`, `LayoutConfig`, `LayoutResolver`
  and `LayoutPreset`, plus the card ID enums (D8).
- **`ThemeShareCode`:** encoding and decoding (D11).

**Why a new package rather than a folder in FoodLogCore:**

- FoodLogCore is the domain layer ("meal", "serving"). Appearance isn't
  domain logic.
- The 8 gamification changes are editing FoodLogCore in parallel. A
  separate package can't conflict with them.

The cost is one `swift test` step in `build.yml` and one `packages:` entry
plus two target dependencies in `project.yml`. Packages don't consume
AltStore App IDs.

## D2 — Tokens become a resolved palette in the environment

**App side** (`GarminFood/DesignSystem/Theming/`, plus `Shared/` for the
parts the widget also needs):

- `ThemePalette` is an `Equatable` struct of **precomputed `Color`s**, one
  per `ThemeRole`, built once from a `ResolvedPalette`. A
  `TokenValue.system(.secondaryGroupedBackground)` becomes
  `Color(.secondarySystemGroupedBackground)`, and `.rgb` becomes
  `Color(.sRGB, …)`. So Classic keeps using the same system colors it uses
  today, not approximations of them.
- `EnvironmentValues.palette` (default `.classic`), plus
  `EnvironmentValues.themeStyle` (card style, corner scale, density,
  number design, gradient header).
- `ThemeColor: ShapeStyle` with `resolve(in:)` (iOS 17) reads
  `environment.palette[role]`. Call sites written as
  `.foregroundStyle(Theme.accent)` become `.foregroundStyle(.theme(.accent))`
  and keep their shape. Sites that need a concrete `Color` (gradients,
  `ProgressRing(tint:)`, `.opacity` math, `GoalState.tint(base:)`) use
  `@Environment(\.palette) var palette`.
- `ThemeStore` is `@MainActor @Observable`. It owns the
  `AppearanceSettings`, persists them (D7), and is registered in
  `AppEnvironment` like every other store.
- The **root `.themed(store)` modifier** in `ContentView` does three things:
  1. It applies `.preferredColorScheme(settings.appearance.colorScheme)`,
     where `nil` means follow the system.
  2. An inner `ThemeResolverView` reads the *effective* `colorScheme`,
     `colorSchemeContrast`, `accessibilityReduceTransparency` and
     `accessibilityDifferentiateWithoutColor`.
  3. It resolves and sets `\.palette` and `\.themeStyle`, and replaces
     today's `.tint(Theme.accent)` with `.tint(palette.accent)`.

  `MomentOverlay` and every sheet sit inside this tree. On-device task
  2.8 confirms that sheets inherit the values. Any presenter that doesn't
  gets an explicit `.themed(store)`.
- **`Theme.swift` keeps its static constants**, equal to Classic. Three
  things still use them: the widget, when a widget instance has no
  parameter; `#Preview`s; and any code outside a themed tree. After
  wave 1, the lint (D12) forbids `Theme.<color>` inside `ios/GarminFood/`.
  `Theme.Spacing`, `Theme.Radius` and `Theme.confirmAnimation` remain as
  they are (see D6 for density).

**Performance.** The palette is a small value. It only changes when the
user changes a setting or an accessibility flag, which invalidates the
views that read it once. No color math runs in `body`: resolution happens
in `ThemeResolverView` when its inputs change. Layout state lives in an
`@Observable` store, so reordering Today re-renders Today only.

**Alternative rejected:** dynamic `UIColor` providers reading a custom
iOS 17 `UITrait`, which would need zero call-site changes. Whether SwiftUI
resolves `Color(uiColor:)` against a custom trait can't be verified without
a simulator, and a wrong guess would fail silently (the colors would
simply not change). The explicit environment is boring and checkable.

## D3 — Token roles and the built-in themes

**Roles** (`ThemeRole`, grouped):

| Group | Roles | Classic value (= today) |
|---|---|---|
| Surfaces | `background`, `surface`, `surfaceRaised`, `stroke` | `systemGroupedBackground`, `secondarySystemGroupedBackground`, `secondarySystemBackground`, `separator` (system) |
| Brand | `accent`, `accentDeep`, `onAccent`, `accentSecondary`, `headerGradientStart/End` | `#F56B4A`, `#CC452E`, white, `#FA8C29`, accent→accentDeep |
| Streak | `ember`, `flameTip` | `#FA8C29`, `#F56B4A` (flame = ember→accent, as today) |
| Macros | `carbs`, `protein`, `fat`, `water` | `#4A8FE3`, `#8C66DB`, `#EDB033`, `#4A8FE3` (water = carbs, as today) |
| States | `success`, `warning`, `danger`, `over`, `grace` | `#33AD73`, `#E69921`, system red (what `.red` is today), `#C7527A`, `#8C9EB2` |
| Calorie bands | `bandLow`, `bandBuilding`, `bandApproaching`, `bandOnTarget`, `bandSlightlyOver`, `bandOver` | grace, ember, `#F5C92E`, success, ember, `#DB3D3B` |

Text stays on the system `.primary`, `.secondary` and `.tertiary` styles in
every theme. Themes that tint their surfaces are contrast-tested against
the system label values (D5). Rarity medal colors are **not** roles.

**Two shared macro and state sets** (AppearanceKit constants, reused by
themes):

- **Legible**: the same hues as Classic, darkened in light mode so each
  reaches at least 3:1 on both `#FFFFFF` and `#F2F2F7`. Dark mode uses
  Classic's values, which already pass.

  | Role | Light value (contrast on white / on `#F2F2F7`) | Dark value |
  |---|---|---|
  | carbs | `#2F74C8` (4.72 / 4.23) | Classic's |
  | protein | `#7A52C7` (5.44 / 4.88) | Classic's |
  | fat | `#A86F00` (4.25 / 3.81) | Classic's |
  | water | `#1C7FB8` (4.40) | `#5AC8FA` |
  | success | `#1F8A57` (4.35) | Classic's |
  | warning | `#B36B00` (4.18) | Classic's |
  | ember | `#C75A00` (4.29) | Classic's |
  | bandApproaching | `#9A7400` (4.31) | Classic's |
  | grace | `#6B7C90` (4.28) | Classic's |
  | bandOver and danger | `#C62828` (5.62) | `#FF6B6B` |
  | over | `#B0406A` (5.54) | Classic's |

- **Colour-blind safe** (Okabe-Ito hues):

  | Macro | Light (contrast on white) | Dark (contrast on `#1C1C1E`) |
  |---|---|---|
  | carbs | `#0072B2` (5.19) | `#56B4E9` (7.37) |
  | protein | `#D55E00` (3.87) | `#F28A3C` (6.87) |
  | fat | `#8A6D00` (4.92) | `#F0E442` (12.87) |

  The bands use the same blue, vermillion and yellow logic.

**Built-in themes.** L and D give the light and dark value of each brand
color, with contrast measured against a white card and a `#1C1C1E` card.
These are starting values: the tests (D5) are the contract. An implementer
may nudge a value to pass and records the change in the catalog's comment.

| ID | Name | Accent L / D | Deep / secondary | Surfaces | Macros | Notes |
|---|---|---|---|---|---|---|
| `classic` | Classic | `#F56B4A` both | Today's | system | Classic, exempt (D5) | **Default. Pixel-identical to today.** |
| `teal` | GF Teal | `#15808C` (4.67) / `#3CC8D4` (8.43) | deep `#164E73`, secondary cyan | system | Legible | Matches the PR #37 icon (navy to cyan). Header gradient `#164E73`→`#22D3DC`. |
| `forest` | Forest | `#2E7D4F` (5.05) / `#5CC98A` (8.25) | moss `#6E7F24` | light background `#F3F5F1` | Legible | Calm and green. Success shifts to teal-green so it doesn't collide with the accent (distinctness test). |
| `ocean` | Ocean | `#1D5FA8` (6.45) / `#5AA9F0` (6.78) | | system | Legible, **carbs overridden to teal** `#0F8B8D` / `#4FD1C5` | The accent is blue, so carbs moves (D5 distinctness). |
| `sunset` | Sunset | `#C2255C` (5.66) / `#F06595` (5.67) | orange `#D9480F` | system | Legible | Header gradient magenta→orange. |
| `mono` | Mono | `#3A3A3C` (11.35) / `#E5E5EA` (13.55) | | system | Legible | Graphite UI. Macros and bands keep color, because they carry meaning. |
| `highContrast` | High Contrast | `#0040DD` (7.56) / `#409CFF` (6.01) | | system, Outlined cards by default | CVD-safe, fitted to ≥ 4.5:1 | Targets AA text-level contrast for every graphic. |
| `autumn` | Czech Autumn (Podzim) | rust `#A84A14` (5.75; 5.34 on cream) / `#F08A4B` (6.84) | plum `#6B3E75` / `#C39BD3` | light background cream `#FBF6EE` with white cards; dark background `#1C1714` | Legible | The fun one: rust and plum (švestky), header gradient rust→plum. |
| `nightRun` | Night Run | lime `#C6F432` (14.62 on `#121212`) | | **dark only**: background `#000000`, cards `#121212` | CVD-safe | OLED and running-watch vibe. `onAccent` is black. |

"Garmin Night" was suggested as a name and rejected: `Theme.swift` says the
app must never read as an official Garmin surface.

`ThemeSpec` also carries `supportedSchemes` (Night Run: `[.dark]`, so the
appearance picker hides Light and System for it), `defaultStyle` (High
Contrast: Outlined cards) and `suggestedIconName` (D10).

## D4 — Resolution order

`PaletteResolver.resolve` builds the palette in five steps:

1. **Start from the theme's light or dark table** for the effective scheme.
2. **Apply the macro set override.** If the user chose Colour-blind safe,
   or `differentiateWithoutColor` is on, swap in the CVD-safe macros and
   bands.
3. **Apply the custom accent**, if set. `AccentAdjuster` fits it per scheme
   (D5), and `accentDeep`, `onAccent` and the header gradient are derived
   from it.
4. **Apply increased contrast**, if `colorSchemeContrast == .increased`.
   Every `.rgb` role that falls below its increased threshold is fitted
   with `AccentAdjuster`. This also applies to Classic: an explicit
   accessibility request overrides the zero-change rule.
5. **Derive `onAccent`**: white or black, whichever has the higher contrast
   against the final accent.

## D5 — Contrast and distinctness policy (enforced by tests)

`ContrastPolicy` defines the thresholds. The test suite iterates **every
built-in theme × each supported scheme × {normal, increased contrast}**.

| Pair | Normal | Increased or High Contrast theme |
|---|---|---|
| `onAccent` on `accent` (button labels) | ≥ 4.5 | ≥ 7.0 |
| `accent` on `surface` and `background` | ≥ 3.0 | ≥ 4.5 |
| each macro, `water`, state and band role on `surface` | ≥ 3.0 | ≥ 4.5 |
| system secondary label (`#8A8A8E` light / `#98989F` dark) on a tinted surface or background | ≥ 3.0 (Apple's own default on white is 3.44) | ≥ 4.5 |

**Distinctness** uses OKLab ΔE:

- Macros pairwise must be at least **0.10** apart.
- The accent against each macro must be at least **0.06** apart.
- For the CVD-safe set, the macros must stay at least 0.10 apart pairwise
  *after* protan, deutan and tritan simulation.

**Classic is exempt** from the thresholds, but only through an **explicit
list** in the test: accent, onAccent-on-accent, fat, success, warning,
ember, grace, bandApproaching, and water-as-carbs in light mode. If the
list grows, the test fails. Classic's gaps are only fixed through D4
step 4 or by the owner's choice (open question 3).

**`AccentAdjuster.fit(color, against: surfaces, minRatio:)`** works like
this:

- It converts to OKLCH and moves lightness in 0.01 steps: down for a light
  scheme, up for a dark one. It keeps the hue and reduces chroma only when
  the color falls outside the sRGB gamut.
- It stops at the first value that meets the ratio. It gives up after 100
  steps and returns the best candidate, flagged.
- It returns `(color, wasAdjusted)`.

The user's raw pick is what gets stored. Fitting happens at resolve time,
so a single pick works in both light and dark mode. The picker shows the
adjusted swatches ("Adjusted for dark mode") and a warning when the pick is
closer than 0.06 ΔE to a macro color ("Looks like the protein color. Bars
may be harder to tell apart").

## D6 — Style options

These are stored in `AppearanceSettings.style` and exposed through
`\.themeStyle`.

- **Card style** (in `CardStyle`, so all 34 `.card()` uses follow):
  - **Filled** (default, today's look): `surface` fill.
  - **Elevated**: `surface` plus a soft shadow (`black 8%`, radius 8,
    y 2) in light mode. In dark mode it uses `surfaceRaised` with no
    shadow, because shadows vanish on black.
  - **Outlined**: `background` fill plus a 1 pt `stroke` border, or 2 pt
    under Increase Contrast.
  - **Glass**: `.regularMaterial` over a screen background carrying a
    faint theme gradient. Under Reduce Transparency it falls back to
    Filled.
- **Corner shape.** This scales `Theme.Radius` through the environment:
  - Sharp: 4, 8, 10, 14
  - Standard (default): 8, 14, 20, 28
  - Round: 12, 18, 26, 34
- **Density**:
  - Comfortable (default, today's look).
  - Compact: card padding goes from 16 to 12 and screen stack spacing
    from 24 to 16.

  Density applies **only at container level** (`CardStyle` padding, the
  Today, Progress and Log Food stack spacing and screen padding). There
  are 211 internal `Theme.Spacing` uses, and they stay static.
  Tap targets stay at least 44 pt.
- **Number font.** Rounded (default), Default, Serif (New York) or
  Monospaced. `Font.heroNumber`, `streakNumber`, `macroValue` and the
  number-only ad-hoc fonts drop their hard-coded `design:`. A
  `.numberStyle()` modifier applies `.fontDesign(style.numberDesign)`
  (iOS 16.1+). Monospaced digits are kept in every style.
- **Dynamic Type fix**, done alongside the font change: `heroNumber`
  (72 pt) and the Level detail's 48 pt number become `@ScaledMetric`
  (relative to `.largeTitle`, clamped with
  `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` on that element).
  At the default text size they look identical.
- **Gradient header** (Today only, off by default): a
  `headerGradientStart`→`End` wash behind the day switcher and summary
  card, at 22% opacity fading into `background`. Under Reduce Transparency
  it becomes a flat 12% tint. Text on it remains `.primary`, and the tests
  check `.primary` against the gradient's darkest or lightest stop blended
  at 22%.
- **Appearance**: System (default), Light or Dark. It's stored per theme
  (`[themeID: Appearance]`), so Night Run can be dark while Classic stays
  on System.

## D7 — Persistence and migration

- There are two new `AppPreferences` keys, `appearance.v1` and
  `layout.v1`. Each holds JSON `Data`. `AppPreferences+Appearance.swift`
  and `AppPreferences+Layout.swift` decode them, following the pattern
  `AppPreferences+Fasting.swift` already uses.
- **Absent key** means `AppearanceSettings.default` and
  `LayoutConfig.default`, which is today's look and order. Existing users
  see zero change.
- **Lenient decoding:**
  - Every field is decoded with `decodeIfPresent`.
  - An unknown enum raw value, like a theme ID from a newer build, falls
    back to that field's default, not to a failure.
  - Unknown extra fields are ignored.
  - A `version` field drives `AppearanceMigration` and `LayoutMigration`.
    These do nothing at v1, but the seam exists.
- **An undecodable blob is quarantined, not wiped** (the same spirit as
  `fix-silent-store-wipe`):
  - It's copied to `appearance.v1.quarantine` or `layout.v1.quarantine`.
  - It's logged with `DiagnosticsLog.log(.warning, category: "appearance",
    …)`.
  - The defaults are used.
  - Settings shows "Your saved look couldn't be read and was reset" once.
- Stores write through on every change. There's no Save button. Changes
  apply live.

## D8 — Card registry and layout model

**Pure model (AppearanceKit):**

```swift
enum TodayCardID: String, CaseIterable, Codable { case daySwitcher, summary, progressStrip, banners, fasting, meals, logAgain, logMeal, weightWater, dayNote, signature }
enum LogFoodShelfID: String, CaseIterable, Codable { case quickPick, favorites, usual, meals, recent, customFoods }
enum ProgressCardID: String, CaseIterable, Codable { case streak, level, boss, bingo, seasonal, journeys, records, collections, sportBody, secrets, challenges, achievements, weight, hydration, trends, goalHistory }

struct CardSpec { id: String; title: String; systemImage: String
                  defaultVisible: Bool; variants: [String]; defaultVariant: String?
                  pin: Pin?  /* .top / .bottom */ ; hideable: Bool }
struct CardPlacement: Codable { id: String; isVisible: Bool; variant: String? }
struct ScreenLayout: Codable { placements: [CardPlacement] }
struct LayoutConfig: Codable { version: Int; today, logFood, progress: ScreenLayout?; startTab: String?; appliedPreset: String? }
```

The ID lists match the code that exists today, plus
`add-gamification-signals` D12's slot names, which are used verbatim.
`ProgressCardID`'s default order is today's order with D12's slot block
inserted "under the level card" in D12's order.

**`LayoutResolver.resolve(stored:specs:) → [ResolvedPlacement]`** follows
these rules, each covered by a unit test:

1. Walk the stored placements in order. Keep the first occurrence of an ID
   and drop duplicates.
2. **Keep IDs that are unknown to this build in storage, but don't render
   them.** A card missing from one build, or from one mode, doesn't lose
   its position when it comes back.
3. **Place new spec IDs** (not in storage) right after the nearest card
   that precedes them in the *default* order and is present. With none
   present, they go first. Their visibility is `defaultVisible`.
4. An unknown or invalid variant falls back to `defaultVariant`.
5. Pinned cards are forced to their edge, and they're always visible when
   `!hideable`:
   - `daySwitcher`: top, not hideable
   - `signature`: bottom, hideability is open question 6
6. With nothing stored, the result is exactly the default order.

A golden test pins the defaults to today's order for each screen.

**App side (`GarminFood/Layout/`):**

- `LayoutStore` (`@Observable`) is set up the same way as `ThemeStore`.
- Each screen renders `ForEach(resolved) { placement in card(placement) }`
  through a single `@ViewBuilder switch` over its ID enum. That gives
  compile-time exhaustiveness and no `AnyView`. Adding a future card means
  adding an enum case (AppearanceKit), a spec, and a switch arm.
- **Availability is separate from visibility.** The screen supplies
  `availability(id) → .available | .empty(hint) | .unavailable(reason)`.
  - Today's existing conditions move here unchanged:
    - Log again and Log a meal are `.empty` unless it's today and there's
      something to show.
    - Fasting is `.unavailable("Turn on fasting in Settings")` while it's
      off.
  - `add-standalone-mode` can return `.unavailable("Needs Garmin")` for
    Garmin-only cards from the same function, without touching the
    layout model.
  - Rendering shows only placements that are visible **and** available.
    The editor lists everything and greys out unavailable rows with their
    reason.
- **Variants:**

  | Card | Variants |
  |---|---|
  | `summary` | `ring` (today's) / `compact` (72 pt scaled ring in one row) / `hero` (big number with no ring, using `Font.heroNumber`) |
  | `meals` | `expanded` (today's) / `collapsed` (each `MealSectionCard` shows its header and macro bars only; tapping still opens `MealDetailView`) |
  | `weightWater` | `both` (today's) / `weight` / `water` |
  | `progressStrip` and everything else | none |

  The banners card hosts `TodaySlotHost()` as one block and is placed
  above `meals` by default, as D12 says.
- **Log Food:** `FoodCatalogView`'s shelf `if` chain becomes a `ForEach`
  over the resolved shelf order. The existing per-mode rules (picker
  modes, `pickBackingFood`, empty shelves) stay as availability on top of
  the user's choice. Search results are unaffected.
- **Progress:** `ProgressHomeView` renders the resolved order. Each gamification slot view
  (`BingoSlotView`, …) is referenced *individually* as a registry card, so
  the user can hide Bingo but keep Boss. `ProgressSlotHost()`'s single call
  is replaced by these individual entries. **None of the slot files are
  edited**, and the wave-2/3 gamification plans are untouched: they keep
  filling their own slot file.
- **Start tab:** `LayoutConfig.startTab` can be `today` (default) or
  `progress`. `AppRouter`'s initial `selectedTab` reads it at launch, and
  deep links and widget routes still win. Tabs aren't reordered or hidden
  (see the proposal's non-goals).

## D9 — Edit layout UX and presets

- **Entry points:**
  - Today's toolbar menu → "Edit layout…"
  - Settings → Appearance → Layout → Today / Log Food / Progress (each
    opens the same editor for that screen)
- **`LayoutEditorSheet`** is generic over a screen:
  - It's a `List` with `.environment(\.editMode, .constant(.active))` and
    `ForEach.onMove`, which gives native drag handles, VoiceOver
    "Move up/Move down" actions, and haptics.
  - Each row has a leading visibility toggle (eye icon), the card's icon
    and title, and a trailing variant `Menu`. Unavailable rows are greyed
    out with their reason as a caption. Pinned rows have no handle and
    show a lock glyph.
  - **Live preview:** the sheet uses `.presentationDetents([.medium,
    .large])` and `.presentationBackgroundInteraction(.enabled(upThrough:
    .medium))`. The real screen underneath updates as rows move, and at
    medium height it can be scrolled.
  - The toolbar has **Presets** (a menu), **Reset** (with a confirmation
    dialog) and **Done**. Every change writes through, so there's no
    separate Save step.
- **Today presets** (`LayoutPreset`, pure data, tested):

  | Preset | Layout |
  |---|---|
  | **Full** | Today's default. Everything shows, including meals expanded and the ring. |
  | **Minimal** | summary `compact`, meals `collapsed`, log again. Everything else hidden except the pinned cards. |
  | **Athlete** | summary `ring`, progress strip, weight & water `both` (moved up under the strip), meals `expanded`, fasting, log again, log a meal, banners, day note |

  Applying a preset overwrites Today's placements and records
  `appliedPreset`. Any edit afterwards clears `appliedPreset` and shows
  "Custom".
- **Undo:** Reset returns to Full. The previous layout is kept in memory
  for the session, so the confirmation dialog can offer "Undo reset".

## D10 — Alternate icons that match themes

- **Precondition:** `add-app-icon-picker` task 4.2 must be confirmed on a
  real, AltStore-signed install. `setAlternateIconName` needs no
  entitlement, so a free Personal Team shouldn't block it, but it hasn't
  been observed yet. If it fails, the icon tasks are dropped, the finding
  is recorded, and themes ship without icon suggestions.
- **New alternates**, 7 in the same loose-file mechanism as PR #27:
  - Coral Classic (the pre-#37 coral primary, recoverable from commit
    `53502e8`)
  - Forest
  - Ocean
  - Sunset
  - Mono
  - Autumn
  - Night Run

  GF Teal uses the primary icon. High Contrast suggests Mono. Existing
  alternates are kept.
- The icons are generated by a committed `tools/generate-app-icons.py`
  (Pillow, the same technique PR #27 used in a throwaway script), so
  they can be regenerated as themes change. Each is a full-bleed opaque
  1024 px image, downsampled to @2x and @3x.
- **Themes suggest, never switch.** When a theme is applied whose
  `suggestedIconName` differs from the current icon, a confirmation
  dialog asks "Also switch the app icon to Forest?". It's only shown if
  the "Match app icon to theme" preference is Ask, which is the default;
  the other option is Never. iOS then shows its own mandatory alert.
- iOS 18 dark and tinted icon variants would need the asset-catalog
  alternate mechanism. That's out of scope here, noted as a follow-up.

## D11 — Sharing a theme

- **Format**: `GFT1.` + base64url(minified JSON with short keys). The
  JSON holds:
  - `t`: theme ID
  - `a`: custom accent hex, optional
  - `s`: style (card, corner, density, number, gradient)
  - `m`: macro set
  - `p`: appearance
  - `l`: Today layout placements, optional, via an "Include layout"
    toggle

  It's typically under 200 characters, with a hard cap of 2 KB on
  decode.
- **Decoding never throws into the UI.** It returns
  `.success(settings, warnings)` or `.failure(reason)`:
  - An unknown theme falls back to Classic, with a warning.
  - An unknown field is ignored.
  - A custom accent is re-fitted by D5 on the receiving phone.
  - A layout is merged through `LayoutResolver`, so a card the receiver
    doesn't have is kept but hidden.
- **Export**: `ShareLink` with the code and a `garminfood://theme?c=<code>`
  link (the app's existing URL scheme, through `AppRouter`), plus a QR
  image from CoreImage's `CIQRCodeGenerator`, shown in a sheet.
- **Import**:
  - a `PasteButton`, which avoids the "Allow Paste" system prompt
    that reading `UIPasteboard` programmatically triggers
  - the link, which opens the app
  - the QR code, through the iPhone Camera, which opens the link

  Import always shows a **preview sheet** with the theme's gallery tile,
  any warnings, and Apply / Cancel. Nothing is applied silently.
- Personal data never goes into the code or the URL: it's appearance and
  layout only.

## D12 — Guard rails: the design-token lint

`tools/lint-design-tokens.sh` is POSIX sh plus `grep -En`, and runs in Git
Bash locally and in CI.

- **Forbidden in `ios/GarminFood`, `ios/Shared` and `ios/GarminFoodWidget`
  `*.swift`:**
  - `Color(red:`, `Color(hue:`, `Color(white:`, `UIColor(red:`
  - named system colors in color positions (`.red`, `.green`, `.blue`,
    `.orange`, `.yellow`, `.purple`, `.pink`, `.teal`, `.mint`, `.cyan`,
    `.indigo`, `.brown`, `Color.<same>`)
  - `.white` and `.black` in `foregroundStyle`, `tint`, `fill` and
    `stroke`
  - after wave 1: `Theme\.(accent|accentDeep|carbs|protein|fat|grace|
    success|warning|ember|over|flameGradient|cardBackground|
    groupedBackground|heroBackground)` anywhere under `ios/GarminFood/`
- **Allowlist**: `tools/design-token-allowlist.txt`, with one
  `path:regex  # reason` line per exemption, for example:
  - `Shared/Theme.swift`
  - `BadgeMedallion.swift` rarity colors
  - the scanner and moment scrims (`Color.black.opacity`)
  - the widget's default fallback
- **Output**: `file:line: <match>` for each violation, and a non-zero exit.
- **CI**: a step before "Install XcodeGen", so it fails fast.

## D13 — Widgets

- `GarminFoodHomeWidget` and `GarminFoodStreakWidget` move from
  `StaticConfiguration` to `AppIntentConfiguration`. They keep **the
  same `kind`**, so placed widgets stay put. The extension and target
  are the same too, so no App ID is spent.
- `WidgetThemeIntent: WidgetConfigurationIntent` carries
  `@Parameter(title: "Theme", default: .classic) var theme:
  WidgetThemeOption`. That's an `AppEnum` of the built-in theme IDs,
  living in the widget target. A widget-side assertion checks that the
  enum's IDs are a subset of `ThemeCatalog`'s.
- The timeline stays `.never`, and the widgets still show no data. The
  widget resolves its gradient from `ThemeCatalog` (AppearanceKit is
  linked) for the chosen ID and the scheme the system gives it.
- Existing instances resolve to Classic, so they look exactly as they do
  today.
- **What can't be done, stated in Settings → Appearance:** "Widgets don't
  change with the app's theme. Long-press a widget → Edit Widget to pick
  its theme." A custom accent can't be offered in widgets either, because
  the widget can't read it.
- Lock Screen (accessory) widgets and Controls are system-tinted, and
  they're unchanged.

## D14 — Testing

In **AppearanceKit** (CI `swift test`, real values, no mocks):

- `ColorMathTests`
  - known vectors: white/black 21:1, `#777777` on white 4.48:1
  - OKLab round trip within 1e-4
  - CVD matrices on the primaries
- `ClassicIdentityTests`: every Classic role equals today's literal from
  `Theme.swift` or `Components.swift`. System roles map to the same system
  color names.
- `BuiltInThemeContrastTests` and `DistinctnessTests`: D5, over every
  theme, scheme and contrast mode, including Classic's closed exemption
  list.
- `AccentAdjusterTests`
  - coral in light mode is fitted and the hue kept within 3°
  - an already-passing color comes back unchanged
  - `#FFFF00` in light mode terminates
  - lime in light mode gets darkened
- `AppearanceSettingsCodingTests`: absent means default; missing fields;
  an unknown theme or enum value; extra fields; garbage bytes cause a
  decode failure, which is reported, not thrown.
- `LayoutResolverTests`: each D8 rule, presets, the golden default order
  per screen, and a round trip with a card unknown to this build.
- `ThemeShareCodeTests`: round trip; the `GFT1.` prefix is required; a
  tampered payload is rejected; over 2 KB is rejected; an unknown theme
  gives Classic plus a warning; an imported accent is re-fitted.

In **CI**: the lint (D12). App-level UI can't be unit-tested (project
convention), so every wave ends with an explicit on-device checklist.

## Risks / Trade-offs

- **Wave 1 is a wide mechanical diff** (about 44 files). There's no
  compiler locally, so a typo costs a CI round trip. *Mitigation:*
  migrate in three batches, each its own commit with green CI, and keep
  `Theme.*` statics compiling throughout.
- **"Pixel-identical" can only be judged by eye**, since there's no
  snapshot testing without a simulator. *Mitigation:* Classic identity is
  unit-tested at the value level, and the on-device task compares
  screenshots before and after in light and dark mode.
- **Custom environment values in sheets and overlays.** Inheritance is
  expected on iOS 17, but it can't be checked locally. *Mitigation:* a
  device checklist item, and an explicit `.themed(store)` on any presenter
  that loses it.
- **Too many options make a messy app.** *Mitigation:*
  - The defaults stay the same.
  - All options sit behind a single Settings → Appearance screen, with a
    theme gallery first and style options under "Fine-tune".
  - Only the accent is free-form.
- **The 16 Progress cards collide in the editor.** *Mitigation:* rows
  show their icon plus availability. A slot whose feature has no content
  yet reports `.empty("Appears when …")`, so the list stays honest.
- **Merge conflicts with in-flight plans.** Wave 4 edits
  `ProgressViews.swift`'s `ProgressHomeView` body. Gamification wave 3
  (`add-weekly-boss-and-streak-freezes`) edits `StreakDot` and the streak
  card in the same file, in different regions. *Mitigation:* land wave 4
  after gamification wave 1, and rebase rather than re-plan.

## Migration Plan

- There's no data migration: new keys, absent by default.
- To roll back, delete `appearance.v1` and `layout.v1` (Settings →
  Appearance → "Reset all appearance"). A downgraded build ignores the
  unknown keys.

## Open Questions

These are listed for the owner in `tasks.md` §0.
