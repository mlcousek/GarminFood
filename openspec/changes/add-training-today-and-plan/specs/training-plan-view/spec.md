## ADDED Requirements

### Requirement: The week agenda shows planned versus done as the vault computed it

The system SHALL show on the Plan tab's Week view one ISO week, Monday
first, with the name of the phase the week belongs to, the week's status,
outline kind and note, its targets and the vault's `actual` volume and
session counts, and for each of its seven days the morning light when
present, each session's sport, title, key target, status and done option,
the day's fuelling, and each unplanned activity. It SHALL NOT compute any
of these numbers itself. It SHALL page across the season's phases, showing
outline-only weeks with their target and a note that sessions aren't written
yet, and weeks outside every phase as having no plan.

#### Scenario: A week in progress

- **WHEN** the owner opens Week on Thursday of a week with a 60 km target whose `actual` is 34 km, 5 done and 1 missed
- **THEN** the header shows "Run 34 of 60 km" and the done and missed counts, and Thursday is marked as today

#### Scenario: Unplanned activity

- **WHEN** a day's only session is a run and the day also lists an unplanned ride
- **THEN** the ride appears as a muted unplanned row under that day and the run's status is unchanged

#### Scenario: A window week of the next phase

- **WHEN** the last window week has a `phaseId` of the next phase
- **THEN** its header shows the next phase's title, not the selected phase's

#### Scenario: Paging into the outline

- **WHEN** the owner pages past the last written week to a deload week targeting 60 km
- **THEN** the view shows "Deload", the 60 km target and that sessions for this week aren't written yet

### Requirement: The month calendar shows the plan like Garmin's calendar

The system SHALL show a Monday-first month grid with ISO week numbers and
each week's run target, and in each day cell up to three sport glyphs styled
by status (done, planned, missed, skipped) and unplanned activities, a
marker for the morning light, a flag on race days from the season's races
and a mark on today. Tapping a day SHALL list its sessions and unplanned
activities, and tapping a session SHALL open its detail.

#### Scenario: Missed and done sessions

- **WHEN** a month contains a missed Tuesday run and a done Wednesday gym session
- **THEN** Tuesday's glyph is styled as missed and Wednesday's as done, distinguishable without relying on colour alone

#### Scenario: Year boundary

- **WHEN** the owner views January 2027
- **THEN** the first row is labelled with ISO week 53 of 2026 and the grid starts on Monday 28 December

### Requirement: The session detail explains the session

The system SHALL show for a session its date, slot, sport, status and type
badge; for each option (or the session itself) its targets, the steps of its
workout and its watch state once published; heart-rate targets expressed in
the athlete's zones; the session's why, then its workout's why, then any
rule notes; where the session came from once published; the done option or
"Option not identified", the matched activity's sport, start, distance and
time and how it was recognised; the session's and day's fuelling; and for a
test, each result value labelled by the test's measures next to the previous
value from the test history. It SHALL open on the tapped option, otherwise
the done option, otherwise the morning-light option, otherwise G.

#### Scenario: Heart-rate target in zones

- **WHEN** option G targets `hrMax: 144` and the athlete's zone 2 is 129–144
- **THEN** the detail shows "≤144 bpm · Z2"

#### Scenario: Workout steps

- **WHEN** option A's workout has a 10-minute warm-up in Z1, then 4 intervals of 5 minutes in Z3 with 2 minutes' recovery
- **THEN** the detail lists "Warm-up 10 min · Z1" and "4 × 5 min · Z3, 2 min recovery"

#### Scenario: Test result against history

- **WHEN** a test session's result is 24 reps on one measure and the test history's previous value is 22
- **THEN** the detail shows 24 with the measure's label and unit, the previous 22 and that it improved

#### Scenario: Steps not published

- **WHEN** the option's workout has no steps
- **THEN** the detail shows the targets and "Steps not published", and no error

### Requirement: The habit ladder shows where each habit stands

The system SHALL list every habit step in order with its state (active,
next, later), its why, its start date or earliest start, its schedule in
words, its 14-day adherence as done of expected and a percentage against the
plan's gate (noting fewer recorded days, or "not recorded yet"), and a "gate
met" note when the plan says so. It SHALL offer no control to start, pause
or tick a habit.

#### Scenario: Gate met

- **WHEN** the active habit's 14-day window is 25 of 28 (89 %) against an 80 % gate and `gateMet` is true
- **THEN** the ladder shows "25 of 28 · 89 %" and says the next habit can start at the Sunday review

#### Scenario: Not recorded yet

- **WHEN** a habit's `window14` is null
- **THEN** the ladder shows "not recorded yet" for it instead of a percentage

### Requirement: Plan screens are read-only and reachable by link

The system SHALL NOT offer any control on the Plan tab that moves, swaps,
skips, checks in or rates a session. A `garminfood://plan?date=YYYY-MM-DD`
link SHALL open the Plan tab on the week containing that date.

#### Scenario: Link to a date

- **WHEN** the owner opens `garminfood://plan?date=2026-11-04`
- **THEN** the Plan tab opens on the week of 2 to 8 November 2026
