## ADDED Requirements

### Requirement: GF Teal is the default look

With no appearance settings stored, the system SHALL render every screen
with the GF Teal theme, which matches the primary app icon. It SHALL use
System appearance, Filled cards, Standard corners, Comfortable density and
Rounded numbers. The pre-change look SHALL remain available as the Classic
Coral theme, whose color values equal the pre-change `Theme` tokens.

#### Scenario: Upgrade switches to GF Teal

- **WHEN** a user who has never opened Appearance settings installs the build that contains this change
- **THEN** the accent, the tab bar tint and the "Log it" button use GF Teal's teal instead of coral

#### Scenario: Classic Coral restores the old look

- **WHEN** the user picks Classic Coral in Settings → Appearance
- **THEN** the accent is `#F56B4A`, macro bars are `#4A8FE3`/`#8C66DB`/`#EDB033`, and cards use the system secondary grouped background, exactly as before this change

#### Scenario: Unreadable settings fall back without losing data

- **WHEN** the stored appearance blob cannot be decoded
- **THEN** the app shows the default look, keeps a copy of the unreadable blob under a quarantine key, writes a warning to Settings → Diagnostics, and tells the user once that their saved look was reset

### Requirement: Built-in themes

The system SHALL offer 13 built-in themes, each paired with an app icon:
GF Teal, Classic Coral, Ocean, Forest, Sunset, Slate and High Contrast
(light and dark); Indigo Night, Berry, Graphite and Gold (dark only); and
Pastel and Citrus (light only). Each theme's brand colors SHALL be derived
from its icon. Selecting a theme SHALL restyle every app screen
immediately, with no relaunch.

#### Scenario: Switching theme applies everywhere

- **WHEN** the user picks Forest in Settings → Appearance and then opens Today, Log Food and Progress
- **THEN** the tab bar tint, the primary buttons, the day switcher and the ring's default tint all use Forest's green accent, and no screen still shows teal

#### Scenario: Dark-only theme

- **WHEN** the user picks Gold while the phone is in light mode
- **THEN** the app renders dark with near-black surfaces and a warm gold accent

#### Scenario: Light-only theme

- **WHEN** the user picks Pastel while the phone is in dark mode
- **THEN** the app renders in light appearance

### Requirement: Appearance mode

The system SHALL let the user choose System, Light or Dark appearance. The
choice SHALL apply to every screen, sheet and overlay in the app. For a
theme that supports only one appearance, that appearance SHALL be used and
the picker SHALL be disabled with an explanation.

#### Scenario: Forced dark

- **WHEN** the user sets Dark with Classic Coral active while the phone is in light mode and opens the log-entry confirm sheet
- **THEN** both the Today screen and the sheet render in dark appearance

#### Scenario: Picker disabled for a single-appearance theme

- **WHEN** Graphite is active
- **THEN** the appearance picker is disabled and says the theme is dark only

### Requirement: Contrast guarantees for non-Classic themes

For every built-in theme except Classic Coral's documented exemptions, the
system SHALL keep, after automatic fitting:

- text on the accent at 4.5:1 or more
- the accent against card and background surfaces at 3:1 or more
- each macro, water, state and calorie-band color against card surfaces
  at 3:1 or more

in both light and dark appearance.

#### Scenario: Button label readable in Ocean light mode

- **WHEN** Ocean is active in light mode
- **THEN** the "Log it" label color on the accent fill measures at least 4.5:1

#### Scenario: Classic exemptions cannot grow silently

- **WHEN** a change makes another Classic token fall below its threshold
- **THEN** the AppearanceKit test suite fails in CI

### Requirement: Custom accent with automatic contrast fitting

The system SHALL let the user pick a custom accent color on top of any
theme. When the picked color falls below the accent contrast threshold in
light or dark appearance, the system SHALL use a lightness-adjusted color
of the same hue for that appearance and show the adjusted swatch. The
user's original pick SHALL be kept. The system SHALL warn when the pick is
visually too close to a macro color.

#### Scenario: Too-light accent in light mode

- **WHEN** the user picks lime `#C6F432` as the accent while in light appearance
- **THEN** buttons and tints use a darker lime that measures at least 3:1 against white, button labels switch to whichever of black or white contrasts more, and the picker shows "Adjusted for light mode"

#### Scenario: Accent collides with a macro

