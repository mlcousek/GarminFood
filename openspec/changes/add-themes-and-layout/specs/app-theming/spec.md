## ADDED Requirements

### Requirement: Default look is unchanged

With no appearance settings stored, the system SHALL render every screen
with the Classic theme, whose color values equal the pre-change `Theme`
tokens. It SHALL use System appearance, Filled cards, Standard corners,
Comfortable density and Rounded numbers.

#### Scenario: Upgrade keeps today's look

- **WHEN** a user who has never opened Appearance settings installs the build that contains this change
- **THEN** the accent is `#F56B4A`, macro bars are `#4A8FE3`/`#8C66DB`/`#EDB033`, cards use the system secondary grouped background at the same corner radius, and the "Log it" button is the same coral as before

#### Scenario: Unreadable settings fall back without losing data

- **WHEN** the stored appearance blob cannot be decoded
- **THEN** the app shows the default look, keeps a copy of the unreadable blob under a quarantine key, writes a warning to Settings → Diagnostics, and tells the user once that their saved look was reset

### Requirement: Built-in themes

The system SHALL offer the built-in themes Classic, GF Teal, Forest, Ocean,
Sunset, Mono, High Contrast, Czech Autumn and Night Run. Each theme SHALL
define separate light and dark values for its color tokens, except Night
Run, which is dark only. Selecting a theme SHALL restyle every app screen
immediately, with no relaunch.

#### Scenario: Switching theme applies everywhere

- **WHEN** the user picks Forest in Settings → Appearance and then opens Today, Log Food and Progress
- **THEN** the tab bar tint, the primary buttons, the day switcher and the ring's default tint all use Forest's green accent, and no screen still shows coral

#### Scenario: Dark-only theme

- **WHEN** the user picks Night Run while the phone is in light mode
- **THEN** the app renders dark with a black background and a lime accent, and the appearance picker offers no Light option for this theme

### Requirement: Appearance mode per theme

The system SHALL let the user choose System, Light or Dark appearance. The
choice SHALL be remembered per theme and SHALL apply to every screen,
sheet and overlay in the app.

#### Scenario: Forced dark

- **WHEN** the user sets Classic to Dark while the phone is in light mode and opens the log-entry confirm sheet
- **THEN** both the Today screen and the sheet render in dark appearance

### Requirement: Contrast guarantees for non-Classic themes

For every built-in theme except Classic's documented exemptions, the
system SHALL keep:

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
Classic as the default. Widgets SHALL NOT follow the in-app theme
automatically. Appearance settings SHALL say so.

#### Scenario: Existing widget unchanged

- **WHEN** the owner updates the app with a Log Food widget already on the Home Screen
- **THEN** the widget keeps its coral gradient until he edits the widget and picks another theme

#### Scenario: App theme does not leak

- **WHEN** the app theme is changed to Forest
- **THEN** a widget configured as Classic still shows the coral gradient

### Requirement: Themes can suggest a matching app icon

When the user applies a theme that has a matching alternate icon different
from the current one, and the "Match app icon to theme" preference is Ask,
the system SHALL offer to switch the icon. It SHALL change the icon only
after the user confirms.

#### Scenario: Declining keeps the icon

- **WHEN** the user applies Forest and declines "Also switch the app icon?"
- **THEN** the Home Screen icon is unchanged and the theme is still applied

#### Scenario: Preference set to Never

- **WHEN** "Match app icon to theme" is Never and the user applies Sunset
- **THEN** no icon prompt appears
