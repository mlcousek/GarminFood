## MODIFIED Requirements

### Requirement: Level is a deterministic function of total XP

The system SHALL compute the user's level from their accumulated XP using a
fixed, deterministic threshold curve, with no configuration or randomness
involved. The curve SHALL have 150 levels, and the XP needed to go from
level `n` to level `n + 1` SHALL be `round(100 × 1.03087^(n − 1))`.

#### Scenario: Reaching a level threshold

- **WHEN** accumulated XP reaches or exceeds the threshold for the next level
- **THEN** the level increases accordingly and progress toward the following level is shown

#### Scenario: The documented thresholds

- **WHEN** the thresholds of levels 2, 10, 25, 50, 75, 100, 125 and 150 are computed
- **THEN** they are 100, 1,020, 3,481, 11,131, 27,491, 62,474, 137,285 and 297,264 XP

## ADDED Requirements

### Requirement: Levels end at 150

The system SHALL treat level 150 as the highest level. There SHALL be no
prestige level and no reset. Every level from 1 to 150 SHALL belong to
exactly one named tier, in English and Czech, and the tiers for levels 1–90
SHALL keep the names and ranges they had before this change.

#### Scenario: The last level

- **WHEN** accumulated XP is at or above the level 150 threshold
- **THEN** level 150 is shown, with no further level to progress toward

#### Scenario: A tier for every level

- **WHEN** any level from 1 to 150 is looked up
- **THEN** exactly one tier contains it, and level 150 is the tier "Legend"

### Requirement: The move to 150 levels never lowers a level

The system SHALL keep every user's accumulated XP unchanged when the curve
changes to 150 levels, and SHALL display a level no lower than the one
displayed before. Every level threshold of the new curve SHALL be at or
below the same level's threshold on every curve that shipped earlier.

#### Scenario: An existing ledger after the update

- **WHEN** a ledger of 3,000 XP that displayed level 20 is loaded by the new build
- **THEN** its XP is still 3,000 and level 22 is displayed

#### Scenario: Any XP total

- **WHEN** any XP total is mapped to a level on the new curve and on each earlier curve
- **THEN** the new level is never below the earlier one (capped at 150)

### Requirement: The change to 150 levels is announced once

The system SHALL show one moment, the first time a ledger written before
this change is loaded, saying that levels now go to 150 and that XP is
unchanged. It SHALL NOT show it again, and SHALL NOT show it on a new
install.

#### Scenario: First launch after the update

- **WHEN** an existing ledger is loaded by the new build for the first time
- **THEN** the "150 levels" moment is queued once, naming the user's level

#### Scenario: A new install

- **WHEN** the app starts with no ledger
- **THEN** no "150 levels" moment is shown
