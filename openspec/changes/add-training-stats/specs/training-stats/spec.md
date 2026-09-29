## ADDED Requirements

### Requirement: Statistics cover a phase or the whole season

The system SHALL offer, in the training experience, a statistics screen
opened from the Plan tab (for the current phase) and from a phase's
screen (for that phase), with a choice between that phase and the whole
season. Without a plan it SHALL show that there is no active plan, and it
SHALL still show the test histories.

#### Scenario: From the Plan tab

- **WHEN** the owner opens Statistics from the Plan tab while the plan's current phase is the base phase
- **THEN** the screen covers the base phase, from 14 October 2030 to 31 January 2031, and offers the whole season instead

#### Scenario: No plan

- **WHEN** the plan file has no current phase
- **THEN** the screen shows "No active plan" and the tests' histories

### Requirement: Adherence counts the plan's sessions as the vault decided them

The system SHALL show, per week and per phase of the scope, how many
sessions were done, missed, skipped and are still planned, as the plan
file states their status, and the share of the sessions due so far (done,
missed or skipped) that were done. The per-week done and missed counts
SHALL equal the vault's own counts for that week. Weeks of the scope that
have started but are not in the plan file SHALL be listed as not in the
app's window and SHALL NOT be counted as zero.

#### Scenario: A phase in progress

- **WHEN** the base phase has 8 sessions done in week 42, 1 done, 1 missed and 4 planned in week 43, and 4 planned in week 44
- **THEN** the screen shows those counts per week and "Done 90 % of the sessions due so far"

#### Scenario: Weeks the phone can't see

- **WHEN** the scope is the whole season, which started in week 36, and the plan file holds weeks 41 to 44
- **THEN** the screen lists "Not in the app's window: W36, W37, W38, W39, W40" and counts nothing for them

#### Scenario: Czech

- **WHEN** the app's language is Czech
- **THEN** the season summary reads "Hotovo 92 % tréninků, které už byly na řadě"

### Requirement: The option split shows which option the done days were

The system SHALL show, for the done sessions with G/A/R options in the
scope, how many were done as G, A and R and how many had no identified
option, each with its share, without relying on colour alone, and SHALL
say when no such session has been done.

#### Scenario: One easier, one alternative, one unknown

- **WHEN** the scope's done traffic-light sessions are one A, one R and one run whose option the vault could not identify
- **THEN** the split shows G 0, A 1, R 1 and "Option not identified" 1, the A row reading "1 session · 33 %"

#### Scenario: None yet

- **WHEN** no traffic-light session in the scope is done
- **THEN** the split says "No traffic-light session done yet"

### Requirement: Volume is compared with the target week by week

The system SHALL show, for every outline week of the scope's phases, the
week's run target and the vault's counted distance with their difference
in kilometres and percent, the same figures as the phase's screen, and a
summary of the planned total, the distance run against the distance
planned over the weeks with a known distance, the weeks within 10 % of
their target and the weekly mean. A started week not in the plan file
SHALL say so rather than show zero.

#### Scenario: Over and under target

- **WHEN** week 42 targeted 55 km and the vault counted 60.1 km, and week 43 targeted 60 km with 10.1 km counted so far
- **THEN** the rows read "60.1 of 55 km" with "+5.1 km (+9 %)" and "10.1 of 60 km" with "−49.9 km (−83 %)"

### Requirement: Test histories show progress and the left/right asymmetry

The system SHALL show for every test its results over time per measure,
the latest value, the first and last value judged in the measure's better
direction, and for measures that pair a left and a right side, the
asymmetry |left − right| / max(left, right) on every date with both
sides and the latest one. A test never done SHALL say that it has no
results yet.

#### Scenario: Calf raises

- **WHEN** the single-leg calf-raise test recorded 18 left and 24 right, then 22 left and 27 right
- **THEN** each side shows "Improved", the history reads "L 18 · R 24 · 25 %" and "L 22 · R 27 · 19 %", and the latest is "Asymmetry 19 %"

#### Scenario: A test not done yet

- **WHEN** the 3 km time trial has no results
- **THEN** its card says "No results yet"
