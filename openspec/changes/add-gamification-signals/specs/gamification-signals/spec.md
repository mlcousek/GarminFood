## ADDED Requirements

### Requirement: Foods are classified into real-world tags from their name, brand and barcode

The system SHALL assign each logged food a set of tags (for example fruit,
vegetable, fish, fermented, coffee, sugary drink, a cuisine, a colour, Czech
brand) using a deterministic keyword dictionary applied to the food's name
and brand after the same diacritic folding and Czech stemming that food
search uses. Exclusion phrases SHALL take precedence over inclusion phrases.
A food SHALL be tagged as a Czech brand when its brand is on the shipped
Czech-brand list, or, when its brand is unknown, when its barcode is a
13-digit EAN beginning with 859.

#### Scenario: Czech name with diacritics and inflection

- **WHEN** the logged food is named "Kysané zelí"
- **THEN** its tags include fermented and vegetable

#### Scenario: Exclusion beats a similar word

- **WHEN** the logged food is named "Rybízový džem"
- **THEN** its tags do not include fish

#### Scenario: Czech brand by list

- **WHEN** the logged food is "Kofola Original" with brand "Kofola"
- **THEN** its tags include sugaryDrink and czechBrand

#### Scenario: Czech brand by barcode fallback

- **WHEN** a food has no brand and its barcode is "8594001234567"
- **THEN** its tags include czechBrand

#### Scenario: Untaggable food

- **WHEN** a food has no name available from any source
- **THEN** it has no tags and still counts as a logged entry

### Requirement: Each nutrition-day has a signals aggregate built from local data first

The system SHALL build, for each of the last 42 logged-date days, an
aggregate containing: the day's entries (with tags, timestamp, meal and
per-entry macros when known), macro totals including fibre and sugar when
known, goals, water total and goal, active kilocalories, Garmin activities,
the day's last weigh-in, the fasting outcome and the day-note tags, plus
flags stating which of these data sources were available. The aggregate
SHALL be computed without any network call, from local stores and cached
Garmin reads. When a cached Garmin day log exists, its entries and totals
SHALL take precedence, and locally logged entries newer than that cache
SHALL be added without double counting an entry that appears in both.

#### Scenario: Entry logged after the Garmin day log was cached

- **WHEN** the Garmin day log for today was cached at 12:00 with 3 entries and the user logs a 4th entry at 12:30
- **THEN** today's signals contain 4 entries

#### Scenario: Same entry in both sources

- **WHEN** a local entry and a cached Garmin entry have the same food id and timestamps 60 seconds apart
- **THEN** the day's signals contain that entry once

#### Scenario: Missing water data

- **WHEN** no local or Garmin hydration value exists for a day
- **THEN** that day's water value is absent and its availability flag for water is false, and no water-based rule counts the day as failed or met

#### Scenario: Offline

- **WHEN** the device is offline
- **THEN** signals are still built for every day from local data and previously cached reads

### Requirement: Garmin activities are read, cached and never written

The system SHALL read the owner's activities with
`GET /activitylist-service/activities/search/activities?startDate&endDate&limit`
(confirmed 200 on 2026-09-24) during background or foreground refresh only,
at most once per 30 minutes, for the last 14 days with a limit of at most 20
per request, and SHALL cache each activity's type, start time, duration,
calories and distance per day for 120 days. The system SHALL NOT issue any
write request to Garmin for gamification. A failed activities read SHALL
leave the previous cache intact and SHALL be recorded in the diagnostics
log; an authentication failure SHALL surface through the existing sign-in
banner.

#### Scenario: Activities cached for offline use

- **WHEN** a refresh reads a 45-minute run that started at 07:10 on 2026-09-23 and the device then goes offline
- **THEN** the signals for 2026-09-23 still include that run

#### Scenario: Activities route fails

- **WHEN** the activities read returns HTTP 500
- **THEN** previously cached activities remain available and a diagnostics entry is recorded

#### Scenario: Logging food does not wait for activities

- **WHEN** the user confirms a food entry while the activities read is slow
- **THEN** the entry is saved and shown without waiting for that read

### Requirement: Gamification features plug in through a registry and grant rewards idempotently

The system SHALL run every registered gamification feature after each
gamification refresh and after each confirmed log, passing the current
signals snapshot. Rewards SHALL be identified by a unique key, and applying
a reward whose key was already applied SHALL have no effect. A feature that
fails SHALL be skipped and logged without preventing other features from
running or the log entry from being saved.

#### Scenario: Same reward evaluated twice

- **WHEN** a feature reports the reward "bingo.line.2026-W39.row0" worth 25 XP on two consecutive refreshes
- **THEN** total XP increases by 25 exactly once

#### Scenario: One feature fails

- **WHEN** one registered feature throws an error during evaluation
- **THEN** the other features' rewards and moments are still applied and a diagnostics entry names the failing feature

### Requirement: Secret and limited-edition badges are supported and do not change existing completionist achievements

The system SHALL support badges marked secret, whose title and description
are hidden until unlocked while their count is shown, and badges marked
limited edition, tied to a named event. Achievements that require unlocking
a fraction of all other achievements SHALL continue to count only the
achievements that existed before feature badges were added.

#### Scenario: Locked secret badge

- **WHEN** a secret badge is not yet unlocked
- **THEN** the achievements screen shows it only as a "???" tile, without its title or description

#### Scenario: Completionist denominator unchanged

- **WHEN** 40 new feature badges are registered
- **THEN** the progress of each existing "unlock N% of achievements" badge is the same as before they were registered

### Requirement: Existing progress survives the upgrade

The system SHALL decode every gamification file written before this change
(challenge state, achievements, XP, lifetime stats) without data loss, and
SHALL keep every previously unlocked achievement, completed challenge and
XP total.

#### Scenario: Upgrade with an active ladder challenge

- **WHEN** the app upgrades while "log-streak-12" is the active challenge
- **THEN** that challenge remains active with its progress and completes normally, even though it no longer enters rotation
