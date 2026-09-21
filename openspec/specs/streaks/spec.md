# streaks Specification

## Purpose
Track and display consecutive-day logging consistency as a motivating, forgiving streak, computed entirely from the local log history without any network dependency.

## Requirements

### Requirement: A streak counts consecutive nutrition-days with at least one logged entry

The system SHALL compute the current streak as the number of consecutive nutrition-days, ending with the most recent day that has at least one logged food entry, using the Garmin nutrition-day boundary rather than local calendar midnight.

#### Scenario: Consecutive days logged

- **WHEN** the user has logged at least one food entry on each of the last 5 consecutive nutrition-days
- **THEN** the displayed streak is 5

#### Scenario: A gap with no grace remaining breaks the streak

- **WHEN** two or more nutrition-days within the same rolling 7-day window have no logged entries
- **THEN** the streak resets to count only from the first day logged after the second gap

### Requirement: One missed day per rolling week is forgiven

The system SHALL forgive exactly one missed nutrition-day per rolling 7-day window without breaking the streak, and SHALL NOT require the user to manually invoke or manage this forgiveness.

#### Scenario: A single missed day within a week

- **WHEN** exactly one nutrition-day within a rolling 7-day window has no logged entry, and entries exist on the days before and after
- **THEN** the streak continues counting across that missed day as if it had not occurred

#### Scenario: A second missed day within the same week

- **WHEN** a second nutrition-day within the same rolling 7-day window also has no logged entry
- **THEN** the streak resets, and the forgiveness is not applied a second time within that window

### Requirement: The streak is visibly at risk before it breaks

The system SHALL distinguish, in its display, a streak that is "safe" (today already logged) from one that is "at risk" (yesterday logged, nothing logged yet today), so the user can act before losing progress.

#### Scenario: Nothing logged yet today, streak still intact

- **WHEN** the most recent logged nutrition-day is yesterday and nothing has been logged for the current nutrition-day yet
- **THEN** the streak display shows an "at risk" state rather than an identical "safe" state
