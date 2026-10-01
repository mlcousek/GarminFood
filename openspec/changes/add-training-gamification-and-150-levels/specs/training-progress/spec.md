## ADDED Requirements

### Requirement: The level card shows the way to 150

The system SHALL show, on the Progress tab's level card, the current level
out of 150 with a bar over the whole range, in both experiences.

#### Scenario: Level 22

- **WHEN** the level is 22
- **THEN** the card says "Level 22 of 150" and the bar is filled to 22 of 150

### Requirement: Progress has a training section in the training experience

In the training experience the system SHALL show a training section on the
Progress tab with this week's check-ins, kept days and strength sessions,
the current check-in streak, habit streak and run of kept weeks, and every
training ladder with its count and its next step. The section SHALL NOT be
shown in the food-first experience.

#### Scenario: A ladder in progress

- **WHEN** 31 sessions were done as planned
- **THEN** the sessions row shows 31 and the next step, 100

#### Scenario: A finished ladder

- **WHEN** a ladder's last step is reached
- **THEN** its row shows the count and that it is complete

#### Scenario: Food-first

- **WHEN** the food-first experience is on
- **THEN** the Progress tab has no training section

### Requirement: Training XP shows soon after the action

The system SHALL evaluate training rewards after a check-in, a habit tick or
a session rating is recorded on the phone, without waiting for the network.

#### Scenario: Checking in

- **WHEN** the morning check-in is saved
- **THEN** its XP is granted in the same session, before the plan file is fetched again
