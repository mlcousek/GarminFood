## ADDED Requirements

### Requirement: A projection is accepted only if the app can read its version

The system SHALL accept a fetched projection only when its `schema` is
`hub.projection` and its `schemaVersion` is 1. A projection whose
`schemaVersion` is higher SHALL NOT replace the last good one, and the
system SHALL tell the user on Today and Plan to update the app. Any other
unreadable projection SHALL NOT replace the last good one, SHALL be logged
once to Diagnostics, and SHALL be reported as a quiet notice with the date
of the plan still shown.

#### Scenario: The vault publishes version 2 in the v1 file

- **WHEN** the fetched `projection.v1.json` has `schemaVersion: 2`
- **THEN** Today and Plan keep showing the last good plan marked with its date, and both show "Update Jirka's Arc to read this plan"

#### Scenario: A file that is not a projection

- **WHEN** the fetched file has `schema: "something-else"`
- **THEN** the last good plan stays, Diagnostics has one `vault` line saying it is not a plan projection, and Plan shows "Couldn't read the latest plan" with the date of the plan shown

### Requirement: Decoding follows the v1 contract and tolerates what the app does not know

The system SHALL read the projection's fields at the names and locations of
the vault's projection v1 contract, including the season with its phases
and races, the selected phase as `plan`, per-week `phaseId`, `actual` and
`aiNote`, per-day `fuel`, `unplanned` and `habitsDone`, the workout library
and the test history. It SHALL ignore unknown fields, SHALL decode unknown
enumeration values as unknown without failing, SHALL treat `null`, an empty
list and a missing key alike, SHALL drop a list element that lacks its
identity or has a malformed date while keeping the rest of the file, and
SHALL summarise dropped elements in one Diagnostics line per fetch.

#### Scenario: The vault's example fixture

- **WHEN** the mirrored `projection.v1.example.json` is decoded
- **THEN** it decodes with no dropped element and every field the screens use has its fixture value

#### Scenario: The vault's minimal fixture

- **WHEN** the mirrored `projection.v1.minimal.json`, with no season and no plan, is decoded
- **THEN** it decodes with no dropped element and Today and Plan show "No active plan"

#### Scenario: A new session type

- **WHEN** a session has `type: "hike"`, unknown to this build
- **THEN** the projection loads and the session is shown with its title and a neutral type

#### Scenario: A session without an id

- **WHEN** one session in the week has no `id` and the others are valid
- **THEN** the other sessions are shown, the broken one is not, and Diagnostics says one session was skipped for a missing id

### Requirement: The last good plan is always available and its age is honest

The system SHALL decode the cached projection at launch without waiting for
the network, SHALL show it offline, and SHALL keep it when a fetch fails or
is rejected. It SHALL judge freshness from the projection's `asOf` and the
last successful sync, never from `generatedAt`: it SHALL say which day the
plan describes when `asOf` is earlier than the current training day, and
SHALL mark the plan as possibly out of date, without a banner, when no fetch
has succeeded for 24 hours.

#### Scenario: Offline morning

- **WHEN** the owner opens the app in airplane mode early in the morning after a successful sync the evening before
- **THEN** Today shows the day's session and options from the cached plan within a second

#### Scenario: Plan describes yesterday

- **WHEN** the cached projection's `asOf` is 2026-10-20 and the current training day is 2026-10-21
- **THEN** Today and Plan show "Plan as of Tue 20 Oct" and no banner

#### Scenario: Old generatedAt, fresh sync

- **WHEN** `generatedAt` is five days old but the last sync succeeded an hour ago and `asOf` is today
- **THEN** no freshness warning is shown

### Requirement: Text from the plan appears in the app's language

The system SHALL show localized plan text (titles, labels, notes, reasons)
in the app's language, using Czech (`cs`, then the vault's `cz` key) on a
Czech app, English on an English app, and otherwise the first non-empty
value. A plain string SHALL be shown as is in both languages.

#### Scenario: Czech phone, vault writes `cz`

- **WHEN** an option's label is `{ "en": "Easy 8 km flat", "cz": "Klidně 8 km po rovině" }` and the app runs in Czech
- **THEN** the option card shows "Klidně 8 km po rovině"

### Requirement: The training day follows the plan's time zone and day boundary

The system SHALL compute the current training day in the projection's
`athlete.tz` (the device's time zone when it is absent), SHALL treat a time
before `athlete.dayBoundaryHour` on today's date as the previous training
day, and SHALL use the selected date as is for any other date.

#### Scenario: Just after midnight

- **WHEN** the day boundary is 3 and the owner opens Today at 00:40 on 21 October in the athlete's time zone
- **THEN** the training card shows the sessions of 20 October
