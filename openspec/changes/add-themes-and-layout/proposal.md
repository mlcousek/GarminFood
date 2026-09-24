## Why

The owner asked: *"the look of the app — can you introduce themes and
customizable screen, like colors, like layout? do also research and plan for
this"*.

Today the app has exactly one look. `Theme.swift` is a set of fixed
constants: a coral accent, fixed macro hues, and system surfaces. Every
screen shows its cards in a hard-coded order. The research in
[`docs/theming-research.md`](../../../docs/theming-research.md) found five
more reasons to act:

- **The icon and the app disagree.** Since PR #37 the primary icon is navy
  to cyan teal, but the app is still coral.
- **Contrast gaps in light mode.** The "Log it" button puts white text on
  coral at 2.96:1. Fat, success, warning, ember, grace and the ring's yellow
  band all fall below 3:1 on white cards. Increase Contrast, Reduce
  Transparency and Differentiate Without Color are never read.
- **The macro hues aren't colour-blind safe.** Blue and purple collapse for
  protan and deutan viewers.
- **Colors bypass the tokens.** Nine raw `.red` error texts, a `.green`
  swipe tint, and hydration borrowing the `carbs` color.
- **Fixed layouts.** Both people who use the app (the owner and possibly his
  fiancée) must scroll past the same fixed stack of cards whether or not
  they use fasting, weight, presets or notes.

## What Changes

- **Theme system.** Semantic tokens become a `ThemePalette` value that is
  resolved for the current theme, color scheme and accessibility settings,
  and injected through the SwiftUI environment. The pure logic (color math,
  WCAG contrast, auto-adjust, theme specs, share codes) lives in a new
  dependency-free SPM package, `AppearanceKit`, which is unit-tested in CI.
