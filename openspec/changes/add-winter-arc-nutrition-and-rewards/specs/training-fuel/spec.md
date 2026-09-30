## ADDED Requirements

### Requirement: The plan day's fuel is decoded tolerantly

The system SHALL decode a projection day's `fuel` object additively in
contract v1. `carbsGPerKg` SHALL be read as a single number (a carb-load
day) or as a `{ min, max }` band, never both. `proteinGPerKg` and
`fasting` (`allowed` or `off`) SHALL also be read. A malformed field SHALL
read as absent without dropping the day, and an unknown `fasting` value
SHALL never pause fasting.

#### Scenario: Band shape

- **WHEN** a day carries `fuel: { carbsGPerKg: { min: 6, max: 8 }, proteinGPerKg: 1.7, fasting: "off" }`
- **THEN** the day has a 6–8 g/kg carb band, 1.7 g/kg protein and fasting off

#### Scenario: Carb-load shape still works

- **WHEN** a day carries `fuel: { kind: "carb-load", carbsGPerKg: 10, carbsG: 800 }`
- **THEN** the day is a carb-load day of 800 g and has no band

#### Scenario: Broken band

- **WHEN** `carbsGPerKg` is `{ min: "a lot" }`
- **THEN** the day has no band and the rest of its fuel still decodes

### Requirement: Fuel targets are grams for the athlete's weight

The system SHALL turn a day's band into grams by multiplying it by
`athlete.weightKg`, or by the latest weigh-in when the plan has no weight.
Protein SHALL be `proteinGPerKg` × weight, or 1.6 g/kg × weight when not
given, and only on a day with a carb band. Without any weight the day SHALL
have no gram targets.

#### Scenario: 80 kg on a 6–8 g/kg day

- **WHEN** the athlete weighs 80 kg and the band is 6–8 g/kg with 1.8 g/kg protein
- **THEN** the day's carb range is 480–640 g and its protein target is 144 g

### Requirement: The Today summary leads with carbs in the training experience

In the training experience, on a day whose plan has a carb band, the system
SHALL show the day summary with carbs first:

- carbs eaten against the range, with "Below range", "In range" or "Above
  range";
- protein against its target;
- calories only as a secondary line.

No part of it SHALL use a warning colour. Food-first SHALL show the calorie
summary unchanged.

#### Scenario: Carbs inside the band

- **WHEN** the range is 480–640 g and 520 g of carbs are logged
- **THEN** the summary says "In range" and shows the calories as a secondary line

#### Scenario: Food-first is unchanged

- **WHEN** the training experience is off
- **THEN** the day summary is the calorie ring it always was

### Requirement: Over is never a warning on a training day

In the training experience, on a day with training sessions or a carb
band, the system SHALL NOT show the calorie ring or bar in the "slightly
over" or "over" colours. It SHALL use the neutral colour instead. A day
without sessions or a band SHALL keep the calorie band colours.

#### Scenario: A long-run day over the calorie target

- **WHEN** a day with a planned run reaches 130 % of the calorie target
- **THEN** the ring is shown in the neutral colour, not orange or red

### Requirement: A gentle note when clearly under-fuelled late in the day

The system SHALL show one secondary note that a carb-rich meal helps
recovery only when all of these are true:

- the shown day is today;
- it is 18:00 or later;
- the carbs logged are below 75 % of the band's lower edge.

It SHALL never show the note on a past day.

#### Scenario: Evening, far below the band

- **WHEN** it is 19:00, the range is 480–640 g and 300 g are logged
- **THEN** the gentle under-fuelling note is shown

#### Scenario: Afternoon

- **WHEN** it is 14:00 and 300 g are logged
- **THEN** no note is shown

### Requirement: Goal status never punishes eating inside the band

In the training experience the system SHALL judge a day's goals as follows:

- **With a carb band:** the calorie and carb goals are met once carbs reach
  the band's lower edge, including above the band.
- **On a training day without a band:** the calorie goal is met from 95 %
  of the target with no upper limit.
- **With a protein target:** protein is met from 90 % of it.

Without a plan target the judgement SHALL be exactly the food-first one.

#### Scenario: Well over the calorie target, inside the carb band

- **WHEN** the calorie target is 2,300 kcal, 3,100 kcal and 560 g of carbs are logged, and the band is 480–640 g
- **THEN** the day's calorie and carb goals are met

#### Scenario: On the calorie target but under-fuelled

- **WHEN** 2,300 kcal and 300 g of carbs are logged against a 480–640 g band
- **THEN** the calorie goal is not met

### Requirement: Fasting pauses on the plan's "off" days

In the training experience, on a day whose plan says `fasting: "off"`, the
system SHALL:

- show "Fasting paused — build week" instead of the fasting phase;
- show no fasting note when logging food for that day;
- schedule no fasting reminder that day;
- mark the day "Paused by the plan" in the history, neither kept nor
  broken.

A paused day SHALL NOT end the kept-days streak. The system SHALL NOT
change the user's fasting settings. Fasting SHALL resume on the next day
the plan allows it.

#### Scenario: Food during a paused fast

- **WHEN** the plan pauses fasting on Wednesday and food is logged inside Wednesday's fasting window
- **THEN** Wednesday shows "Paused by the plan" and the kept streak runs through it
