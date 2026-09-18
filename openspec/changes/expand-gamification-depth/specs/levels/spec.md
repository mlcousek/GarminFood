## MODIFIED Requirements

### Requirement: Level is a deterministic function of total XP

The system SHALL compute the user's level from their accumulated XP using a fixed, deterministic threshold curve, with no configuration or randomness involved. The curve SHALL be tuned so that a realistic pattern of daily use produces new level-ups throughout at least a 2-3 year horizon, rather than becoming practically unreachable within the first year.

#### Scenario: Reaching a level threshold

- **WHEN** accumulated XP reaches or exceeds the threshold for the next level
- **THEN** the level increases accordingly and progress toward the following level is shown

#### Scenario: Multi-year reachability

- **WHEN** total XP is projected forward at a realistic sustained daily rate over a 2-3 year period
- **THEN** the projected level at that point is well past the game's early levels, and levels remain reachable (not asymptotically frozen) for years beyond that

## ADDED Requirements

### Requirement: A level carries a tier and title

The system SHALL associate every level with one of a small set of named tiers spanning the full level range, each with its own display title, so level progress reads as more than a bare number.

#### Scenario: Displaying a level

- **WHEN** the level screen or a level-up moment displays a level
- **THEN** it shows that level's tier title alongside the numeric level
