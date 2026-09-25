## ADDED Requirements

### Requirement: A supplement streak counts consecutive stack-complete days

The system SHALL keep a supplement streak that increases on each
stack-complete day, ignores neutral days, and breaks on a day with planned
items that is not complete, unless a streak freeze covers it.

#### Scenario: Neutral day in between

- **WHEN** Monday and Wednesday are stack complete and Tuesday has nothing planned
- **THEN** the streak on Wednesday is 2

#### Scenario: Missed day

- **WHEN** Thursday has planned items that were not all taken and no freeze is available
- **THEN** the supplement streak is 0 on Friday morning

### Requirement: Streak freezes are shared between the food and supplement streaks

The system SHALL use one pool of streak freezes for both the food streak and
the supplement streak. A freeze SHALL protect only a streak of 3 or more
days, and SHALL be consumed by whichever protected streak breaks first.
Each missed day SHALL consume at most one freeze for each streak it would
break.

#### Scenario: Supplement streak protected

- **WHEN** the user holds 1 freeze, has a 10-day supplement streak and misses the stack on one day while the food streak continues
- **THEN** the missed day shows as frozen, the supplement streak continues, and the pool has 0 freezes

#### Scenario: Short streak not protected

- **WHEN** the supplement streak is 2 days and a day is missed while a freeze is held
- **THEN** the freeze is not consumed and the streak breaks

### Requirement: Supplement badges, challenges, collection and journey exist only while enabled

The system SHALL award supplement badges (for example 30 days of creatine,
60 vitamin D days between October and March, a full-stack week), include
supplement challenges in the rotation, and track a vitamin collection and a
creatine journey only while the feature is enabled and at least one product
exists. Badges already earned SHALL remain after the feature is disabled.

#### Scenario: Feature disabled

- **WHEN** the feature is disabled
- **THEN** no supplement challenge appears in the rotation and the earned "Stack week" badge is still shown in Achievements

#### Scenario: Sunshine badge

- **WHEN** vitamin D was taken on 60 distinct days between 1 October and 31 March
- **THEN** the "Sunshine" badge is unlocked once

### Requirement: Supplement XP does not change levelling pace

The system SHALL grant supplement XP through the XP budget's optional-source
multiplier, so that enabling supplements does not reduce the time to reach
level 84 for a typical active day by more than 1 %.

#### Scenario: Enabled vs disabled

- **WHEN** the simulated typical day is run with and without the supplement budget line
- **THEN** the days to level 84 differ by less than 1 %
