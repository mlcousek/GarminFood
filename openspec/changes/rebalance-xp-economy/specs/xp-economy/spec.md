## ADDED Requirements

### Requirement: Levelling pace is fixed by an explicit XP budget

The system SHALL derive the level curve's growth factor from an explicit
table of expected daily XP per always-on XP source, so that a typical active
day reaches level 84 after 1,095 days (±1%), level 10 within 7–21 days,
and level 50 within 150–300 days. The first-level band stays 100 XP and
only the growth factor is solved, so the level 10 and level 50 windows
describe what that curve delivers. Meeting later windows would need a
larger base, which would leave existing users weeks without a level-up.

#### Scenario: Typical pace

- **WHEN** a typical active day's budgeted XP is accumulated on the level curve
- **THEN** level 10 is reached within 7–21 days, level 50 within 150–300 days, and level 84 within 1,084–1,106 days

#### Scenario: Budget and curve agree

- **WHEN** the level curve's growth factor is compared with the factor solved from the budget table
- **THEN** they differ by less than 0.0001

#### Scenario: A reward is changed without re-solving

- **WHEN** a feature's reward constant changes so that its budget line changes but the growth factor literal is not updated
- **THEN** the budget test fails and reports the solved factor to use

### Requirement: Every gamification feature has a budget line

The system SHALL have exactly one budget line for every feature id in the
gamification feature registry.

#### Scenario: New feature without a budget line

- **WHEN** a feature is added to the registry without a budget line
- **THEN** the budget coverage test fails naming the missing feature id

### Requirement: Optional features do not speed up levelling

The system SHALL scale XP granted by optional, user-enabled sources by one
shared multiplier, `min(1, 0.005 × core daily XP / enabled optional daily
XP)`, with every positive grant paying at least 1 XP, so that enabling them
keeps the simulated days to reach level 84 within ±1% of the always-on
budget alone.

#### Scenario: An optional source is enabled

- **WHEN** an optional source that pays at most one grant a day is enabled and a typical day includes its scaled grant
- **THEN** the simulated days to level 84 are within ±1% of the always-on figure

#### Scenario: No optional source is enabled

- **WHEN** no optional source is enabled
- **THEN** the multiplier is 1 and no grant is scaled

### Requirement: A curve change never lowers the displayed level

The system SHALL display, after any change of growth factor, a level no
lower than the highest level previously reached under any earlier factor.

#### Scenario: Update with a steeper curve

- **WHEN** a user at level 40 under the previous factor updates to a build whose factor maps their XP to level 38
- **THEN** level 40 is still displayed and XP progress continues toward level 41

#### Scenario: The owner's ledger after the update

- **WHEN** a ledger of about 3,000 XP with a peak of level 20 updates to the budget-solved curve
- **THEN** level 20 stays displayed and level 21 arrives within 5 typical days
