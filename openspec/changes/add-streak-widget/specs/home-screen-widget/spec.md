## MODIFIED Requirements

### Requirement: The widget shows no live or cached data of any kind

`add-garmin-auth-and-sync` task 6.4 confirmed there is no App Group and no
Keychain Sharing on this account (`errSecMissingEntitlement`/-34018,
confirmed live, on both read and write). WidgetKit's refresh mechanism
(`WidgetCenter.reloadTimelines()`) does not hand a widget a value from the
app -- it tells the widget to re-run its own `getTimeline()` in its own
isolated process, which has no channel to anything the app knows and cannot
authenticate to Garmin on its own. This applies identically to every Home
Screen widget this app offers, not just the original generic one: there is
no version of any of them that shows a real number "eventually"; the system
SHALL NOT attempt to fetch, cache, or display any Garmin-sourced or
locally-aggregated value (including a streak count) in any Home Screen
widget. Each is a static icon, label, and (where applicable) fixed
decorative background only.

#### Scenario: Widget renders

- **WHEN** any Home Screen widget this app offers renders its timeline
  entry
- **THEN** the content shown is identical regardless of the actual state of
  the user's Garmin account or local logging history (streak count
  included)
- **AND** no network request and no read of the app's local data occurs as
  part of rendering it

## ADDED Requirements

### Requirement: A streak-themed static variant is offered alongside the generic widget

The system SHALL offer a second Home Screen widget with streak-themed visual
framing (a flame motif and encouraging static copy, e.g. "Keep your streak
going" / "Log today") as an alternative to the generic "Log Food" widget,
subject to the same no-live-data and single-tap-target requirements as every
other widget in this capability. This widget SHALL NOT display an actual
streak count, streak-at-risk state, or any other value derived from Garmin
or local data -- its flame and copy are static encouragement, not a data
display.

#### Scenario: Choosing between widget variants

- **WHEN** the user adds a GarminFood widget from the system's widget
  gallery
- **THEN** both the generic "Log Food" widget and the streak-themed widget
  are offered as separate choices
- **AND** either can be placed on the Home Screen independently of the
  other, including both at once

#### Scenario: Tapping the streak-themed widget

- **WHEN** the user taps the streak-themed widget
- **THEN** the app opens straight into the food catalog, ready to log (the
  same destination `GarminFoodDeepLink.Action.logFood` already drives the
  other widgets to), since logging today is what keeps the streak alive
