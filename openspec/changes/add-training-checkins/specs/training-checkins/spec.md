## ADDED Requirements

### Requirement: Today offers the morning check-in

In the training experience, when the vault connection has a device id and
the plan has the selected training day, the training card SHALL offer a
morning check-in with three choices, G (green), A (amber) and R (red),
each distinguished by letter and shape as well as colour and read by
VoiceOver with its meaning. Choosing one SHALL record `checkin.morning` for
that training day with the day's traffic-light session, if any, and SHALL
mark the choice and the matching option card. The option cards SHALL keep
opening the session detail and SHALL NOT record anything.

#### Scenario: The 4:00 check

- **WHEN** at 04:05 the owner taps A on Today, and today has a G/A/R session
- **THEN** `checkin.morning {light: amber, sessionId: <that session>}` is recorded for the training day, the A button is selected and the A option card is marked as matching the morning check

#### Scenario: A rest day

- **WHEN** the day has no session
- **THEN** the check-in is still offered and recorded without a session id

#### Scenario: No device id

- **WHEN** the connection is on but "Test connection" never succeeded
- **THEN** no check-in row is shown and Today stays read-only

### Requirement: Lock-screen Controls record the morning check-in

The system SHALL offer three Controls, Green, Amber and Red, in the existing
widget extension. Each SHALL open the app and record the check-in there for
the current training day, using the cached plan only, and SHALL fail with a
visible message when the vault connection is off or has no device id.

#### Scenario: From the lock screen

- **WHEN** the owner taps the Amber Control at 04:02, before the day boundary has passed in the plan's time zone at 03:00
- **THEN** the app opens and an amber check-in is recorded for today's training day

#### Scenario: Connection off

- **WHEN** the Control is tapped on an install without the vault connection
- **THEN** nothing is recorded and the Control reports that the vault must be connected first

### Requirement: Habits are ticked on and off

When ticking is allowed, each habit row on Today SHALL have an on/off
toggle for the selected training day, past or future. Toggling SHALL record
`habit.tick {date, habitId, done}`. A row SHALL show the phone's latest
tick, otherwise on when the projection counts the habit as done that day.

#### Scenario: Evening holds

- **WHEN** the owner turns "holds" on for today
- **THEN** `habit.tick {habitId: "holds", done: true}` is recorded and the toggle shows on

#### Scenario: Logging tomorrow

- **WHEN** the day switcher shows tomorrow and the owner ticks a habit
- **THEN** the tick is recorded for tomorrow's date

### Requirement: A session can be rated and annotated

When rating is allowed, the session detail SHALL let the owner set an RPE
from 1 to 10 and save a note of at most 2000 characters, recording
`session.rpe` and `session.note` for that session and its date, and SHALL
show the latest values with their delivery state.

#### Scenario: After the long run

- **WHEN** the owner opens the long run's detail, taps 7 and saves "Calf tight after 25 km"
- **THEN** both events are recorded and the detail shows RPE 7 and the note, "Saved on phone"

### Requirement: Training reminders prompt the check-in and the habits

In the training experience, with training reminders on, the system SHALL
schedule a local "How do you feel today?" reminder at 04:05 on each of today
and tomorrow that has a session with options and no check-in yet, and an
"Evening habits" reminder at 20:10 on each of those days with expected
habits not all ticked. It SHALL remove them when the check-in or the ticks
are recorded, when the switch is off, and in the food-first experience.

#### Scenario: Already checked in

- **WHEN** the owner checks in at 03:50 via the Control
- **THEN** today's 04:05 reminder is removed

#### Scenario: Food-first install

- **WHEN** an install has no vault connection
- **THEN** no training reminder is ever scheduled

### Requirement: The food-first experience is unchanged

The system SHALL NOT show any check-in, tick or rating control, record any
event, or schedule any training reminder in the food-first experience or
on a standalone install.

#### Scenario: The fiancée's install

- **WHEN** a standalone install opens Today and Settings
- **THEN** it looks and behaves exactly as before this change
