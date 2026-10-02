## ADDED Requirements

### Requirement: Day skeletons are decoded and a date is looked up in one place

The projection's top-level `days` SHALL be decoded as a list of days with
the same decoder as a plan week's days, tolerantly: an absent, `null` or
malformed list reads as empty, a broken day is dropped and recorded, the
list is kept in date order, and a day whose date a plan week already holds
(or that repeats an earlier skeleton) is dropped. The list SHALL be read
whether or not `plan` is null. A date SHALL be looked up in the written
weeks of the plan first and among the skeletons second, and every screen,
reminder and reward fact that needs "the day" SHALL use that one lookup.

#### Scenario: A day of an unwritten week

- **WHEN** the plan has written weeks W41 to W44 and `days` holds 2030-11-04 to 2030-11-17
- **THEN** looking up 2030-11-05 returns its skeleton with no sessions and its expected habits, and looking up 2030-10-23 returns the written week's day with its sessions

#### Scenario: No plan at all

- **WHEN** `plan` is null and `days` holds the 42 dates of the window
- **THEN** every one of those dates is found, and a date outside them is not

#### Scenario: A file from before the change

- **WHEN** the file has no `days` key
- **THEN** it decodes with no skeletons and nothing else changes

#### Scenario: A skeleton repeats a planned date

- **WHEN** `days` contains a date that a written week also holds
- **THEN** the skeleton is dropped and the written week's day is the one found

### Requirement: Pain mode is decoded tolerantly

`athlete.painMode` SHALL be decoded as `{ active, since, sites, reason,
clearsAfter }`: a missing object reads as "not in pain mode", an `active`
that is not a boolean reads as false, an unknown site reads as `other`
(each site once), an unknown `reason` is kept as unknown, and a malformed
date reads as absent. Decoding it SHALL never fail the file.

#### Scenario: Active pain mode

- **WHEN** the file has `painMode: { active: true, since: "2030-10-14", sites: ["achilles-left", "knee-right"], reason: "light", clearsAfter: "2030-10-30" }`
- **THEN** pain mode is active since 14 Oct with those two sites, the reason "light" and 30 Oct as the earliest clearing morning

#### Scenario: Broken values

- **WHEN** `active` is the string "yes", `reason` is "vibes" and `sites` contains "hip"
- **THEN** pain mode reads as inactive, the reason as unknown and the site as `other`

### Requirement: A day's fuel is on every day and a carb-load day is its kind

Every day's `fuel` SHALL be decoded with `kind` (`carb-load`, `daily`, or
unknown), `raceId`, `carbsGPerKg` as one number or as a `{ min, max }`
band, `carbsG`, `proteinGPerKg`, `fasting` with `fastingReasons`, `load`,
`plannedMin` and `rules`, every field lenient and every enumeration open.
A day SHALL count as a carb-load day only when its fuel's `kind` is
`carb-load` -- or, for a fuel without a `kind`, when it carries the single
number or the grams and no band -- and never merely because a fuel is
present.

#### Scenario: A daily fuel is not a carb load

- **WHEN** a day's fuel is `{ kind: "daily", carbsGPerKg: { min: 5, max: 7 }, proteinGPerKg: 1.6, fasting: "off", fastingReasons: ["build-week", "long-session"], load: "moderate", plannedMin: 60 }`
- **THEN** it decodes as a band of 5 to 7 g/kg with fasting off for two reasons, the day is not a carb-load day and no carb-load line is shown for it

#### Scenario: A carb-load day

- **WHEN** a day's fuel is `{ kind: "carb-load", raceId: "valley-30k-2030", carbsGPerKg: 8, carbsG: 560 }`
- **THEN** the day is a carb-load day and shows "Carb load: 560 g carbs (8 g/kg)"

#### Scenario: Unknown values

- **WHEN** a fuel has `kind: "snack"`, `load: "monster"` and a fasting reason "moon"
- **THEN** each is kept as unknown, the day is not a carb-load day and fasting is not read as off

### Requirement: Fields the app does not use yet never break decoding

The projection fields added to v1 on 2026-10-01 that this app does not show
yet -- `athlete.gate`, the load fields of `week.actual`, `unplanned[].flag`,
`session.feedback.pains`, `done.manual`, the `manual` values of
`done.source` and `done.matchedBy`, top-level `notices`, and each habit's
`streak`, `history` and `adherence` -- SHALL be ignored or kept as unknown
values, and a file carrying them SHALL decode with no dropped element. A
session done without a watch (`done.source: "manual"`, no activity) SHALL
read as done.

#### Scenario: The vault's example of 2026-10-01

- **WHEN** the mirrored example projection is decoded
- **THEN** nothing is dropped, the gym session marked done by hand reads as done with an unknown source and no activity, and the phone's acknowledged sequence is 31

#### Scenario: Event types this build does not write

- **WHEN** the mirrored event example with `test.gate` and `session.done` lines is decoded
- **THEN** all 31 lines are valid, those types read as "other", and an RPE that carries `pains` reads as the RPE it is
