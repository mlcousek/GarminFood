## Why

`add-glanceable-surfaces` shipped one Home Screen widget
(`GarminFoodHomeWidget.swift`): a generic "Log Food" tile, static and
data-free by necessity (no App Group/Keychain Sharing on this free-tier
account -- see design.md D2, REVISED). That widget works, but its visual
framing is generic utility, not motivation. This app's whole gamification
layer (`Gamification/`) is built around the streak as the thing that keeps
someone coming back; the Home Screen is the highest-visibility real estate
this app has, and today nothing there references the streak at all. A
second, streak-themed widget variant -- same honest static contract, just a
flame motif and encouraging copy -- gives people a Home Screen tile that
feels like it's rooting for them, without pretending to know today's actual
streak count (which, per D2, no widget on this account ever can).

## What Changes

- Add a second Home Screen widget, `GarminFoodStreakWidget.swift`: a
  flame/ember-themed tile ("Keep your streak going" / "Log today"), static
  and data-free, `systemSmall` and `systemMedium`. Registered in
  `GarminFoodWidgetBundle.swift` alongside the existing
  `GarminFoodHomeWidget` -- both are offered; this does not replace or
  retire the generic one.
- Reuses the existing `GarminFoodDeepLink.Action.logFood` deep link (same
  "open straight into the food catalog, ready to log" destination the other
  two widgets already use) -- no new deep-link action, since logging today
  is exactly what keeps the streak alive.
- Reuses `Theme.flameGradient`/`Theme.ember` (already defined in
  `Shared/Theme.swift` for the app's own streak UI) so the widget visually
  matches the app's existing streak presentation rather than inventing a
  new palette.

## Capabilities

### Modified Capabilities

- `home-screen-widget` -- gains a second static variant (streak-themed)
  alongside the existing generic one. The capability's core contract (no
  live data, ever; single whole-widget tap target; Continuity availability)
  is unchanged and now explicitly covers both widgets.

### New Capabilities

None.

## Non-goals

- **A live streak count, streak-at-risk warning, or any other
  Garmin/local-data-derived value on this widget.** Same reason as the
  existing Home Screen widget: this process has no App Group, no Keychain
  Sharing, and therefore no channel to Garmin's credential or to the app's
  own local `LifetimeStatsStore`/streak state (confirmed blocked on-device,
  `errSecMissingEntitlement`/-34018, `add-garmin-auth-and-sync` task 6.4).
  The flame and copy are static encouragement, not a data display -- adding
  a real number later would require solving the same App-Group/shared-
  storage problem this whole widget category is built around not having,
  which is out of scope for this change.
- **Retiring or replacing `GarminFoodHomeWidget`.** Both widgets stay;
  which one (or both) ends up on the user's Home Screen is their choice,
  made in the system's own widget gallery, not something this app decides.
- **A matching streak-themed Lock Screen accessory or Control.** Out of
  scope here; `GarminFoodLockScreenWidget.swift` and the existing Controls
  already cover those surfaces and are untouched by this change.

## Impact

Affected surfaces: the widget extension target only (`ios/GarminFoodWidget/`,
new file `GarminFoodStreakWidget.swift`; `GarminFoodWidgetBundle.swift`
updated to register it). No changes to `ios/GarminFood/` (the app target),
`GarminKit`, `FoodLogCore`, or `Gamification`.

**Depends on**: `add-glanceable-surfaces` (the widget extension target,
`GarminFoodDeepLink`, and the D2 static-widget precedent this change
follows) and `add-gamification` (`Theme.flameGradient`/`Theme.ember`,
defined for the app's own streak UI and reused here as-is).

**Unblocks**: nothing further planned.
