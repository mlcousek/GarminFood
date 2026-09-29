## ADDED Requirements

### Requirement: A race screen shows the race and its countdown

The system SHALL show for a season race its countdown from today (also
for a race in the past), its date (marked when approximate), priority and
hero status, category, distance and goal, the phase that anchors it (which
opens the phase's screen) or that no phase covers it, and whether the
vault has a race report. It SHALL open from the race's row on the Season
view, from a phase's races and from Today's race chip.

#### Scenario: The next race

- **WHEN** today is 23 October 2030 and the owner opens the B race on Sunday 3 November 2030 anchored to the base phase
- **THEN** the screen shows "in 11 days", "Sun 3 Nov 2030", "B race" and the base phase's title as a link

#### Scenario: Today's race chip

- **WHEN** the owner taps the race chip on Today
- **THEN** the Plan tab opens on the Season view with that race's screen on top

### Requirement: The race plan shows checkpoints with times, buffers and paces

The system SHALL show the race's start time and cutoff, and for each
checkpoint its distance, climb, aid, target and cutoff as durations and
clock times from the start, the buffer between them (flagged when the
target is after the cutoff), the heart-rate cap, and the pace of the
section from the last checkpoint that has a target, where the start is
kilometre 0 at minute 0. A checkpoint without a target SHALL get no pace
and SHALL NOT be used as the start of the next section; nothing SHALL be
interpolated. A race without preparation SHALL say that its prep is not
written yet.

#### Scenario: Checkpoint times

- **WHEN** the race starts at 09:00 and a checkpoint at 21 km has a target of 125 minutes and a cutoff of 210 minutes, the previous one being at 11.5 km with a target of 65 minutes
- **THEN** the checkpoint shows "Target 2 h 5 min · 11:05", "Cutoff 3 h 30 min · 12:30", "Buffer 1 h 25 min" and "6:19 /km"

#### Scenario: A checkpoint without a target

- **WHEN** the 21 km checkpoint has no target
- **THEN** it shows no pace, and the finish's pace is measured from the 11.5 km checkpoint

#### Scenario: No prep yet

- **WHEN** a race has no preparation in the plan
- **THEN** the screen shows "Race prep not written yet" and no checkpoint, fuel or carb-load sections

### Requirement: Race fuel and gear are shown with totals and priorities

The system SHALL show the race's carbohydrate per hour, how often to eat,
fluid per hour and, when the finish has a target, the totals to the
finish; and SHALL list the gear with mandatory items first, each marked
mandatory or optional without relying on colour alone.

#### Scenario: Fuel totals

- **WHEN** the race fuel is 70 g carbohydrate and 500 ml fluid per hour and the finish target is 178 minutes
- **THEN** the screen shows "About 208 g carbs to the finish" and "About 1.5 l fluid to the finish"

### Requirement: Carb-load days show grams and open that day's food log

The system SHALL list each carb-load day of the race's preparation with
its date, how many days before the race it is, its grams of carbohydrate
per kilogram and its grams: the plan's own figure for that day when the
plan file has it, otherwise the grams per kilogram times the athlete's
weight from the plan, labelled as an estimate with that weight, and no
gram figure when the plan has no weight. Each day SHALL offer to open the
food log of that date on Today, without logging or changing anything.

#### Scenario: Inside the plan's window

- **WHEN** the plan file's day two days before the race carries a carb load of 560 g at 8 g/kg
- **THEN** the row shows "2 days before", "560 g carbs · 8 g/kg" and "From your plan"

#### Scenario: Outside the plan's window

- **WHEN** the plan file has no fuel for the day before the race, the prep asks for 10 g/kg and the plan's weight is 72 kg
- **THEN** the row shows "720 g carbs · 10 g/kg" and "Estimated for 72 kg"

#### Scenario: Opening the food log

- **WHEN** the owner taps "Open food log" on the carb-load day of 1 November
- **THEN** the app shows Today on 1 November with that day's food log and nothing is logged

### Requirement: The taper and the race day are part of the plan

The system SHALL show the anchoring phase's outline weeks from the last
build week before the race week up to the race week, each with its kind,
run target and note, marking the race week and the current week, and the
plan's sessions that are this race, each opening the session detail.

#### Scenario: Taper into a race week

- **WHEN** the race is in week 44, the anchoring phase's weeks 42 and 43 are build weeks and week 44 is a race week
- **THEN** the taper lists week 43 and week 44, with week 44 marked as the race week
