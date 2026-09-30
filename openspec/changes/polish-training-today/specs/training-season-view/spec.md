## ADDED Requirements

### Requirement: Every race priority and the time before the first phase are shown

The Season timeline SHALL draw and list races of every priority (A, B, C)
with their priority, and SHALL draw the time between the season's start
and its first phase as a labelled "No phase planned" gap. A race no phase
covers SHALL be drawn and listed with "No phase covers this race yet", and
its race screen SHALL open with that line and without a taper.

#### Scenario: B races before the first phase

- **WHEN** the season starts two weeks before its first phase and two B races without a phase fall in that time
- **THEN** the timeline shows the gap "No phase planned" from the season's start, both B races on separate lanes with "B race" and "No phase covers this race yet", and each opens its race screen
