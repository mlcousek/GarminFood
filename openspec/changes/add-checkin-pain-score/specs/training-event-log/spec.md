## ADDED Requirements

### Requirement: The morning check-in carries the pain score in the contract's shape

`checkin.morning` SHALL carry `pains`, written as `null` when the pain was
not asked and otherwise as a list of `{site, score, note}` objects:
`site` one of `achilles-left`, `achilles-right`, `knee-left`, `knee-right`,
`other`; `score` a number 0-10 in steps of 0.5, written without a fraction
when whole; `note` a string of 1-200 characters or `null`. A payload with
a score off the half-step grid or out of range, or a blank or too long
note, SHALL be refused before anything is recorded. Reading an event, an
unknown site SHALL be read as `other`.

#### Scenario: Golden bytes

- **WHEN** the app encodes a check-in with the left Achilles at 5.5 with a note and the right knee at 1
- **THEN** the payload is `{"date":…,"light":"amber","option":"A","pains":[{"note":"…","score":5.5,"site":"achilles-left"},{"note":null,"score":1,"site":"knee-right"}],"sessionId":…}` byte for byte

#### Scenario: Not asked

- **WHEN** a Control records a check-in
- **THEN** its payload has `"pains":null`

#### Scenario: Off the grid

- **WHEN** a draft would record a score of 4.3
- **THEN** recording is refused and nothing is written

### Requirement: A later check-in keeps or replaces the day's pain like the vault

The phone's overlay SHALL take, per training day, the `pains` of the
latest check-in of that date that carries them: a later check-in without
`pains` keeps the earlier answer, and one with `pains`, `[]` included,
replaces it. The phone's answer SHALL win over the projection's `day.pains`
while the event is kept.

#### Scenario: Keep

- **WHEN** a check-in with `pains` is followed by one of the same date without
- **THEN** the day still shows the first check-in's pains, with the new light

#### Scenario: Replace with nothing

- **WHEN** a later check-in of the same date has `pains: []`
- **THEN** the day's pain is "none"
