## ADDED Requirements

### Requirement: Default layouts match today's screens

With no layout stored, the system SHALL show:

- **Today:** the day switcher, summary card with the ring, streak and
  level strip, fasting card when fasting is on, meal cards expanded, Log
  again, Log a meal, Weight & Water, day note, then the signature.
- **Log Food:** the shelves Quick pick, Favorites, Usual, Meals, Recent,
  then custom foods.
- **Progress:** today's card order.

Each screen keeps the same show-when-relevant rules as before.

#### Scenario: Upgrade keeps order

- **WHEN** a user who never edited a layout opens Today after upgrading
- **THEN** the cards appear in exactly the pre-change order and variants

#### Scenario: Empty shelf still hides

- **WHEN** there are no recent foods on today's date with the default layout
- **THEN** the Log again shelf is not shown, as before

### Requirement: Reorder and hide Today cards

The system SHALL let the user reorder, hide and show every Today card
except the day switcher. The day switcher stays pinned at the top. Changes
SHALL apply immediately and persist across relaunches.

#### Scenario: Move weight up

- **WHEN** the user drags Weight & Water above the meal cards in the layout editor and relaunches the app
- **THEN** Today shows Weight & Water above the meal cards

#### Scenario: Hide the day note

- **WHEN** the user hides the Day note card
- **THEN** Today no longer shows the note card, and showing it again restores it at the same position

#### Scenario: Day switcher cannot move

- **WHEN** the layout editor is open for Today
- **THEN** the day switcher row has no drag handle and no hide toggle

### Requirement: Per-card variants

The system SHALL offer these variants:

- summary card: Ring, Compact or Hero number
- meal cards: Expanded or Collapsed
- Weight & Water: Both, Weight only or Water only

A collapsed meal card SHALL still show its calories and macro bars and
open the meal detail when tapped.

#### Scenario: Collapsed meals

- **WHEN** the user sets meal cards to Collapsed
- **THEN** each meal card shows its header, calories and macro bars without entry rows, and tapping it opens that meal's detail screen with all entries

#### Scenario: Water only

- **WHEN** the user sets Weight & Water to Water only
- **THEN** Today shows the hydration card with its quick-add buttons and no weight card

### Requirement: Layout editor with live preview

The system SHALL provide an Edit layout sheet, reachable from Today's
toolbar and from Settings → Appearance → Layout. The sheet SHALL:

- list the cards with drag handles, visibility toggles and variant menus
- keep the screen underneath visible and updating while it is open at
  half height
- be fully operable with VoiceOver

#### Scenario: Live preview

- **WHEN** the user moves Log again to the top of the list with the sheet at half height
- **THEN** the Today screen visible behind the sheet shows Log again in its new position before the sheet is closed

#### Scenario: VoiceOver reorder

- **WHEN** a VoiceOver user uses the Move up action on the Day note row
- **THEN** the Day note moves up one position

#### Scenario: Unavailable card is explained

- **WHEN** fasting is off and the Today editor is open
- **THEN** the Fasting row is greyed out with the caption "Turn on fasting in Settings", and its visibility setting is kept

### Requirement: Presets and reset

The system SHALL offer the Today presets Full, Minimal and Athlete, and a
Reset action that restores the default layout after confirmation. Editing
after applying a preset SHALL mark the layout as Custom.

#### Scenario: Minimal preset

- **WHEN** the user applies Minimal on a day with recently logged foods
- **THEN** Today shows the day switcher, a compact summary, collapsed meal cards, Log again and the signature, and hides the streak strip, fasting, Log a meal, Weight & Water and the day note

#### Scenario: Reset

- **WHEN** the user confirms Reset in the Today editor
- **THEN** Today returns to the default order and variants

### Requirement: Log Food shelf layout

The system SHALL let the user reorder and hide the Log Food shelves Quick
pick, Favorites, Usual, Meals, Recent and Your custom foods. Picker modes
SHALL still hide shelves that cannot be used there. Search results SHALL
be unaffected.

#### Scenario: Favorites first

- **WHEN** the user moves Favorites above Quick pick and opens Log Food with an empty search
- **THEN** the Favorites shelf is the first shelf

#### Scenario: Picker rules still apply

- **WHEN** the catalog is opened to pick an ingredient for a meal preset
- **THEN** the Meals shelf is hidden regardless of the user's layout

### Requirement: Progress section layout

The system SHALL let the user reorder and hide Progress cards. That
includes each gamification feature card individually (Boss, Bingo,
Seasonal, Journeys, Records, Collections, Sport & Body, Secrets). A
feature card added by a later build SHALL appear at its default position
without resetting the user's layout.

#### Scenario: Hide one feature card

- **WHEN** the user hides Bingo but keeps Boss
- **THEN** Progress shows the Boss card and no Bingo card

#### Scenario: New card after update

- **WHEN** a build adds a new Progress card that is not in the user's stored layout
- **THEN** it appears right after the card that precedes it in the default order, and the user's other placements are unchanged

### Requirement: Layouts survive cards that come and go

The system SHALL keep the stored position and visibility of a card that is
missing from the current build or unavailable in the current data mode. It
SHALL restore that card at its remembered position when the card returns.

#### Scenario: Standalone mode round trip

- **WHEN** a card is unavailable while the app is in a mode that hides it, and the user later returns to a mode where it is available
- **THEN** the card reappears at the position and visibility it had before

### Requirement: Start tab

The system SHALL let the user choose whether the app opens on Today or
Progress. Widget and deep-link routes SHALL still open their own
destination.

#### Scenario: Open on Progress

- **WHEN** the start tab is Progress and the app is launched from its icon
- **THEN** the Progress tab is selected

#### Scenario: Widget still wins

- **WHEN** the start tab is Progress and the app is opened from the Log Food widget
- **THEN** the Log Food flow opens
