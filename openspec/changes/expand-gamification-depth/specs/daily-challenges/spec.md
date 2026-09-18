## Purpose

Offer a fresh, low-commitment pair of single-day goals every nutrition-day, separate from the longer-horizon rotating challenges, drawn from a large template pool so the same challenge rarely repeats.

## ADDED Requirements

### Requirement: Exactly two daily challenges are active per nutrition-day, drawn from a large template pool

The system SHALL select exactly two daily-challenge templates for each nutrition-day from a fixed pool of at least 100 templates, each with a completion condition evaluable purely from that day's local log entries and locally cached goal status.

#### Scenario: A new nutrition-day begins

- **WHEN** the app is opened on a nutrition-day that does not yet have daily challenges assigned
- **THEN** two templates are selected for that day from the pool

#### Scenario: Reopening later the same day

- **WHEN** the app is reopened later the same nutrition-day
- **THEN** the same two daily challenges already assigned for that day are shown, not a new pair

### Requirement: A daily-challenge template does not repeat within 30 days

The system SHALL NOT select a daily-challenge template that was already shown on any of the preceding 30 nutrition-days, unless fewer than two templates in the pool satisfy that constraint, in which case the least-recently-shown templates are used instead so a day is never left with fewer than two challenges.

#### Scenario: A template was shown 10 days ago

- **WHEN** selecting today's daily challenges
- **THEN** a template last shown within the past 30 days is excluded from selection

### Requirement: Completing a daily challenge is a rewarded, visible moment

The system SHALL award XP, distinct from the long-running-challenge completion bonus, the first time a given day's daily challenge is detected as complete, and SHALL present a visible completion moment.

#### Scenario: A daily challenge's condition is met

- **WHEN** a daily challenge's completion condition becomes true for the current nutrition-day
- **THEN** the user sees a completion moment and XP is awarded exactly once for that day's instance of that challenge
