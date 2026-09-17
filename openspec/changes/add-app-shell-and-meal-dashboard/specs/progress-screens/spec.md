## Purpose

Give levels, streaks and challenges their own screens, so progress is something the user can explore and not just a single line on Today.

## ADDED Requirements

### Requirement: The level screen explains progress and how to earn XP

The system SHALL show the current level, total XP, XP into the current level and the XP needed for the next. It SHALL list the next levels' thresholds and the XP awarded for each action (logging, extending a streak, hitting a goal, completing a challenge).

#### Scenario: Mid-level

- **WHEN** the user has 250 XP
- **THEN** the screen shows the level that 250 XP falls in, the XP into it, and the XP still needed

### Requirement: The streak screen shows history and the longest streak

The system SHALL show the current streak, the longest streak ever reached, and a calendar of recent weeks marking each nutrition day as logged, missed, or covered by the grace rule. It SHALL use the same day boundary and grace rule as the current-streak calculation.

#### Scenario: A grace day inside the longest streak

- **WHEN** the history has five logged days, one missed day covered by grace, then four logged days
- **THEN** the longest streak is counted across the grace day, and the calendar marks that day as a grace day

#### Scenario: Two misses in one week

- **WHEN** two days in the same rolling week are missed
- **THEN** the second miss ends the streak, and the longest streak does not bridge it

### Requirement: The challenges screen shows active, available and completed challenges

The system SHALL show the active challenge with its progress and time remaining, every challenge in the catalog with its reward, and completed challenges with their completion date and XP. A challenge SHALL be recorded as completed when the app completes it.

#### Scenario: Completing a challenge

- **WHEN** the active challenge's condition is met
- **THEN** it appears under completed, with today's date and the XP it awarded

#### Scenario: Completed history survives relaunch

- **WHEN** the app is relaunched after a challenge was completed
- **THEN** the completed list still includes it

### Requirement: Goal history is visible

The system SHALL show, for recent days, whether the calorie and each macro goal was met, using the goal statuses already recorded.

#### Scenario: A day that met only protein

- **WHEN** a recorded day met the protein goal and no other
- **THEN** that day shows protein as met and the rest as not met

### Requirement: Celebrations respect Reduce Motion

Celebratory and repeating animations on progress UI SHALL be replaced with non-animated equivalents when Reduce Motion is enabled or celebrations are turned off.

#### Scenario: Reduce Motion is on

- **WHEN** Reduce Motion is enabled and the streak is shown
- **THEN** the flame does not pulse
