## ADDED Requirements

### Requirement: Rewards that push against the plan are quiet in the training experience

In the training experience the system SHALL NOT:

- announce, reward or count personal records for "Biggest active day" or
  "Longest fast" (their values are still kept);
- unlock the fasting-streak badges or the weight-goal milestone badges;
- offer challenges, daily challenges, bingo squares or a weekly boss that
  judge the fixed calorie target.

An already earned badge SHALL stay visible. A challenge or card already
running SHALL finish normally. Food-first SHALL be unchanged.

#### Scenario: A new biggest active day while training

- **WHEN** the training experience is on and today's active kcal beats the record
- **THEN** the record's value is updated silently, with no moment and no XP

#### Scenario: Daily challenges on a training day

- **WHEN** today's daily challenges are picked in the training experience
- **THEN** neither is "hit your calorie goal" nor "hit all four goals"

### Requirement: Training badges reward the plan's own habits

In the training experience the system SHALL unlock badges from the plan's
facts, each once:

| Ladder | Tiers |
|---|---|
| Morning check-ins (days) | 7 / 30 / 100 |
| An amber or red morning followed by its option | 1 / 10 |
| Weeks with at least two strength sessions done | 1 / 4 / 12 |
| Habit ticks | 25 / 100 / 300 |
| Weeks the projection closed within plan: no missed session, at least one done, run volume at most 10 % over target | 1 / 4 / 12 |

Counts SHALL accumulate beyond the weeks the projection carries. Outside the
training experience these badges SHALL be hidden unless earned.

#### Scenario: Honest amber morning

- **WHEN** the morning check-in is amber and that day's session is done with its A option
- **THEN** it counts toward the "Listened to the Body" badge

#### Scenario: Red morning, full session anyway

- **WHEN** the check-in is red and the session is done with its G option
- **THEN** it does not count as an honest call

### Requirement: Training rewards keep the levelling pace

The system SHALL pay each training badge the generic badge bonus. The
training rewards SHALL be an optional XP source, scaled like other optional
sources so that the training experience never makes levelling faster.
Nothing SHALL be paid twice for the same badge.

#### Scenario: A badge already unlocked

- **WHEN** "Morning Report" is already unlocked and another check-in is recorded
- **THEN** no second unlock or XP is granted
