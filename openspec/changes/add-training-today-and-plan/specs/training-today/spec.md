## ADDED Requirements

### Requirement: Training cards lead Today in the training experience

In the training experience the system SHALL offer four Today cards, the
next race, the day's training, today's habits and the weekly note, placed
after the day switcher and before the food cards by default. For a user who
already customised Today, the system SHALL insert them after the day
switcher and SHALL keep every existing card's position, visibility and
variant. The training cards SHALL NOT exist in the food-first experience.

#### Scenario: First connection with a customised layout

- **WHEN** the owner, whose Today has weight & water moved above the meals, enables the vault connection
- **THEN** Today shows the day switcher, then the training cards, then his food cards in his own order

#### Scenario: Food-first install

- **WHEN** a food-first install opens Today or its layout editor
- **THEN** no training card is shown or listed

### Requirement: The day's sessions show their options read-only

The system SHALL show every session of the selected training day in the
file's order with its sport, title, status, a test or race badge for those
types, and the morning light when the projection carries one. For a session
with options it SHALL show three option cards, G, A and R, each with its
label and key targets (and its watch state once published), distinguished
by letter and shape as well as colour; a session without options SHALL show
its own title and targets. It SHALL highlight the done option, otherwise the
option matching the morning light, otherwise none, and SHALL show a done
session whose option is unknown as done with no option marked. It SHALL show
the day's carb-load target and a session's carbs per hour when present.
Tapping an option SHALL open the session detail at that option and SHALL NOT
record anything.

#### Scenario: A traffic-light run day, before the run

- **WHEN** today has an easy run with options G "Easy 12 km", A "Easy 8 km flat" and R "Bike 45 min Z1", and no light or done option
- **THEN** Today shows three option cards with those labels and their targets, none highlighted

#### Scenario: Red day recognised from the sport

- **WHEN** the projection marks the session done with option R, source `sport-inferred`
- **THEN** the R card is highlighted with a check and the session's status reads "Done"

#### Scenario: Done, option unknown

- **WHEN** the session is done with `done.option: null` because a run can't tell G from A
- **THEN** the session reads "Done" and no option card is marked

#### Scenario: Carb-load day

- **WHEN** the day's `fuel` is a carb load of 680 g at 8 g/kg before a race
- **THEN** the training card shows "Carb load: 680 g carbs (8 g/kg)"

#### Scenario: Colour-blind friendly

- **WHEN** "Differentiate Without Color" is on
- **THEN** each option card still shows its letter and its own shape

#### Scenario: Tapping is not a check-in

- **WHEN** the owner taps the A card
- **THEN** the session detail opens on option A and no event or file is written

### Requirement: Today's training card explains every non-happy state

The system SHALL show a designed state instead of sessions when the plan is
still being fetched, when the vault hasn't published a plan, when the
projection has no plan ("No active plan"), when the day has no session in a
week that exists ("Rest day"), and when the day's week is only outlined
("Week not written yet" with its target).

#### Scenario: Outlined week

- **WHEN** the selected date falls in a week that exists only in the outline with a 60 km target
- **THEN** the training card says the week isn't written yet and shows the 60 km target

### Requirement: Habits, the next race and the weekly note are shown without controls

The system SHALL list the habits the plan expects on the selected day with
their label, dose, schedule, 14-day adherence against the gate (or "not
recorded yet") and the day's done count when published, with no control to
tick them. It SHALL show a countdown chip to the next future race in the
season with priority A or marked as the hero race, prefixed "about" when its
date is approximate, opening the month calendar at the race date. It SHALL
show a teaser of the current week's AI note, or of the latest earlier week's
when the current one has none, opening the full text. Each card SHALL be
hidden when its data is absent.

#### Scenario: Race countdown

- **WHEN** the season lists a B race in 10 days and an A race in 23 days
- **THEN** Today shows a chip for the A race with "in 23 days", and tapping it opens Plan → Month with that day flagged

#### Scenario: No season

- **WHEN** the projection's `season` is null
- **THEN** no countdown chip is shown and nothing else changes

#### Scenario: Weekly note from last week

- **WHEN** the current week's `aiNote` is null and the previous week's is set
- **THEN** the weekly note card shows the previous week's note with that week's label

### Requirement: Food logging stays on Today

In the training experience the system SHALL keep Today's calorie summary,
"Log again" quick picks, meals, "Log a meal", weight and water and the
toolbar "Log a food" button, with the summary compact by default, and SHALL
log food through them exactly as in the food-first experience.

#### Scenario: Two-tap log below the training cards

- **WHEN** the owner scrolls past the training cards and taps a "Log again" item, then "Log it"
- **THEN** the food is committed locally in its meal and the calorie summary updates, with no network wait
