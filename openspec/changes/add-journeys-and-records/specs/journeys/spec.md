## ADDED Requirements

### Requirement: Cumulative totals advance along real-world journeys

The system SHALL maintain four journeys from cumulative daily values: a
protein climb where 1 g of protein equals 1 vertical metre, a water journey
in litres, a road trip from Praha where kilometres equal active kilocalories
divided by the latest known body weight in kilograms (70 kg when unknown),
and a food passport with one stamp per distinct food ever logged. Each
journey SHALL show the current position, the last milestone reached and the
next milestone with the distance remaining, and SHALL state its conversion
on screen. Days without the required data SHALL contribute nothing.

#### Scenario: Protein reaches Sněžka

- **WHEN** the cumulative protein in the current climb stage goes from 1,580 g to 1,640 g
- **THEN** the Sněžka (1,603 m) milestone is reached and the next milestone shown is Gerlachovský štít at 2,655 m

#### Scenario: Road trip distance

- **WHEN** a day has 700 active kilocalories and the latest weigh-in is 70 kg
- **THEN** that day adds 10 km to the road trip

#### Scenario: Endless pool

- **WHEN** the water total passes the last finite milestone
- **THEN** the journey shows the percentage of the Podolí 50 m pool filled

### Requirement: Each day counts exactly once toward lifetime journey totals

The system SHALL fold each day's value into a journey's lifetime total
exactly once, SHALL keep recomputing the most recent three days while they
can still change, and SHALL keep totals independently of the capped usage
history.

#### Scenario: Repeated refreshes

- **WHEN** gamification refreshes ten times on the same day
- **THEN** each past day's protein has been added to the climb total exactly once

#### Scenario: Late log for yesterday

- **WHEN** the owner logs a 30 g protein entry for yesterday
- **THEN** yesterday's contribution to the climb increases by 30 m

### Requirement: Journey milestones are rewarded once

The system SHALL award 40 XP once per journey milestone reached, unlock the
journey's badges at their designated milestones, and show at most one
journey moment per evaluation, combining several milestones reached at
once.

#### Scenario: Two milestones on one day

- **WHEN** a single day's water carries the total past both 10 L and 50 L
- **THEN** 80 XP is awarded and one moment names both milestones
