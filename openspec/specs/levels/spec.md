# levels Specification

## Purpose
Give logging consistency a visible sense of progress through XP and levels, weighted toward rewarding consistency over sheer volume of entries.

## Requirements

### Requirement: Logging awards XP, with larger awards for consistency than volume

The system SHALL award a flat XP amount for each logged food entry, and SHALL award a larger XP amount for extending the current streak and for meeting a day's nutrition goal, than for logging an additional entry alone.

#### Scenario: Logging several entries in one sitting

- **WHEN** the user logs three food entries within a short time on the same day
- **THEN** each entry awards the flat per-log XP amount, without an escalating bonus for logging multiple entries at once

#### Scenario: Extending the streak

- **WHEN** a logged entry is the first for a new nutrition-day that extends the current streak
- **THEN** the XP awarded for that day includes the streak-extension bonus in addition to the flat per-log amount

### Requirement: Level is a deterministic function of total XP

The system SHALL compute the user's level from their accumulated XP using a fixed, deterministic threshold curve, with no configuration or randomness involved.

#### Scenario: Reaching a level threshold

- **WHEN** accumulated XP reaches or exceeds the threshold for the next level
- **THEN** the level increases accordingly and progress toward the following level is shown

### Requirement: Leveling up is a visible, animated moment

The system SHALL present a level-up with a distinct animated transition and haptic feedback, not a silent numeric update, unless Reduce Motion is enabled, in which case an equivalent non-animated confirmation SHALL still be shown.

#### Scenario: Crossing a level threshold

- **WHEN** a logging action causes the level to increase
- **THEN** the user sees an animated level-up moment with haptic feedback

#### Scenario: Reduce Motion is enabled

- **WHEN** a logging action causes the level to increase while Reduce Motion is enabled
- **THEN** the level-up is still confirmed to the user, without the full animated transition
