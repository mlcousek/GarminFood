## ADDED Requirements

### Requirement: The habit ladder is tracked from Today

In the training experience, Today SHALL show a Habits card whenever the
plan has a habit ladder, placed right after the training card (whose first
row is the morning check-in) and visible by default in every layout,
including a layout the owner stored before this card existed. The card
SHALL show the highest active step as "Step n of N"; the active habits and
any habit the shown day expects, in ladder order, each with its 14-day
adherence against the gate; an on/off tick, recorded through the check-in
recorder, for each habit the day expects when recording is allowed; "Not on
today's plan" and no tick for an active habit the day does not expect; how
many of the day's expected habits are done; and the next step with what
unlocks it ("Gate met" when the vault says so, else the current habit and
the gate's percentage and window) and its earliest start. Tapping the
header or the next step SHALL open the full habit ladder. The card SHALL be
hidden only when the ladder is empty.

#### Scenario: A day with one expected habit

- **WHEN** two habits are active, the day expects one of them and the vault counted it done
- **THEN** the card shows "Step 2 of 6", both habits, a tick only on the expected one, "Not on today's plan" on the other, "1 of 1 done today" and "Next step: ..." with "Unlocks when ... holds 80 % over a 14-day window"

#### Scenario: A day that expects no habit

- **WHEN** the shown day expects no habit and the ladder has active habits
- **THEN** the card still shows the active habits and the next step, without ticks or a day count

#### Scenario: Stored layout from before

- **WHEN** the owner's stored Today layout has the old habits card hidden
- **THEN** the Habits card is shown right after the training card

### Requirement: The race chip shows the next race of any priority

Today's race chip SHALL show the next race on or after the shown day of
any priority, with its priority letter as text (and a star for the hero
race), its countdown and, when the season's main race -- the next hero
race, else the next A race -- is a different, later race, a second line
"Main race: <name> · <countdown>". Tapping it SHALL open the race.

#### Scenario: B race before the hero race

- **WHEN** a B race is in 11 days and the hero race in about 241 days
- **THEN** the chip shows the B race, "B", "in 11 days" and "Main race: <hero> · in about 241 days"

#### Scenario: The hero race is next

- **WHEN** the next race is the hero race
- **THEN** the chip shows it with no second line
