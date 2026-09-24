## ADDED Requirements

### Requirement: Standalone users have editable local nutrition goals with history

In standalone mode the system SHALL keep a local calorie target and optional
protein, carbs and fat targets as a history keyed by the day each goal starts
applying. The goal for a day SHALL be the latest one starting on or before
it, so editing a goal never changes past days. In Garmin mode targets SHALL
stay Garmin's and read-only.

#### Scenario: Editing a goal keeps history

- **WHEN** a standalone user changes her target from 1900 to 1800 kcal today
- **THEN** today and later days use 1800 kcal, and yesterday's ring and Trends still use 1900 kcal

#### Scenario: No goal set

- **WHEN** a standalone user skipped goal setup
- **THEN** the Today screen shows intake without a target, and no goal-met status is recorded for those days

### Requirement: A goal calculator suggests a safe starting target

The system SHALL offer a calculator that suggests calories and macros from
sex, birth year, height, current weight, activity level, goal (lose,
maintain, gain) and pace, using Mifflin-St Jeor times an activity factor
plus or minus the pace, and SHALL never suggest a target below 1200 kcal or
below the person's BMR, nor a pace above 0.75 kg a week or above 1 % of body
weight a week. Every suggested number SHALL be editable, the result SHALL be
saved as a new goal starting today, and the screen SHALL say these are
general estimates, not medical advice.

#### Scenario: Reference person

- **WHEN** the calculator gets female, 30 years, 165 cm, 60 kg, moderate activity (1.55), maintain
- **THEN** it suggests about 2046 kcal (BMR 1320 x 1.55) with protein at 1.4 g per kg (84 g)

#### Scenario: Floor applies

- **WHEN** a lose-weight pace would bring the target below the person's BMR
- **THEN** the target is raised to the floor and the screen says why
