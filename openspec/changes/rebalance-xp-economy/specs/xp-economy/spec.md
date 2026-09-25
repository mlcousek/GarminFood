## ADDED Requirements

### Requirement: Levelling pace is fixed by an explicit XP budget

The system SHALL derive the level curve's growth factor from an explicit
table of expected daily XP per always-on XP source, so that a typical active
day reaches level 84 after 1,095 days, level 10 within 14–35 days, and
level 50 within 270–460 days.

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

The system SHALL scale XP granted by an optional, user-enabled source so
that enabling it keeps the simulated days to reach level 84 within ±1% of
the always-on budget alone.

#### Scenario: Supplements enabled

- **WHEN** the supplements feature is enabled and a typical day includes its expected supplement XP
- **THEN** the simulated days to level 84 are between 1,084 and 1,106

### Requirement: A curve change never lowers the displayed level

The system SHALL display, after any change of growth factor, a level no
lower than the highest level previously reached under any earlier factor.

#### Scenario: Update with a steeper curve

- **WHEN** a user at level 40 under the previous factor updates to a build whose factor maps their XP to level 38
- **THEN** level 40 is still displayed and XP progress continues toward level 41
