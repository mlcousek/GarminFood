## ADDED Requirements

### Requirement: Secret achievements stay hidden until unlocked

The system SHALL provide 15 secret achievements whose titles and
descriptions are not displayed, nor read by VoiceOver, until unlocked. The
achievements screen SHALL show each locked secret as a "???" tile and the
number of secrets found out of the total.

#### Scenario: Nothing found yet

- **WHEN** no secret achievement is unlocked
- **THEN** the achievements screen shows 15 "???" tiles and "0 of 15 secrets found", and no secret title appears anywhere in the app

### Requirement: Secret achievements unlock by exact rules from logged data

The system SHALL unlock each secret achievement when its rule holds on the
logged data, including: an entry timestamped 00:00–03:59 whose logged date
is that same calendar date (Midnight Fridge Raid); at least 5 coffee
entries on one day (Barista Mode); a pizza entry on 4 consecutive Fridays
(Pizza Friday); a completed day whose rounded calorie total equals the
rounded calorie goal with at least 3 entries (Bullseye); a completed day
with at least 3 entries whose rounded calorie total is at least 1000 and a
palindrome (Palindrome Day); any entry logged on a Friday the 13th; and at
least 7 distinct cuisines within one ISO week (World Tour Week). Rules that
refer to completed days or weeks SHALL NOT use the current day or week.

#### Scenario: Fridge raid

- **WHEN** the owner logs a yoghurt at 01:30 with today's date
- **THEN** Midnight Fridge Raid unlocks

#### Scenario: Backfilled late-night entry

- **WHEN** at 01:30 the owner logs a meal dated yesterday
- **THEN** Midnight Fridge Raid does not unlock

#### Scenario: Palindrome day

- **WHEN** yesterday had 4 entries totalling 1,221 kcal
- **THEN** Palindrome Day unlocks

#### Scenario: Not yet a palindrome

- **WHEN** today's running total is 1,221 kcal
- **THEN** Palindrome Day does not unlock until the day is completed with that total

#### Scenario: Pizza Friday broken

- **WHEN** pizza was logged on three Fridays, then not on the fourth, then on the fifth
- **THEN** Pizza Friday does not unlock

### Requirement: Unlocking a secret is a reveal moment with a reward

The system SHALL, when one or more secrets unlock, show a single reveal
moment naming them, award the standard achievement bonus plus 50 XP per
secret exactly once, and unlock a visible "Secret Keeper" achievement when
all 15 secrets are unlocked.

#### Scenario: Two secrets at once

- **WHEN** one evaluation unlocks Barista Mode and Gone Fishing
- **THEN** one moment names both and each awards its XP once
