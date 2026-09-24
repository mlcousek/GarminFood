## ADDED Requirements

### Requirement: Streak freezes are earned and capped

The system SHALL grant one streak freeze for each defeated weekly boss and
each fully completed weekly bingo card, SHALL hold at most 2 unused freezes
(grants beyond the cap are discarded), and SHALL show the number of
available freezes on the streak card and streak screen.

#### Scenario: Bank full

- **WHEN** the owner holds 2 freezes and completes a full bingo card
- **THEN** the balance stays at 2 and the streak screen notes that the bank was full

### Requirement: A freeze automatically covers a recent missed day that would break the streak

The system SHALL, without user action, consume one available freeze for a
missed day within the last 7 days, before today, that would otherwise reset
a running streak of at least 3 days, provided the freeze was earned before
that missed day. A frozen day SHALL keep the streak running without
increasing its length, SHALL NOT use up the one-miss-per-week forgiveness,
and SHALL be shown as frozen in the streak calendar. A missed day already
forgiven by the weekly grace rule SHALL NOT consume a freeze. A consumed
freeze SHALL NOT be refunded if the day is later backfilled.

#### Scenario: Second miss in a week is frozen

- **WHEN** the streak is 21, Tuesday was forgiven by grace, Thursday is missed, and one freeze earned on the previous Sunday is available
- **THEN** on Friday Thursday is marked frozen, the streak is still 21, the balance drops to 0 and a freeze moment is shown

#### Scenario: Grace day does not use a freeze

- **WHEN** only one day in the last 7 is missed
- **THEN** it is shown as forgiven by grace and no freeze is consumed

#### Scenario: Short streak not protected

- **WHEN** a 2-day streak would be broken by a missed day
- **THEN** no freeze is consumed

#### Scenario: Freeze earned after the miss

- **WHEN** the only freeze was granted on Saturday and the streak-breaking miss was on Thursday
- **THEN** the freeze is not used for Thursday

#### Scenario: Existing behaviour without freezes

- **WHEN** no freeze has ever been earned
- **THEN** streak length, grace and at-risk status are exactly as before this change
