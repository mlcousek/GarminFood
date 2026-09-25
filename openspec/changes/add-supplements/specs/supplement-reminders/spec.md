## ADDED Requirements

### Requirement: One reminder per time slot, only while that slot is not done

The system SHALL schedule a local notification for each time slot that has
planned items on a day, at that slot's reminder time, and SHALL remove or
skip it once every item in that slot is taken. Reminders SHALL be re-planned
whenever the app comes to the foreground, an item is ticked, or a
supplement setting changes.

#### Scenario: Slot completed early

- **WHEN** the evening reminder is set for 21:00 and all evening items are ticked at 19:30
- **THEN** no evening supplement notification is delivered that day

#### Scenario: Nothing due in a slot

- **WHEN** the pre-workout slot has no planned items on a rest day
- **THEN** no pre-workout notification is scheduled for that day

### Requirement: The reminder has a "Taken" action that ticks the slot

The system SHALL attach a "Taken" action to each slot reminder. Choosing it
SHALL record every planned item of that slot for that day as taken without
opening the app, and choosing it more than once SHALL NOT create duplicate
records. If the record cannot be written, the system SHALL open the app on
that slot and log the failure to diagnostics.

#### Scenario: Taken from the lock screen

- **WHEN** the 08:00 morning reminder shows creatine and D3 and the user taps "Taken"
- **THEN** creatine and D3 are recorded as taken for that day and the Today card shows the morning slot as done on next open

#### Scenario: Double tap

- **WHEN** the "Taken" action is delivered twice for the same slot and day
- **THEN** each item has exactly one intake record for that slot

### Requirement: A restock reminder fires before a product runs out

The system SHALL notify the user once per pack when the projected days left
for a product reach the user's restock lead time (default 7 days).

#### Scenario: Running low

- **WHEN** omega-3 is projected to run out in 7 days and the lead time is 7 days
- **THEN** one restock notification for omega-3 is delivered, and none again until stock is refilled

### Requirement: Reminder texts follow the app language

The system SHALL write supplement reminder titles and bodies in the app's
current language, and SHALL re-plan pending supplement reminders when the
language changes.

#### Scenario: Language switch

- **WHEN** a morning reminder is pending in English and the app language is switched to Czech
- **THEN** the pending reminder is replaced by one in Czech
