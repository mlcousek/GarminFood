## ADDED Requirements

### Requirement: The home Target is the fixed calorie goal

The system SHALL show the account's base calorie goal (Garmin `calorieGoal`)
as the home-screen Target, not the activity-adjusted goal, and SHALL compute
the ring's percentage against that fixed goal.

#### Scenario: A run does not move the target

- **WHEN** the user burns 600 active kcal on a run and the base goal is 2300
- **THEN** the Target still reads 2300 kcal and the ring percentage is consumed ÷ 2300

### Requirement: Active calories are shown under the Target

The system SHALL show the selected day's active calories burned under the
Target, as information only. The value comes from the `activeKilocalories`
field of `GET /usersummary-service/usersummary/daily?calendarDate={date}`
(live-verified 2026-09-23). If that read fails, the system SHALL hide the line
without showing an error.

#### Scenario: Active calories shown

- **WHEN** Garmin reports 290 active kcal for today
- **THEN** the home screen shows "Active today: 290 kcal" under the Target

#### Scenario: Route unavailable

- **WHEN** the daily summary read fails
- **THEN** the active line is hidden and the rest of the card renders normally

### Requirement: The calorie ring colour reflects progress in steps

The system SHALL colour the calorie ring by the percentage of the Target
eaten, using these steps:

| % of Target | Colour |
|---|---|
| under 50% | cool grey-blue |
| 50% to under 80% | orange |
| 80% to under 95% | yellow |
| 95% to 105% inclusive | green |
| over 105% up to 115% | orange |
| over 115% | red |

#### Scenario: Hitting the goal band

- **WHEN** the user has eaten 2250 kcal of a 2300 kcal Target (97.8%)
- **THEN** the ring is green

#### Scenario: Well over the goal

- **WHEN** the user has eaten 2700 kcal of a 2300 kcal Target (117%)
- **THEN** the ring is red

### Requirement: The Profile header shows the owner's real name

The system SHALL show Garmin's `fullName` in the Profile header, falling back
to `displayName` and then to "GarminFood". It SHALL never show a UUID-like
identifier when a full name is available.

#### Scenario: Account whose displayName is a UUID

- **WHEN** socialProfile returns displayName "f8c8e6e5-…" and fullName "Jiří Mlčoušek"
- **THEN** the Profile header reads "Jiří Mlčoušek"
