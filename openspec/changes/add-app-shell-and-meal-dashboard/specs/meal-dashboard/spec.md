## Purpose

Show a day the way Garmin Connect's food page does: meal by meal, each with its foods and with consumed versus suggested calories and macros, including entries not yet delivered to Garmin.

## ADDED Requirements

### Requirement: The day is shown as ordered meal sections

The system SHALL show one section per meal in the order Breakfast, Lunch, Dinner, Snacks, unless Garmin supplies a `displayOrder`, in which case that order SHALL be used. Every meal SHALL have a section even when nothing is logged in it. The data comes from `GET /nutrition-service/food/logs/{date}` (200, last verified 2026-09-16).

#### Scenario: A day with only breakfast logged

- **WHEN** the day's log contains foods only under BREAKFAST
- **THEN** four sections are shown, and Lunch, Dinner and Snacks each show zero consumed calories and an "add food" action

#### Scenario: Garmin supplies a display order

- **WHEN** the log's meals carry `displayOrder` values that place SNACKS before DINNER
- **THEN** the Snacks section is shown before the Dinner section

### Requirement: Each meal shows consumed versus Garmin's suggested targets

Each meal section SHALL show consumed calories, carbs, protein and fat against that meal's suggested targets from `mealNutritionGoals`. It SHALL prefer the adjusted target when Garmin supplies one, and SHALL show the consumed value alone when no target exists.

#### Scenario: Adjusted targets are present

- **WHEN** a meal's goals contain `calories` 500 and `adjustedCalories` 560
- **THEN** the meal's calorie target shows 560

#### Scenario: A meal with no goals

- **WHEN** a meal's goals are absent
- **THEN** the section shows consumed values with no target and no progress state

#### Scenario: A meal with nothing logged

- **WHEN** Garmin returns an empty content object for a meal
- **THEN** the section shows 0 consumed for calories and each macro, not a missing value

### Requirement: The day shows totals against the daily target

The system SHALL show the day's consumed calories and macros against `dailyNutritionGoals`. It SHALL use the same under / on-target / over rule (within ±10% of the target) for the day and for each meal.

#### Scenario: Day exactly on target

- **WHEN** the day's consumed calories are within 10% of the daily target
- **THEN** the day and any meal that is also within 10% of its own target show the on-target state

### Requirement: Entries not yet delivered appear in their meal

An entry queued for delivery but not yet present in Garmin's log SHALL appear in its meal section on its date, marked as syncing, with its name and calories when the food is known locally. An entry already present in Garmin's log SHALL be shown once.

#### Scenario: Logged while offline

- **WHEN** the user logs a food for lunch while offline
- **THEN** it appears in Today's Lunch section marked as syncing

#### Scenario: Delivered but not yet reconciled

- **WHEN** an entry has been delivered and also appears in Garmin's log
- **THEN** the Lunch section lists it once, as a confirmed entry

### Requirement: Adding from a meal pre-selects that meal and day

Starting to log from a meal section SHALL pre-select that meal and that section's date in the confirm screen. Both SHALL remain editable.

#### Scenario: Adding to yesterday's dinner

- **WHEN** the user views yesterday, taps add in Dinner, and picks a food
- **THEN** the confirm screen shows Dinner and yesterday's date

### Requirement: Without a meal pre-selected, the default comes from Garmin's meal windows

When logging starts without a meal pre-selected, the default meal SHALL be the meal whose window (from `GET /nutrition-service/meals/{date}`, 200, last verified 2026-09-16) contains the current time, and Snacks outside every window. If no windows are available, the existing time-of-day table SHALL be used.

#### Scenario: Inside the lunch window

- **WHEN** the lunch window is 10:00–12:00 and the user starts logging at 11:15
- **THEN** Lunch is pre-selected

#### Scenario: Between windows

- **WHEN** the user starts logging at 08:30 and no window contains 08:30
- **THEN** Snacks is pre-selected

### Requirement: Any day can be viewed

The system SHALL let the user move to earlier and later days and back to today, and SHALL show the selected date.

#### Scenario: Going back a day

- **WHEN** the user moves to the previous day
- **THEN** that day's meals and totals are shown, and a control returns to today

### Requirement: A meal can be opened for detail

Opening a meal SHALL show its foods and its full nutrient breakdown as returned by Garmin (including fiber, sugar, fats, sodium and the other fields present) and SHALL allow adding food to that meal.

#### Scenario: Opening dinner

- **WHEN** the user opens Dinner on a day with food in it
- **THEN** the detail lists each food with its quantity and calories, and the nutrients Garmin returned for Dinner

### Requirement: Entries can be deleted with confirmation

The user SHALL be able to delete an entry after confirming. A confirmed entry is deleted through `DELETE /nutrition-service/food/logs/{date}` (modelled on a live-tested client; not yet exercised by this project as of 2026-09-16) and a queued entry is removed from the local queue. A failed delete SHALL leave the entry visible and state why.

#### Scenario: Deleting a synced entry

- **WHEN** the user confirms deleting a synced entry and Garmin accepts
- **THEN** the entry disappears and the meal's totals update

#### Scenario: Deleting fails

- **WHEN** Garmin rejects the delete
- **THEN** the entry stays listed and an error explains what happened

#### Scenario: Deleting a queued entry

- **WHEN** the user deletes an entry that is still syncing
- **THEN** it is removed locally and is never sent to Garmin

### Requirement: The dashboard never blanks on a failed load

If the day cannot be loaded, the system SHALL keep showing the last loaded data for that day, marked as stale, together with the queued entries.

#### Scenario: Offline refresh

- **WHEN** the day was loaded once and a refresh fails
- **THEN** the previous data stays visible with a stale marker
