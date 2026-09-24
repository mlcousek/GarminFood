## ADDED Requirements

### Requirement: Each install has a data mode, and existing installs stay Garmin-connected

The system SHALL store a per-install data mode, either Garmin-connected or
standalone ("On this phone only"). When no mode is stored, it SHALL classify
an install that has a Garmin token or any local history (outbox, usage
history, weight or water entries) as Garmin-connected silently, without
showing onboarding, and SHALL treat an install with neither as a fresh
install that needs onboarding.

#### Scenario: The owner's phone after the update

- **WHEN** the new build first launches on a phone that has a stored Garmin token and past log history, and no mode is stored
- **THEN** the mode is stored as Garmin-connected, no onboarding is shown, and the app behaves exactly as before

#### Scenario: A fresh install

- **WHEN** the app first launches with no Garmin token and no local history
- **THEN** no mode is stored yet and onboarding is shown

### Requirement: First-launch onboarding lets the user choose Garmin or standalone

The system SHALL ask a fresh install how it wants to use the app, with "With
my Garmin account" and "Just on this phone". Choosing Garmin SHALL run the
existing Garmin sign-in and store Garmin-connected mode (also when the user
postpones sign-in). Choosing standalone SHALL store standalone mode and offer
goal setup (skippable) and a backup explainer. All onboarding text SHALL be
available in English and Czech.

#### Scenario: Choosing standalone

- **WHEN** a fresh install picks "Just on this phone" and completes or skips goal setup
- **THEN** standalone mode is stored and the Today screen opens with no Garmin banner

#### Scenario: Choosing Garmin but postponing sign-in

- **WHEN** a fresh install picks "With my Garmin account" and taps "Not now" on the sign-in sheet
- **THEN** Garmin-connected mode is stored and today's signed-out behaviour applies, including the "Not connected to Garmin" banner

### Requirement: Standalone mode makes no Garmin calls and hides Garmin-only surfaces

In standalone mode the system SHALL NOT call any Garmin route (no auth
refresh, drain, reconciliation, health refresh, profile read, meal backfill
or background delivery), and SHALL hide the auth and delivery banners, the
sync queue, Garmin sign-in and account rows, Garmin's read-only nutrition
plan, "Use Garmin's goal", "Default meal from Garmin's schedule", "Sync to
Garmin" for presets, the custom-food backing picker and the "Active today"
line. In Garmin-connected mode none of these surfaces or calls change.

#### Scenario: Standalone foreground

- **WHEN** a standalone install comes to the foreground
- **THEN** no network request goes to connectapi.garmin.com and no Garmin banner or sync-queue row is visible

#### Scenario: Garmin mode unchanged

- **WHEN** a Garmin-connected install comes to the foreground
- **THEN** it refreshes auth, drains and reconciles exactly as before this change

### Requirement: Weight and water stay on the phone in standalone mode

In standalone mode, logging or deleting a weigh-in or a drink SHALL commit to
the local store only, with no outbox entry, no Garmin delete and no negative
correction, and the "not in Garmin yet" badges SHALL be hidden. The water
total SHALL be the sum of the day's local entries.

#### Scenario: Logging water standalone

- **WHEN** a standalone user logs 250 ml
- **THEN** the day's water total rises by 250 ml and the hydration outbox stays empty

### Requirement: The mode can be switched explicitly, without silent data loss

The system SHALL let the user switch mode from Settings only after an
explicit confirmation that states what happens to their data. Switching
standalone to Garmin SHALL complete only after a successful sign-in and SHALL
keep the local food log on the phone (not uploaded). Switching Garmin to
standalone SHALL be refused while a delivery is in flight, and SHALL offer
undelivered food entries a choice between "Deliver first" (when signed in)
and "Keep on this phone", converting kept entries into local log entries.

#### Scenario: Switch refused during a drain

- **WHEN** the user confirms Garmin to standalone while a drain is running
- **THEN** the switch is refused with "Finishing sync, try again in a moment" and the mode is unchanged

#### Scenario: Keeping undelivered entries

- **WHEN** the user switches Garmin to standalone with two undelivered entries and picks "Keep on this phone"
- **THEN** both appear in the local food log for their day and meal, and the outbox no longer contains them

### Requirement: Garmin-only gamification is unavailable, not locked, in standalone mode

In standalone mode the system SHALL NOT offer any challenge, bingo square,
boss or journey that needs activities or active kcal, and SHALL hide
achievements that can only be earned from Garmin activity data instead of
showing them as locked. Food-, water-, weight-, fasting- and note-based
gamification SHALL work from local data, including goal-met status judged
against local goals.

#### Scenario: No activity challenges offered

- **WHEN** challenge rotation runs for a standalone install
- **THEN** no offered challenge requires activities or active kcal

#### Scenario: Goal met from local data

- **WHEN** a standalone user's local calorie goal is 1800 kcal and the day's local log totals 1790 kcal
- **THEN** the day is recorded as calorie goal met, the same way Garmin mode judges it