- **9 built-in themes.** Each has its own light and dark values:
  - **Classic** (default, today's coral, pixel-identical)
  - **GF Teal** (matches the new icon)
  - **Forest**
  - **Ocean**
  - **Sunset**
  - **Mono**
  - **High Contrast**
  - **Czech Autumn** (rust and plum on warm paper)
  - **Night Run** (true-black OLED with a lime accent, dark only)
- **Style options.**
  - Appearance: System, Light or Dark, per theme.
  - A custom accent picker with automatic contrast fixing and a warning
    when the accent is too close to a macro color.
  - Card style: Filled (today), Elevated, Outlined or Glass.
  - Corner shape: Sharp, Standard or Round.
  - Density: Comfortable (today) or Compact.
  - Number font: Rounded (today), Default, Serif or Monospaced.
  - An optional gradient header on Today.
  - Macro colors: Standard or Colour-blind safe (Okabe-Ito).
- **Layout customization through a card registry.**
  - On the Today screen you can reorder cards, hide or show them, and pick
    per-card variants: ring large, compact or hero number; meals expanded
    or collapsed; Weight & Water as both, weight only or water only.
  - An "Edit layout" half-height sheet with drag handles sits over the live
    screen, with Reset.
  - Presets: Full (today), Minimal, Athlete.
  - Log Food shelf order and visibility, Progress section order and
    visibility (including the gamification slot cards), and a choice of
    which tab the app opens on.
- **Sharing.** Export and import a theme as a short `GFT1.` code, a
  `garminfood://theme?c=…` link or a QR code. Import is through
  `PasteButton`, so there's no paste prompt.
- **Widgets.** The Home Screen widgets get a per-widget "Theme" parameter
  through `AppIntentConfiguration`. It's set by long-pressing the widget
  and choosing Edit Widget. They **can't** follow the in-app theme
  automatically because there's no App Group, and the UI says so.
- **Icons.** New alternate icons matching the themes, offered, never
  forced, when you pick a theme. This is gated on first confirming on a
  device that the existing PR #27 icon switching works.
- **Guard rails.**
  - `tools/lint-design-tokens.sh`, run in CI and locally in Git Bash,
    rejects raw colors outside an allowlist.
  - Contrast tests guarantee every built-in theme meets its thresholds.
  - Layout persistence and migration tests.
- **Zero change for existing users.** With no stored settings the app
  renders exactly as today. Every stored blob is versioned and optional,
  and falls back to the defaults when missing or unreadable.

## Capabilities

### New Capabilities

- `app-theming`: themes, appearance, style options, custom accent with
  contrast guarantees, accessibility adaptation, sharing, widget theme
  parameter, and icon suggestions.
- `screen-layout`: the card registry, Today, Log Food and Progress layout
  editing, presets, start tab, persistence and migration.

### Modified Capabilities

None. The existing `today-dashboard`, `app-icon-picker` and
`glanceable-surfaces` behavior is preserved by default. This change only
adds options on top.

## Non-goals

- **Live data in widgets, and widgets following the app theme
  automatically.** Both are impossible without an App Group (see
  `openspec/config.yaml` hard constraints). Revisit only if the owner pays
  for the Developer Program.
- **Per-person profiles on one phone.** Each person runs their own install
  on their own phone with their own Garmin account. Themes travel between
  them as share codes. Owner to confirm (open question).
- **Recoloring achievement rarity medals** (`BadgeMedallion`). Rarity colors
  carry meaning and stay fixed.
- **New gamification cards or banners.** Those stay with their own changes
  (`add-weekly-bingo`, `add-seasonal-events`, `add-journeys-and-records`,
  `add-food-collections`, `add-secret-achievements`,
  `add-sport-and-body-achievements`, `add-weekly-boss-and-streak-freezes`).
  They plug into the registry through `add-gamification-signals`'s slot
  views without any edit to their plans.
- **Hiding Garmin-only surfaces in standalone mode.** That's
  `add-standalone-mode`'s job. The registry only exposes an *availability*
  hook it can use.
- **Custom fonts bundled into the app, and free-form color editing of every
  token.** Only the accent is user-pickable. Everything else comes from
  curated, contrast-tested themes.
- **Reordering or hiding the Profile tab.** Settings live there.
- **iOS 26 Liquid Glass `.glassEffect` and Icon Composer icons.** They're
  optional follow-ups if the CI Xcode ships the iOS 26 SDK. The "Glass"
  card style here uses iOS 17 materials.

## Impact

Affected surfaces:

- **New package** `ios/AppearanceKit/`, with tests.
- **Theme tokens**: `ios/Shared/Theme.swift` becomes the palette plus a
  Classic fallback.
- **Design system**: `ios/GarminFood/DesignSystem/*`, plus a new
  `DesignSystem/Theming/` (environment keys, `ThemeStore`, styles).
- **Settings**: a new `Profile/Appearance/` (Appearance settings, theme
  gallery, accent picker, share and import).
- **Layout**: a new `GarminFood/Layout/` (card registry, `LayoutStore`,
  editor sheet).
- **Screens**: `Today/TodayView.swift`, `Catalog/FoodCatalogView.swift`,
  `Progress/ProgressViews.swift`, `ContentView.swift`, and a mechanical
  token migration across roughly 44 view files.
- **Widgets**: `GarminFoodWidget/*` (theme parameter).
- **Icons**: `GarminFood/AppIcons/` (new alternates).
- **Build and tooling**: `ios/project.yml` (package, alternate icons), a
  new AppearanceKit step and a lint step in `.github/workflows/build.yml`,
  and `tools/lint-design-tokens.sh` plus its allowlist.

No Garmin route is used, read or written. No new targets, so no App ID
quota is spent.

**Depends on**:

- Nothing, for waves 1 to 3.
- Wave 4's Progress registry assumes `add-gamification-signals` has merged,
  so that `ProgressSlotHost` exists. Before that, the registry covers only
  the built-in Progress cards.
- Wave 5's icon work depends on `add-app-icon-picker` task 4.2, the
  on-device check.

**Unblocks**:

- Every future card gets layout control for free by registering itself.
  That includes the gamification slot cards and anything standalone mode
  hides or shows.