- **WHEN** the user picks a purple within the distinctness threshold of the protein color
- **THEN** the picker shows a warning that protein bars may be hard to tell apart, and still lets the user keep the color

### Requirement: Style options

The system SHALL offer these options, each applying app-wide immediately:

- card style: Filled, Elevated, Outlined or Glass
- corner shape: Sharp, Standard or Round
- density: Comfortable or Compact
- number font: Rounded, Default, Serif or Monospaced
- an optional gradient header on Today
- macro colors: Standard or Colour-blind safe

#### Scenario: Outlined cards

- **WHEN** the user selects Outlined
- **THEN** every card on Today and Progress draws a hairline border on the screen background instead of a filled surface

#### Scenario: Colour-blind safe macros

- **WHEN** the user selects Colour-blind safe macro colors
- **THEN** carbs, protein and fat bars use blue, vermillion and yellow-ochre, and their "C/P/F" letters remain visible

### Requirement: Accessibility settings are respected

The system SHALL adapt the resolved theme to accessibility settings in
four ways:

- With Increase Contrast on, every theme color SHALL be raised to 4.5:1
  or more against surfaces, and outlined borders SHALL thicken.
- With Reduce Transparency on, the Glass card style and the gradient
  header SHALL render opaque.
- With Differentiate Without Color on, the colour-blind-safe macro colors
  SHALL be used.
- Numeric displays SHALL scale with Dynamic Type.

#### Scenario: Increase Contrast fixes Classic's accent

- **WHEN** Increase Contrast is on and Classic is active in light appearance
- **THEN** the accent and the "Log it" button fill are darkened so the label measures at least 7:1

#### Scenario: Glass under Reduce Transparency

- **WHEN** the Glass card style is selected and Reduce Transparency is on
- **THEN** cards render with the solid Filled surface

#### Scenario: Large text

- **WHEN** Dynamic Type is set to an accessibility size
- **THEN** the weight and hydration hero numbers grow with the text size instead of staying at 72 pt

### Requirement: Share a theme as a code

The system SHALL export the current theme, custom accent, style options,
appearance and optionally the Today layout as a text code starting with
`GFT1.`, as a `garminfood://theme` link and as a QR image. It SHALL import
a code or link only after showing a preview with Apply and Cancel. The
code SHALL contain no personal or food data.

#### Scenario: Fiancée imports the owner's theme

- **WHEN** the owner shares his code and it is pasted with the Paste button on another phone
- **THEN** a preview of the theme appears, and tapping Apply makes that phone's app use the same theme, accent and style

#### Scenario: Invalid code

- **WHEN** a truncated or tampered code is pasted
- **THEN** the app says the code couldn't be read and changes nothing

#### Scenario: Code from a newer build

- **WHEN** a code names a theme this build does not have
- **THEN** the preview says the theme is unknown and offers to apply the rest of the settings on Classic

### Requirement: Widgets are themed per widget

The system SHALL let each Home Screen widget choose its theme from the
built-in list through the widget's own Edit Widget configuration, with
GF Teal (the default theme, which unconfigured widgets already show) as the
default. Widgets SHALL NOT follow the in-app theme automatically.
Appearance settings SHALL say so.

#### Scenario: Existing widget unchanged

- **WHEN** the owner updates the app with a Log Food widget already on the Home Screen
- **THEN** the widget keeps its GF Teal gradient until he edits the widget and picks another theme

#### Scenario: App theme does not leak

- **WHEN** the app theme is changed to Forest
- **THEN** a widget configured as Classic still shows the coral gradient

### Requirement: App icon follows the theme

The system SHALL offer 11 alternate app icons in the "GF / by Jirka"
gradient style, plus the primary icon, on the Appearance page. A "Match app
icon to theme" toggle, on by default, SHALL switch the app icon to the
selected theme's icon when a theme is picked. The icon SHALL remain
selectable independently of the theme.

#### Scenario: Picking a theme switches the icon

- **WHEN** "Match app icon to theme" is on and the user picks Sunset
- **THEN** the app asks iOS to switch to the Sunset icon, and iOS shows its own icon-changed alert

#### Scenario: Toggle off keeps the icon

- **WHEN** "Match app icon to theme" is off and the user picks Ocean
- **THEN** the Home Screen icon is unchanged and the theme is still applied

#### Scenario: A removed alternate icon resets

- **WHEN** the app launches with an alternate icon from a previous build that no longer exists
- **THEN** the app resets to the primary icon
