## ADDED Requirements

### Requirement: A deterministic 3×3 bingo card is generated for each ISO week

The system SHALL generate one bingo card per ISO-8601 week (Monday to
Sunday, by logged date) the first time gamification runs in that week, and
SHALL persist it so that the card never changes for the rest of that week.
The card SHALL have a free centre square and eight tasks: three easy, three
medium and two hard, with no two tasks from the same family and no task
that was on the previous week's card unless too few tasks are eligible.
Generation SHALL be a deterministic function of the week and the eligible
task set.

#### Scenario: Reopening the app

- **WHEN** the card for 2026-W39 was generated on Monday and the app is reopened on Wednesday
- **THEN** the same nine squares are shown in the same positions

#### Scenario: Composition

- **WHEN** a new card is generated
- **THEN** it contains a free centre, 3 easy, 3 medium and 2 hard tasks, and no two tasks share a family

### Requirement: Only tasks the owner's data can satisfy are placed on a card

The system SHALL exclude a task from card generation when the data it
requires (water, macros such as fibre and sugar, or Garmin activities) is
not available on any of the last 14 days.

#### Scenario: No hydration data

- **WHEN** no water has been recorded locally or in Garmin during the last 14 days
- **THEN** the new card contains neither "Hydrated" nor "Water Works"

#### Scenario: No activities

- **WHEN** no Garmin activity is cached for the last 14 days
- **THEN** the new card contains neither "Refuel" nor "Earned It"

### Requirement: Squares complete automatically from the week's day signals and stay complete

The system SHALL mark a day-scoped square complete when its rule holds on
any day of the card's week, and a week-scoped square complete when its rule
holds across the week so far. A completed square SHALL remain complete for
that card even if a later edit or deletion would no longer satisfy it.
Squares SHALL NOT complete from days outside the card's week.

#### Scenario: Fish on Tuesday

- **WHEN** "Something Fishy" is on this week's card and the owner logs "Pstruh na másle" on Tuesday
- **THEN** that square shows as done on Tuesday

#### Scenario: Deleted entry

- **WHEN** the only fish entry that completed "Something Fishy" is later deleted
- **THEN** the square remains done and no XP is removed

#### Scenario: Last week's fish

- **WHEN** fish was logged only on the Sunday before this card's Monday
- **THEN** "Something Fishy" on this card is not done

### Requirement: Lines and a full card are rewarded once

The system SHALL award 25 XP for each row, column or diagonal that becomes
complete (the free centre counts as complete), and SHALL award 150 XP, one
streak-freeze grant and the full-card badges when all nine squares are
complete. Each reward SHALL be granted at most once per card, and each
completion SHALL produce a visible celebration moment.

#### Scenario: First line

- **WHEN** the two non-centre squares of the middle row are completed
- **THEN** 25 XP is awarded once and a "BINGO!" moment is shown

#### Scenario: Full card

- **WHEN** the ninth square is completed
- **THEN** 150 XP and one streak-freeze grant are recorded for that week, "Blackout" is unlocked if it was not already, and repeating the evaluation grants nothing more

### Requirement: The bingo card is visible on the Progress tab with its history

The system SHALL show the current card as a compact grid on the Progress tab
with the number of completed lines and days left, and SHALL provide a
detail screen showing each square's rule, completion day, and the cards of
the last 12 weeks. Each square SHALL have a VoiceOver label stating its
position, title and completion state.

#### Scenario: Square details

- **WHEN** the owner taps a completed square
- **THEN** its rule and the day it was completed are shown
