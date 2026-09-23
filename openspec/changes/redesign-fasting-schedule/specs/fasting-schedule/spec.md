## ADDED Requirements

### Requirement: A daily fasting window is configured in Settings

The system SHALL let the user enable fasting and set a daily "fast from" time
and a "fast until" time. The window SHALL repeat every day without any manual
start or stop. A window whose start time is later than its end time SHALL be
treated as crossing midnight.

#### Scenario: Overnight window

- **WHEN** the user sets fasting from 20:00 until 12:00
- **THEN** every day the fast runs from 20:00 until 12:00 the next day, and Settings shows "16 h fast · 8 h eating"

### Requirement: The home screen shows the current fasting phase

While fasting is enabled, the system SHALL show a fasting card on the home
screen. The card SHALL show whether the user is currently fasting or in the
eating window, the elapsed and remaining time, and when the phase changes.

#### Scenario: During the fast

- **WHEN** the window is 20:00–12:00 and it is 07:20
- **THEN** the card shows "Fasting", 11 h 20 m elapsed, and that eating opens at 12:00

#### Scenario: During the eating window

- **WHEN** the window is 20:00–12:00 and it is 16:50
- **THEN** the card shows "Eating window" closing at 20:00, 3 h 10 m left

### Requirement: Logging food during the fast shows a gentle warning

When the user is about to log food inside the fasting window, the system SHALL
show a non-blocking note on the confirm screen. The system SHALL still allow
the food to be logged.

#### Scenario: Snack at 09:00

- **WHEN** the window is 20:00–12:00 and the user confirms a food at 09:00
- **THEN** the confirm screen notes "You're fasting until 12:00"
- **AND** confirming still logs the food

### Requirement: Each day's fast is judged from the food log

The system SHALL mark a day's fast as kept when no food was logged inside that
day's window, and as broken otherwise. The system SHALL show a streak of
consecutive kept days.

#### Scenario: Broken fast

- **WHEN** food was logged at 09:00 inside a 20:00–12:00 window
- **THEN** that day is marked broken and the kept-days streak resets to 0
