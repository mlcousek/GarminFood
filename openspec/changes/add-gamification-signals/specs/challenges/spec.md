## ADDED Requirements

### Requirement: Rotation favours curated and real-world challenges over number ladders

The system SHALL select the next long-running challenge by a deterministic
weighted pick in which hand-authored templates have weight 2, signal-based
real-world templates have weight 3, at most two tiers of each number-ladder
family (per macro or meal axis) have weight 1, and all other ladder tiers
have weight 0. Templates with weight 0 SHALL remain defined so that active
challenges, completion history and earned achievements referring to them
keep working. The last 8 activated templates SHALL be excluded from the
pick. A template whose data requirement (macros, water or activities) is not
met by any of the last 14 days SHALL NOT be picked.

#### Scenario: Ladder tier trimmed from rotation

- **WHEN** the rotation picks the next challenge
- **THEN** it never picks "log-streak-4" (a trimmed ladder tier)

#### Scenario: Same inputs, same pick

- **WHEN** the rotation is evaluated twice with the same time, history and signals
- **THEN** it picks the same template both times

#### Scenario: No water data

- **WHEN** no hydration data exists in the last 14 days
- **THEN** "Hydration Station" is not picked

#### Scenario: "Complete every challenge" stays achievable

- **WHEN** the owner has completed every template with non-zero rotation weight
- **THEN** the "complete every challenge" achievement unlocks, even though trimmed ladder tiers were never completed

### Requirement: Real-world challenges are evaluated from day signals

The system SHALL evaluate signal-based challenges from the per-day signals
aggregate within the challenge window, counting a day only when the
challenge's rule holds for that day, and SHALL show progress as days
satisfied out of days required.

#### Scenario: Something Fishy

- **WHEN** "Something Fishy" (fish on 2 days within 7) is active and the owner logs "Losos na grilu" on Tuesday and "Tuňákový salát" on Friday
- **THEN** the challenge completes on Friday and awards its XP once

#### Scenario: A day without macro data

- **WHEN** "Fibre Fanatic" is active and a day has an entry without known fibre
- **THEN** that day does not count toward the challenge and is not shown as failed
