## MODIFIED Requirements

### Requirement: Levelling pace is fixed by an explicit XP budget

The system SHALL derive the level curve's growth factor from an explicit
table of expected daily XP per XP source, so that a typical consistent day
in the training experience (the always-on food sources plus the training
sources) reaches **level 150 after 1,540 days (±1 %)**. The first-level band
stays 100 XP and only the growth factor is solved. On that curve:

- level 10 is reached within 21 days of typical play;
- no single level takes more than 56 days of typical play;
- perfect play every day needs at least 2.9 years;
- three typical weeks followed by one poor week need at most 5 years.

The food-first experience SHALL use the same curve. Its always-on budget is
unchanged, so it reaches level 150 later than the training experience.

#### Scenario: Typical pace

- **WHEN** a typical training-experience day's budgeted XP is accumulated on the level curve
- **THEN** level 150 is reached within 1,525–1,555 days and level 10 within 21 days

#### Scenario: Budget and curve agree

- **WHEN** the level curve's growth factor is compared with the factor solved from the budget table
- **THEN** they differ by less than 0.0001

#### Scenario: A reward is changed without re-solving

- **WHEN** a reward constant changes so that its budget line changes but the growth factor literal is not updated
- **THEN** the budget test fails and reports the solved factor to use

#### Scenario: The slowest level

- **WHEN** the XP needed for the last level is divided by a typical day's XP
- **THEN** the result is at most 56 days

## ADDED Requirements

### Requirement: Training sources are budgeted and stay smaller than the food core

The system SHALL list every training XP source in the budget with its reward
and its assumed frequency for a poor week, a typical day and a perfect week.
The training sources together SHALL NOT exceed 60 % of the always-on food
budget, and no single training source SHALL exceed 15 % of it. Training
rewards SHALL NOT be scaled as an optional source.

#### Scenario: The training share

- **WHEN** the training lines of the budget are summed for a typical day
- **THEN** the sum is at most 60 % of the always-on food budget

#### Scenario: A training badge is unlocked

- **WHEN** a training badge unlocks while the training experience is on
- **THEN** it pays the full generic badge bonus, not a scaled one

#### Scenario: The scenario totals

- **WHEN** the budget is summed for the poor, typical and perfect scenarios
- **THEN** the totals are about 73.8, 192.9 and 277.5 XP a day
