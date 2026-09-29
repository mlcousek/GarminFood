## ADDED Requirements

### Requirement: A phase screen shows where the phase stands

The system SHALL show for a phase its title, kind, status, date range and
where today falls in it: the week of the phase and the days left while it
runs, the days until it starts before it, or that it is finished once it
is closed or its period has ended. It SHALL open from the phase's row on
the Season view and from a race's anchoring phase.

#### Scenario: A running phase

- **WHEN** today is 23 October 2030 and the phase runs from 14 October 2030 to 31 January 2031
- **THEN** the header reads "Week 2 of 16 · 100 days left"

#### Scenario: A closed phase

- **WHEN** the phase's status is closed
- **THEN** the header reads "Finished"

### Requirement: Goals and rules appear only where the plan publishes them

The system SHALL show the plan's goals and rules on the screen of the
selected phase (the plan file's `plan`) and SHALL, for any other phase,
say that goals and rules are published for the current phase only instead
of showing empty sections.

#### Scenario: Another phase

- **WHEN** the owner opens a phase that is not the plan's selected phase
- **THEN** no goals or rules sections are shown and the screen says "Goals and rules are published for the current phase only."

### Requirement: The phase's weeks compare the run target with what the vault counted

The system SHALL list every outline week of the phase with its kind, note,
run target and the vault's counted distance, where the target is the
written week's own target, else the outline's, and the distance is the
written week's `actual`. A future week SHALL show no distance. A week that
has started but is not among the plan file's written weeks SHALL say that
its distance is not in the app's window, and SHALL NOT be shown as zero.
The phone SHALL NOT compute a week's distance itself.

#### Scenario: A written week with a different target from its outline

- **WHEN** week 42's outline target is 50 km, the written week's target is 55 km and the vault counted 60.1 km
- **THEN** the row shows 55 km against 60.1 km

#### Scenario: A started week outside the window

- **WHEN** week 45 has started but the plan file holds written weeks only up to week 44
- **THEN** week 45's row shows its target and "Not in the app's window", not 0 km

### Requirement: The phase screen lists its key sessions, tests and races

The system SHALL list the phase's long, tempo, threshold, interval,
VO2max, test and race sessions from the written weeks dated inside it,
each opening the session detail; every test result from the test history
dated inside the phase with its measures; and the races anchored to the
phase.

#### Scenario: A test result in the phase

- **WHEN** the calf-raise test recorded 22 reps left and 27 right on 16 October 2030 inside the phase
- **THEN** the phase lists that test on Wed 16 Oct with "Left 22 reps · Right 27 reps"

### Requirement: A closed phase ends with a recap

The system SHALL show, for a closed phase or any phase with a recap text,
the vault's recap and a summary: the distance run against the distance
planned over the weeks with a known distance, how many of those weeks
were within 10 % of their target, the biggest week, for each test measure
recorded at least twice inside the phase its first and last value judged
in the measure's better direction, and the phase's races.

#### Scenario: Recap of the transition phase

- **WHEN** the closed transition phase had one week planned at 30 km and the vault counted 22.6 km
- **THEN** the recap shows its text, "Ran 22.6 of 30 km planned", "0 of 1 weeks within 10 % of target" and "Biggest week: 22.6 km (W41)"

#### Scenario: A test measured twice

- **WHEN** a measure where higher is better went from 18 to 22 reps inside the phase
- **THEN** the recap shows "Left: 18 → 22 reps · Improved"
