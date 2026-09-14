## Purpose

Show a glanceable, always-accurate daily calorie ring with fast quick-add actions on the Home Screen, and make that same widget available on the Mac desktop at no extra engineering cost via Continuity.

## ADDED Requirements

### Requirement: The widget's displayed total is read from Garmin, not from local aggregation

The widget SHALL display the daily calorie total by reading it from Garmin's own daily summary, rather than from a value aggregated locally across processes, consistent with the sync capability's rule that Garmin is the source of truth.

#### Scenario: Widget displays today's total

- **WHEN** the widget renders its timeline entry for today
- **THEN** the calorie total shown reflects Garmin's daily summary as of the most recent successful read

### Requirement: Pending entries are shown provisionally and distinguished from confirmed data

An entry logged by the widget itself that has not yet been confirmed delivered to Garmin MAY be shown added on top of the last known Garmin total, but MUST be visually distinguished from confirmed data.

#### Scenario: An entry is queued but not yet confirmed

- **WHEN** the widget has a locally queued, undelivered entry from the current session
- **THEN** it may add that entry's value to the displayed total
- **AND** the addition is visually marked as pending

### Requirement: A quick-add tap updates the widget without waiting on the reload budget

Tapping a quick-add button on the widget SHALL trigger a timeline reload through the button's own app intent completion, so the displayed ring reflects the new entry without depending on WidgetKit's periodic reload budget.

#### Scenario: Tapping a quick-add tile

- **WHEN** the user taps a quick-add tile on the widget
- **THEN** the food is logged
- **AND** the widget's ring updates to reflect it immediately upon the tap completing

### Requirement: The widget remains available on the Mac desktop via Continuity

The widget's local data store SHALL use a file protection level compatible with Continuity widget sharing (not `NSFileProtectionComplete`), so the widget continues to be available as a Mac desktop widget when the same Apple Account is signed in on a paired Mac.

#### Scenario: Viewing the widget on a paired Mac

- **WHEN** the widget is added to a Mac's desktop or Notification Center while the iPhone is reachable
- **THEN** it renders and its quick-add actions function, executed on the iPhone and reflected back to the Mac
