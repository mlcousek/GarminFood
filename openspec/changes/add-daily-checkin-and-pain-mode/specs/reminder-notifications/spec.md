## ADDED Requirements

### Requirement: The morning check-in reminder is planned on every day

In the training experience, with training reminders on and recording
allowed, the system SHALL plan a local "How do you feel today?" reminder
for each day of the next seven (today included) that has no check-in light
yet -- whether the day has a session with options, is a rest day, belongs
to a week that is not written or there is no plan at all -- and SHALL leave
out a reminder whose time has already passed. Its body SHALL be the short
"Green, amber or red?", and in pain mode SHALL also ask for the pain score.
The reminder for a day SHALL be removed once that day has a check-in. The
evening habits reminder SHALL be planned for each of those days whose
expected habits (a day skeleton's included) are not all ticked.

#### Scenario: A rest day

- **WHEN** tomorrow is a rest day without a check-in
- **THEN** a check-in reminder is pending for tomorrow morning

#### Scenario: No plan

- **WHEN** the projection has no plan and nothing is checked in
- **THEN** seven check-in reminders are pending, one per day, each with the body "Green, amber or red?"

#### Scenario: Pain mode wording

- **WHEN** pain mode is on
- **THEN** the reminder's body is "Green, amber or red? Add your pain score too."

#### Scenario: Checked in

- **WHEN** the owner checks in for today
- **THEN** today's check-in reminder is removed and tomorrow's stays

### Requirement: The training reminders fire at the owner's times

The notification settings SHALL offer, next to the training reminders
switch, a time for the check-in reminder and a time for the habits
reminder, 04:05 and 20:10 until changed. The chosen times SHALL be kept
across launches and SHALL be used for every planned training reminder;
changing a time SHALL replace the pending reminders at the old time with
ones at the new time. A stored value outside a day SHALL be clamped into
it.

#### Scenario: Defaults

- **WHEN** the owner never changed the times
- **THEN** the check-in reminder is planned at 04:05 and the habits reminder at 20:10

#### Scenario: A later morning

- **WHEN** the owner sets the check-in reminder to 06:30
- **THEN** every pending check-in reminder fires at 06:30, none remains at 04:05, and the time is still 06:30 after the app restarts
