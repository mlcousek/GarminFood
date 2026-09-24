## ADDED Requirements

### Requirement: Eight personal records are tracked with value, date and previous best

The system SHALL track the records: most protein in a day, most fruit and
vegetable entries in a day, most distinct foods in a day, most water in a
day, biggest active-kilocalorie day, longest consecutive water-goal streak,
longest fast (hours between consecutive entries, ignoring gaps longer than
48 hours), and lowest sugar on a completed day whose calories were within
10 % of the goal with at least 3 entries. Each record SHALL show its value,
the day it was set and the previous best. A record whose data source is
unavailable SHALL be hidden rather than shown as zero.

#### Scenario: Longest fast ignores unlogged days

- **WHEN** the owner logged nothing for 3 days between two entries
- **THEN** that 72-hour gap does not become the longest-fast record

#### Scenario: Off-target low-sugar day

- **WHEN** a completed day has 5 g sugar but calories 40 % under the goal
- **THEN** it is not considered for the lowest-sugar record

### Requirement: A new personal record is announced once and rewarded

The system SHALL announce a new record with a "New PR!" moment showing the
new and previous values and award 20 XP, at most once per record per day,
only when the value strictly beats the previous best. Records where higher
is better SHALL be evaluated during the day; the lowest-sugar and longest
fast records SHALL be evaluated only for completed days. A record SHALL NOT
be announced until it has at least 7 days of qualifying data, and the first
computation after installation SHALL set all records silently.

#### Scenario: Protein PR during the day

- **WHEN** the protein record is 171 g and today's total rises to 175 g and later to 186 g
- **THEN** one "New PR!" moment and 20 XP are given when it passes 171 g, and the record later shows 186 g without a second moment

#### Scenario: First run

- **WHEN** records are computed for the first time from 42 days of history
- **THEN** all record values are set and no moment or XP is given

#### Scenario: Warm-up

- **WHEN** only 4 days have water data and today's water beats them all
- **THEN** the record value updates but no moment is shown
