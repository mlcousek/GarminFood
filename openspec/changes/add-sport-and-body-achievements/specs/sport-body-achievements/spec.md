## ADDED Requirements

### Requirement: Fuelling and recovery around Garmin activities earn badges

The system SHALL link food entries to cached Garmin activities (read-only,
`GET /activitylist-service/activities/search/activities`, confirmed
2026-09-24) lasting at least 20 minutes. An endurance activity SHALL count
as fuelled when an entry with at least 30 g of carbohydrate — or, when its
carbohydrate is unknown, a food tagged carb-rich — was logged between 30
and 180 minutes before the activity started. An activity SHALL count as
recovered when entries logged within 60 minutes after it ended total at
least 20 g of protein. Each activity SHALL count at most once for each
badge family, and badges SHALL unlock at 1, 10 and 50 counted activities.
Mobility, yoga and similar activities, and walks shorter than 45 minutes,
SHALL NOT count.

#### Scenario: Fuelled run

- **WHEN** the owner logs porridge with 45 g carbs at 06:00 and a 60-minute run starts at 07:30
- **THEN** the run counts as fuelled and "Fuelled Up" unlocks if not already unlocked

#### Scenario: Too early

- **WHEN** the carb entry was logged 181 minutes before the run started
- **THEN** the run does not count as fuelled

#### Scenario: Recovery across two entries

- **WHEN** a run ends at 08:30 and the owner logs 12 g protein at 08:45 and 10 g at 09:15
- **THEN** the run counts as recovered

#### Scenario: Mobility session

- **WHEN** a 30-minute "mobility" activity is followed by 30 g protein
- **THEN** it does not count toward Recovery Window

### Requirement: Intake matched to an active day earns "Earned It"

The system SHALL count a completed day toward the Earned It badges (5, 25
and 100 days) when its active kilocalories are at least 400, it has at least
3 entries and a calorie goal, and its intake is at least 80 % of the goal
and at most the goal plus 50 % of that day's active kilocalories.

#### Scenario: Big training day

- **WHEN** a completed day has a 2,200 kcal goal, 1,000 active kcal and 2,600 kcal eaten
- **THEN** the day counts toward Earned It

#### Scenario: Under-eating is not rewarded

- **WHEN** a completed day has a 2,200 kcal goal, 1,000 active kcal and 1,500 kcal eaten
- **THEN** the day does not count

### Requirement: Race days and long efforts are recognised

The system SHALL unlock race-day badges for days tagged "race" in the day
note that have at least one entry (at 1 and 5 such days), a carb-loading
badge when the two days before a race day both meet the carbohydrate goal,
and in-activity fuelling badges for at least 3 entries during a single
endurance activity of at least 90 minutes and for at least one entry during
an endurance activity of at least 3 hours.

#### Scenario: Trail race

- **WHEN** a day is tagged "race" and has a 4-hour trail run with 3 entries logged during it
- **THEN** "Race Day Fuel", "Gel Guru" and "Long Haul" unlock

### Requirement: Weight-goal milestones and fasting streaks earn badges

The system SHALL unlock weight milestones against the effective weight goal
(local override, else Garmin's starting and target weight): a weigh-in at
least 1 kg from the start weight in the goal's direction, a weigh-in at
least halfway from start to target, a weigh-in at or beyond the target
within 0.2 kg, and 30 consecutive days in which every weigh-in is within
1 kg of the target with at least 8 weigh-ins. The system SHALL unlock
fasting badges when the kept-fast streak reaches 3, 7, 14 and 30 days.
These badges SHALL be permanent even if the goal later changes.

#### Scenario: First kilo on a loss goal

- **WHEN** the start weight is 82.0 kg, the target 76.0 kg, and a weigh-in of 80.9 kg is recorded
- **THEN** "First Kilo" unlocks

#### Scenario: Steady needs enough weigh-ins

- **WHEN** 30 consecutive days have 7 weigh-ins, all within 1 kg of target
- **THEN** "Steady as Sněžka" does not unlock

#### Scenario: Activities unavailable

- **WHEN** the activities route fails for a week
- **THEN** activity badges do not progress, weight and fasting badges still unlock, and nothing is shown as failed
