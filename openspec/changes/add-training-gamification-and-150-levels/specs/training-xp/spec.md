## ADDED Requirements

### Requirement: Training rewards follow the plan and never pay for more

In the training experience the system SHALL award XP and badges only for
following the plan and for honest self-monitoring. It SHALL NOT award
anything in proportion to distance, duration, pace, elevation, body weight,
the number of sessions beyond the plan, or consecutive training days.

#### Scenario: An unplanned run

- **WHEN** a day has an activity that no planned session matched
- **THEN** that activity earns no XP and counts toward no badge

#### Scenario: Seven session days in a row

- **WHEN** seven consecutive days each have a session done as planned
- **THEN** the XP earned equals the sum of each day's own rewards, with nothing added for the run of days

#### Scenario: Outside the training experience

- **WHEN** the food-first experience is on
- **THEN** no training XP is granted and no training badge is unlocked

### Requirement: Honest self-monitoring earns XP once

The system SHALL award XP once per day for a morning check-in and for a pain
answer given with it, once per session for an RPE and for a note, once per
ISO week for a gate test at most 14 days old, and once per test session with
a recorded result. Check-in and pain XP SHALL be paid only for today and the
two days before.

#### Scenario: A morning check-in

- **WHEN** today's check-in is recorded
- **THEN** 10 XP is granted for today, once, however often the check-in is repeated or corrected

#### Scenario: A check-in filled in a week later

- **WHEN** a check-in for a day seven days ago first appears in the plan
- **THEN** it counts toward the check-in badges and earns no XP

### Requirement: Habits earn XP for ticks, full days, streaks and ladder steps

The system SHALL award XP for each habit done on a day (at most eight a
day), a bonus when every expected habit of the day is done, one-off rewards
when the best habit streak reaches 7, 30, 100 and 365 days, and a reward when
a ladder step becomes active. A streak day SHALL be a day on which at least
the ladder's gate share of the expected habits is done; a day with nothing
expected SHALL neither count nor break the streak, and today SHALL NOT break
it. Tick and full-day XP SHALL be paid only for today and the two days
before; a later tick SHALL still count for the streak and the badges.

#### Scenario: A full habit day

- **WHEN** all three habits expected today are ticked today
- **THEN** 2 XP is granted for each and 6 XP for the full day

#### Scenario: Back-filling two weeks

- **WHEN** habits for a day ten days ago are ticked today
- **THEN** no XP is granted for them, and the day counts for the habit streak

#### Scenario: The streak outlives the plan window

- **WHEN** the habit streak reaches 100 days although the plan file carries only the last weeks
- **THEN** the 100-day reward is granted once

### Requirement: A session earns XP only within the plan and the morning light

The system SHALL award XP for a planned session that is done within the
morning check-in's light: any option on a green morning or without a
check-in, the A or R option on an amber morning, the R option on a red
morning. A session done with a harder option than the light allows SHALL earn
nothing and SHALL make its day not kept. An amber or red morning followed by
its option SHALL earn an additional "honest call" reward for that day.

#### Scenario: Amber morning, the amber option

- **WHEN** the check-in is amber and the day's session is done with option A
- **THEN** the session XP and the honest-call XP are granted

#### Scenario: Red morning, the full session

- **WHEN** the check-in is red and the session is done with option G
- **THEN** no session XP and no day XP are granted for that day

#### Scenario: Green morning, the easier option

- **WHEN** the check-in is green and the session is done with option A
- **THEN** the session XP is granted in full

### Requirement: Rest and stopping are never punished

The system SHALL treat a rest day without an unplanned run as a kept plan
day and award the same day XP as a training day. A day whose sessions were
not done after a red check-in SHALL be a kept day. A session not done after
an amber check-in, and a skipped session, SHALL be excused: it SHALL NOT
break the day or the week. No reward SHALL be taken away.

#### Scenario: A rest day

- **WHEN** a day with no planned session ends with no unplanned run
- **THEN** the plan-day XP is granted for it

#### Scenario: Resting on a red morning

- **WHEN** the check-in is red and the day's session is not done
- **THEN** the day is kept, the plan-day XP is granted, and the week can still be kept

#### Scenario: A skipped session

- **WHEN** a session was skipped through a plan change
- **THEN** it earns nothing and does not break its day or week

### Requirement: Unplanned volume breaks the kept week

The system SHALL award the "week kept within plan" reward only for a week
the plan has closed, with no broken day, at least one kept day, run distance
at most 10 % over its target, and no unplanned run distance taking it over
the target. An easy week (deload, taper, recovery or transition) SHALL earn
an additional reward when it is kept and its run distance is at or under the
target.

#### Scenario: Extra kilometres

- **WHEN** a closed week's run distance is over its target and part of it was unplanned
- **THEN** the week is not kept and earns neither the week reward nor the easy-week reward

#### Scenario: A deload week respected

- **WHEN** a closed deload week has no broken day and its run distance is under the target
- **THEN** the week reward and the easy-week reward are both granted

#### Scenario: A week still open

- **WHEN** the plan has not closed a week
- **THEN** no week reward is granted for it yet

### Requirement: Plans, phases and seasons are rewarded for being followed

The system SHALL award XP once for each approved week, each week with two
strength sessions done, each phase that is closed with a recap, and each
season whose period has ended. A plan change made from the phone SHALL earn
no XP.

#### Scenario: A phase is closed

- **WHEN** a phase becomes closed and carries a recap
- **THEN** its reward is granted once

#### Scenario: Plan edits

- **WHEN** ten sessions are moved and moved back in one week
- **THEN** no XP is granted for the edits

### Requirement: Races reward preparation and execution, not distance or pace

The system SHALL award fixed XP per race for a complete prep (on or before
race day), for each carb-load day whose carbohydrate goal was met, for a
finished race, and for a written report. The amounts SHALL NOT depend on the
race's distance, elevation, result time, pace or priority. A race run after a
red check-in SHALL earn no finish reward. Reaching the goal and a personal
record SHALL be one-off badges.

#### Scenario: A short and a long race

- **WHEN** a 10 km race and a 100 km race are both finished
- **THEN** each earns the same finish XP

#### Scenario: Carb-load day

- **WHEN** a carb-load day's logged carbohydrate meets the day's fuel band
- **THEN** the carb-load XP is granted for that day

### Requirement: A wise stop is rewarded like a finish

The system SHALL award the finish amount, and reveal a secret badge once,
for a race that was not finished because a stop rule ended it, or that was
not started after a red check-in on race morning.

#### Scenario: Not starting on a red morning

- **WHEN** race morning's check-in is red and the race session is not done
- **THEN** the finish amount is granted for that race and the secret badge is revealed

### Requirement: Every training reward is paid once and outlives the plan window

The system SHALL key every training reward by its day, week, session, habit,
phase, season or race, and SHALL pay each key at most once however often the
plan is re-read. Counts behind the badge ladders SHALL be kept on the phone,
so they continue to grow after their days leave the plan file.

#### Scenario: The same plan read twice

- **WHEN** the same plan facts are evaluated twice
- **THEN** the second evaluation adds no XP and unlocks nothing new

#### Scenario: A badge ladder across months

- **WHEN** 100 sessions were done as planned over several months
- **THEN** the 100-session badge unlocks, although the plan file shows only the last weeks
