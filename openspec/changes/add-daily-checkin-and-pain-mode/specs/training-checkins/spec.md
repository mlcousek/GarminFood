## ADDED Requirements

### Requirement: The morning check-in is offered on every day

When the app may record check-ins, Today SHALL offer the morning check-in
row for the shown training day whatever the plan says about it: a day of a
written week, a day of a week that is not written (a day skeleton), a day
when there is no active plan, and a date the cached file does not cover.
The chosen light SHALL be the phone's latest check-in for that date, else
the file's check-in light for the day. Under an empty state ("no active
plan", "sessions aren't written yet") the card SHALL still show the day's
morning light.

#### Scenario: An unwritten week

- **WHEN** today is in a week whose sessions are not written and the owner taps Amber
- **THEN** an amber check-in is recorded for today, the row shows Amber as chosen with "Saved on phone", and the card shows "Morning check: Amber" under "Sessions for this week aren't written yet"

#### Scenario: No active plan

- **WHEN** the projection has no plan and check-ins are allowed
- **THEN** Today shows the "no active plan" state with the three check-in buttons, and a recorded light shows as chosen

#### Scenario: A lock-screen Control on a day outside the plan

- **WHEN** a Control records a light on a day no written week holds
- **THEN** the light is shown on Today, in the Plan month cell and in the day sheet for that date

#### Scenario: Recording is not allowed

- **WHEN** the vault connection has no device id
- **THEN** no check-in row is shown on any day

### Requirement: Habits are tickable on every day the file covers

The Habits card, its ticks and the reward facts SHALL use the day found by
the one date lookup, so a day skeleton's expected habits are listed,
tickable and counted like a written week's, also when there is no plan.

#### Scenario: A Monday of an unwritten week

- **WHEN** the skeleton of Monday 4 Nov expects the daily holds and the gym habit
- **THEN** the Habits card lists both as scheduled today and tickable, and ticking the gym habit shows one of two done

#### Scenario: Reward facts without a plan

- **WHEN** there is no plan and the owner checked in today
- **THEN** the day's reward fact says "checked in", and no week fact exists

### Requirement: The Plan tab shows what is known about unwritten days

The month calendar's day cells and the day sheet SHALL show a day
skeleton's morning light and unplanned activities. A week agenda whose
sessions are not written SHALL list, under its message, each of its days
that has a check-in light, an unplanned activity or (in pain mode) recorded
pain, and SHALL NOT call such a day a rest day.

#### Scenario: A check-in in an unwritten week

- **WHEN** the owner checked in amber on Tuesday of an unwritten week
- **THEN** that week's agenda shows its "not written yet" message and one row for Tuesday with "Morning check: Amber", and the month cell for that day shows the amber light

### Requirement: Pain features show only in pain mode

Pain mode SHALL be on when the projection's `athlete.painMode.active` is
true, or when this phone holds a morning pain answer with a score above 0
that the vault has not read yet (its event is not acknowledged and the
file's own pain for that date is not that answer). Nothing SHALL be stored
for it. In pain mode the pain step, the card's pain line and the Plan pain
tags SHALL behave as before. Outside pain mode the check-in SHALL be the
light only: no pain step opens by itself, no pain line and no pain tags are
shown (a recorded answer of an earlier episode included), and the row SHALL
offer one small "Something hurts?" link once a light is chosen, which opens
the same pain step. An amber or red light alone SHALL NOT turn the phone's
half of pain mode on.

#### Scenario: Healthy morning

- **WHEN** pain mode is off and the owner taps Green
- **THEN** the check-in is recorded, no pain step opens, the card shows no pain line and the row shows the "Something hurts?" link

#### Scenario: Something hurts

- **WHEN** pain mode is off, the owner taps "Something hurts?", sets the left knee to 2 and saves
- **THEN** a check-in with `pains: [{site: knee-left, score: 2}]` is recorded, and at once the card shows "Pain: Knee (left) 2/10", the Plan day row shows the tag and the step behaves as in pain mode

#### Scenario: Zero is not pain

- **WHEN** pain mode is off and the owner opens the link and saves every site at 0
- **THEN** the answer is recorded and pain mode stays off

#### Scenario: The vault has read the answer

- **WHEN** the vault acknowledged the phone's pain answer and its `painMode` is inactive
- **THEN** pain mode is off on the phone

#### Scenario: The vault's pain mode

- **WHEN** the projection says `painMode.active: true` and today's light is chosen but the pain is not recorded
- **THEN** the pain step is open under the lights with the default sites at 0

### Requirement: A Control check-in brings Today forward only in pain mode

After a lock-screen Control's check-in succeeds, the app SHALL show Today
at the current training day only when pain mode is on (where the pain step
is waiting); outside pain mode the light is the whole check-in and the app
SHALL stay where it was.

#### Scenario: Amber from the lock screen while healthy

- **WHEN** pain mode is off and the owner taps the Amber Control
- **THEN** an amber check-in is recorded and the app does not switch to Today

#### Scenario: Amber from the lock screen in pain mode

- **WHEN** pain mode is on and the owner taps the Amber Control
- **THEN** an amber check-in is recorded and Today shows today's check-in row with the pain step open

### Requirement: Fuel targets and paused fasting work on every day

The day's fuel targets for the food side and the days on which the plan
pauses fasting SHALL be read from the day found by the one date lookup, so
a day skeleton and a day without any plan give the same targets and the
same "fasting paused" as a written week's day. A day SHALL be treated as a
carb-load day only by its fuel's kind.

#### Scenario: A rest day of an unwritten week

- **WHEN** a skeleton's fuel is a daily band of 3 to 5 g/kg with fasting allowed and the athlete weighs 70 kg
- **THEN** the day's carb target is 210 to 350 g, it is not a carb-load day and fasting is not paused

#### Scenario: A build-week day

- **WHEN** a day's fuel says `fasting: "off"`
- **THEN** the day counts as a paused fasting day whether a written week or a skeleton holds it
