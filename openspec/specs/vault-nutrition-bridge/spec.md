# vault-nutrition-bridge Specification

## Purpose
Keep the Obsidian vault's existing nutrition sync correctly wired to Garmin's real food-log route, so that the vault's daily notes and Nutrition dashboard reflect actual logged food rather than silently showing nothing because of a stale, dead endpoint.

## Requirements

### Requirement: The vault reads nutrition data from a route confirmed to exist

The vault's nutrition sync SHALL call the food-log route recorded as working in the project's route registry, rather than a route known to return 404.

#### Scenario: Fetching a day's nutrition data

- **WHEN** the sync fetches nutrition data for a given date
- **THEN** it calls the currently registered, confirmed-working route
- **AND** it does not call `/nutrition-service/food/log/date/{date}`, which is confirmed dead as of 2026-09-14

### Requirement: A missing route is reported distinctly from a day with no logged food

The sync SHALL distinguish "the route does not exist" (HTTP 404 on a route expected to exist) from "no food was logged on this date" (a successful response with an empty result), and MUST report the former visibly rather than silently treating it as the latter.

#### Scenario: The registered route stops working

- **WHEN** the nutrition route returns HTTP 404 unexpectedly
- **THEN** the sync logs a visible warning naming the route
- **AND** it does not silently record "no data" for every date in the sync window

#### Scenario: A date genuinely has no logged food

- **WHEN** the nutrition route returns a successful, empty result for a date
- **THEN** the sync records no nutrition data for that date without logging a warning

### Requirement: Daily note frontmatter reflects real synced data

Once the corrected route is in place, the sync SHALL populate daily-note frontmatter fields (calories, protein, carbs, fat, fiber, water where present) from actual Garmin data for any date on which food was logged.

#### Scenario: Food was logged on a synced date

- **WHEN** the owner has logged food on a given date in Garmin Connect
- **THEN** running the sync populates that date's daily note with the corresponding nutrition frontmatter fields
