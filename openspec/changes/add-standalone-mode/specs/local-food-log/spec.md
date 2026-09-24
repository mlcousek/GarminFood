## ADDED Requirements

### Requirement: Standalone food entries are committed to a local system of record

In standalone mode the system SHALL commit every confirmed food entry to a
local food log store, with its day, meal, time, food reference, serving,
quantity and a nutrient snapshot for the logged amount, before the confirm
action completes, with no network wait and no outbox, sync or "syncing"
state. Entries SHALL be kept indefinitely and SHALL NOT change when the
source food is later edited.

#### Scenario: Logging offline

- **WHEN** a standalone user in airplane mode logs 150 g of a 100 g-serving food with 120 kcal per serving
- **THEN** the entry appears immediately in its meal with 180 kcal, and it is still there after the app is relaunched

#### Scenario: Snapshot survives a food edit

- **WHEN** a custom food logged yesterday at 200 kcal is edited to 250 kcal today
- **THEN** yesterday's entry and day total still show 200 kcal

### Requirement: The Today dashboard, meal detail and trends read the local log in standalone mode

In standalone mode the system SHALL build the Today dashboard, meal detail,
calorie ring, macro bars, copy-meal source days and Trends charts from the
local food log and local goals, through the same read interface that Garmin
mode uses, so totals, goals and bands are computed by the same code in both
modes.

#### Scenario: Day totals

- **WHEN** a standalone day has breakfast entries of 300 and 200 kcal and a lunch entry of 600 kcal, with a local goal of 2000 kcal
- **THEN** the Today ring shows 1100 of 2000 kcal and breakfast shows 500 kcal

#### Scenario: Trends

- **WHEN** a standalone user opens Trends after logging on 5 of the last 7 days
- **THEN** the calorie chart shows those 5 days from the local log with each day's goal line

### Requirement: Editing, moving, duplicating, copying and deleting work on local entries

In standalone mode the system SHALL change an entry's amount in place
(rescaling its nutrients by the quantity ratio), move it to another meal,
duplicate it, copy a past meal into the current day and delete an entry,
all as local commits, and SHALL update usage history, remembered servings
and quick picks the same way Garmin mode does.

#### Scenario: Editing an amount

- **WHEN** a standalone entry of 1 serving at 200 kcal is edited to 1.5 servings
- **THEN** the entry shows 300 kcal and the day total rises by 100 kcal

#### Scenario: Deleting

- **WHEN** a standalone user deletes an entry
- **THEN** it disappears from its meal and day totals immediately, and no Garmin request is made
