## ADDED Requirements

### Requirement: The weekly boss has a plan-adherence variant

In the training experience the system SHALL be able to choose a weekly boss
whose hits are kept plan days. It SHALL be chosen by the same rule as every
other boss (the weakest habit of the last four weeks, never last week's
boss), from at least 10 judged plan days. Outside the training experience it
SHALL never be chosen, and it SHALL NOT be required for the "every boss
defeated" badge.

#### Scenario: A week of kept days

- **WHEN** the plan boss is this week's boss with a target of 5 and five days of the week are kept
- **THEN** the boss is defeated and pays the usual defeat reward

#### Scenario: A rest day is a hit

- **WHEN** a rest day of the boss's week ends without an unplanned run
- **THEN** it counts as a hit

#### Scenario: Food-first

- **WHEN** the food-first experience picks its weekly boss
- **THEN** the plan boss is not a candidate

### Requirement: Bingo cards draw training squares in the training experience

In the training experience the system SHALL add squares about check-ins,
habits, kept plan days, strength sessions and session ratings to the pool a
weekly card is drawn from. No square SHALL ask for more training than
planned or for an amber or red morning. A card already running SHALL finish
as it is.

#### Scenario: A training square is ticked

- **WHEN** a card holds "check in on 5 days" and the fifth check-in of its week is recorded
- **THEN** the square is done on that day

#### Scenario: A Sunday rest day

- **WHEN** last week's card holds "keep the day's plan on 5 days" and its fifth kept day is the Sunday rest day, which is over on Monday
- **THEN** the square is done when the card is settled on Monday

#### Scenario: Food-first cards

- **WHEN** a card is generated in the food-first experience
- **THEN** it contains no training square

#### Scenario: A plan without written days

- **WHEN** a card is generated in the training experience and the plan has no written day
- **THEN** it contains no training square

### Requirement: The road-trip journey moves by kept days in the training experience

In the training experience the system SHALL advance the road-trip journey by
a fixed distance for every kept plan day, rest days included, instead of by
active calories, and SHALL say so in the journey's conversion line.

#### Scenario: A rest day moves the journey

- **WHEN** a rest day is kept
- **THEN** the road trip advances by the same distance as on a training day

#### Scenario: A plan without written days

- **WHEN** the plan has no written day
- **THEN** the road trip keeps advancing by active calories

#### Scenario: A very active day

- **WHEN** a day's active calories are three times the usual
- **THEN** the road trip advances by the same fixed distance, if the day is kept
