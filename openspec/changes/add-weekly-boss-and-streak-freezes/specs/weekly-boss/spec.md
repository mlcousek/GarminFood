## ADDED Requirements

### Requirement: Each week's boss targets the owner's weakest recent habit

The system SHALL, once per ISO week, choose a boss from ten habit
archetypes by computing each archetype's adherence over the 28 days of the
four previous weeks and picking the eligible archetype with the lowest
adherence. An archetype SHALL be eligible only when its required data is
available and at least 14 of the 28 days qualify for consideration. The
boss SHALL NOT be the same archetype as the previous week's boss. With
fewer than 7 logged days in the window, the boss SHALL be the logging
consistency archetype. The choice SHALL be deterministic and persisted for
the week.

#### Scenario: Skipped breakfasts

- **WHEN** over the last 28 days breakfast was logged on 42 % of logged days and every other eligible habit's adherence is higher
- **THEN** this week's boss is "Snídaňový skřet" (Breakfast Goblin)

#### Scenario: Never twice in a row

- **WHEN** last week's boss was "Pouštní drak" and water is still the weakest habit
- **THEN** this week's boss is the eligible archetype with the next-lowest adherence

#### Scenario: Not enough water data

- **WHEN** water was recorded on only 10 of the last 28 days
- **THEN** "Pouštní drak" is not eligible this week

### Requirement: The boss target scales with the owner's adherence and each good day is a hit

The system SHALL set the boss target to the ceiling of adherence × 7 plus
2, limited to between 3 and 7 days, and SHALL count each day of the current
week on which the habit is met as one hit. Habits that an evening entry
could still break (late-night eating, sugary drinks) SHALL only count
completed days.

#### Scenario: Target from adherence

- **WHEN** the chosen habit's adherence was 42 %
- **THEN** the boss target is 5 days

#### Scenario: Late-night boss today

- **WHEN** the boss is "Půlnoční mlsoun" and it is 19:00 with no entry after 21:00 yet today
- **THEN** today is not yet counted as a hit

### Requirement: Defeating the boss is rewarded once; escaping has no penalty

The system SHALL, when hits reach the target within the week, award
150 XP plus 25 XP for each target day above 3, one streak-freeze grant, the
applicable boss badges and a celebration moment, each at most once per week.
If the week ends first, the boss SHALL be recorded as escaped with no XP
loss and no effect on the streak.

#### Scenario: Defeat

- **WHEN** a boss with target 5 receives its 5th hit on Friday
- **THEN** 200 XP and one streak freeze are granted once and "Boss Slayer" unlocks if not already unlocked

#### Scenario: Escape

- **WHEN** Sunday ends with 3 of 5 hits
- **THEN** the week is recorded as escaped and XP and streak are unchanged
