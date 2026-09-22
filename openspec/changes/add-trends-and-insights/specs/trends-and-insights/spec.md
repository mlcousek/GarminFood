## Purpose

Give the user a way to see how their nutrition and hydration have tracked
over time, not just on a single day -- read-only, computed from data the
app already fetches or already stores locally.

## ADDED Requirements

### Requirement: The Trends screen shows a macro trend against goal

The system SHALL fetch the last ~30 nutrition days' calories, protein,
carbs and fat (actual and goal) in one Garmin read and show each as an
actual-vs-goal line chart. A day with nothing logged SHALL be treated as
absent data for that day, never rendered as a logged zero.

#### Scenario: A month with a few unlogged days

- **WHEN** the fetched range includes days with no `nutritionContent` in
  the response
- **THEN** those days are skipped in each macro's actual line rather than
  plotted as 0, and the chart's accessible summary reflects only the days
  that were actually logged

#### Scenario: A fetch failure with no prior data

- **WHEN** the Garmin read fails and no data has loaded yet this session
- **THEN** the screen shows an error state, not an empty or crashed chart,
  and pull-to-refresh can retry it

### Requirement: The Trends screen shows a hydration streak and trend

The system SHALL compute, purely locally from stored hydration entries, the
number of consecutive days (counting back from today) whose total met the
user's local daily hydration goal, and SHALL show a bar chart of recent
daily totals against that goal.

#### Scenario: An unbroken run of days meeting the goal

- **WHEN** today and each of the preceding several days' totals each meet
  or exceed the goal
- **THEN** the streak count equals that unbroken run's length

#### Scenario: A shortfall day breaks the streak

- **WHEN** yesterday's total fell short of the goal but today's has met it
- **THEN** the streak counts only today, not any day before the shortfall

### Requirement: The macro trend fetch is scoped to the Trends screen

The system SHALL fetch macro trend data only while the Trends screen is
open (on appearance and pull-to-refresh), not as part of the app's routine
foreground refresh, since a multi-week history has no use elsewhere in the
app.

#### Scenario: Opening the Progress tab does not fetch the macro trend

- **WHEN** the user opens the Progress tab without navigating into Trends
- **THEN** no `calorieSummaryDaily` request is made
