## ADDED Requirements

### Requirement: Weight shows a 7-day morning average in the training experience

In the training experience the weight card and the Weight screen SHALL show
the average of the last 7 days' morning weigh-ins (logged before 07:00
local), with its change against the 7 days before in % a week. When the
window has no morning weigh-in, the system SHALL average every weigh-in in
it and label it "7-day average".

#### Scenario: Morning and midday weigh-ins

- **WHEN** the last 7 days hold weigh-ins of 83.0 kg and 83.4 kg at 06:30–06:45 and 85.1 kg at 13:00
- **THEN** the card shows a 7-day morning average of 83.2 kg

### Requirement: No weight target in the training experience

In the training experience the system SHALL NOT show:

- the weight goal bar or the estimated arrival date;
- the goal line on the weight chart;
- the weight-goal milestones on Sport & Body.

Food-first SHALL show them as before.

#### Scenario: A goal is set in Settings

- **WHEN** a target weight is set and the training experience is on
- **THEN** the weight card shows the morning average and no target or ETA

### Requirement: One quiet flag for losing weight too fast

The system SHALL show one quiet, non-warning line only when the 7-day
average fell by more than 0.7 % against the previous 7 days. A gain, a
stable weight or a slower fall SHALL show no judgement.

#### Scenario: Falling 0.84 % a week

- **WHEN** the average fell from 83.0 kg to 82.3 kg in a week
- **THEN** the card shows the quiet "falling faster than the plan allows" line

#### Scenario: Falling 0.6 % a week

- **WHEN** the average fell from 83.0 kg to 82.5 kg
- **THEN** no line is shown
