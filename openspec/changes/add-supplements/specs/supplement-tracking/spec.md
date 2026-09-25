## ADDED Requirements

### Requirement: Supplements are off by default and fully hidden when off

The system SHALL provide a Settings switch for supplements that is off on a
new or upgraded install. While it is off, the system SHALL NOT show the
Supplements screen, the Today supplements card, supplement reminders, or
supplement challenges. Turning it off SHALL keep all supplement data, and
turning it back on SHALL restore it.

#### Scenario: Fresh install

- **WHEN** the app is installed or updated and Settings is opened
- **THEN** the Supplements switch is off and no supplement UI appears anywhere

#### Scenario: Disable and re-enable

- **WHEN** a user with 3 products and 20 days of intake history turns the switch off and later on again
- **THEN** the 3 products and 20 days of history are shown again, and no supplement reminder was delivered while it was off

### Requirement: Products are added from a catalog, as custom products, or by barcode

The system SHALL let the user add a product from a built-in catalog (with
default serving, unit and linked ingredient), create a custom product with
one or more ingredients and amounts per serving, or scan a barcode that
prefills name and brand when found. It SHALL always let the user confirm or
edit ingredient amounts before saving.

#### Scenario: Catalog product

- **WHEN** the user adds "Creatine monohydrate" from the catalog
- **THEN** a product with 5 g creatine per serving is proposed and can be edited before saving

#### Scenario: Multi-ingredient product

- **WHEN** the user creates a custom "ZMA" product with zinc 15 mg, magnesium 450 mg (aspartate) and vitamin B6 10 mg per serving
- **THEN** one tick of it adds 15 mg zinc, 450 mg magnesium and 10 mg B6 to that day's ingredient totals

#### Scenario: Barcode not found

- **WHEN** a scanned barcode is found in neither Open Food Facts nor DSLD
- **THEN** the custom product editor opens with the barcode filled in and no other fields prefilled

### Requirement: Schedules decide what is due each day

The system SHALL compute each day's planned items from each product's
schedule: time slots, servings per slot, and a pattern of daily, every N
days, chosen weekdays, training days, or a repeating cycle of phases. A
schedule change SHALL apply from the day it is made and SHALL NOT change
what was due on earlier days.

#### Scenario: Creatine loading cycle

- **WHEN** creatine is scheduled as 4 servings a day for 7 days from 2026-10-01, then 1 serving a day
- **THEN** 2026-10-07 plans 4 servings and 2026-10-08 plans 1 serving

#### Scenario: Every other day

- **WHEN** vitamin D is scheduled every 2 days anchored on 2026-10-01
- **THEN** it is due on 2026-10-03 and not on 2026-10-02

#### Scenario: Training days without activity data

- **WHEN** a product is scheduled on training days and no activity data exists for a day tagged "race"
- **THEN** it is due on the race-tagged day and on no other day without activities

#### Scenario: Schedule edited

- **WHEN** on 2026-10-10 magnesium changes from daily to weekdays only
- **THEN** 2026-10-04 (a Sunday) still counts magnesium as planned, and 2026-10-11 (a Sunday) does not

### Requirement: A daily checklist records intake locally without waiting for the network

The system SHALL show each day's planned items grouped by time slot. The
user SHALL be able to tick an item, "Take all" for a slot, log a one-off
extra dose, and change yesterday's checklist. Every change SHALL be
committed to local storage and shown immediately, with no network request.

#### Scenario: Take all

- **WHEN** the morning slot has creatine, D3 and omega-3 and the user taps "Take all"
- **THEN** all three are recorded as taken for that day and the slot shows as done

#### Scenario: Fix yesterday

- **WHEN** the user forgot to tick the evening magnesium yesterday and ticks it from the Supplements screen today
- **THEN** yesterday's record includes magnesium and yesterday becomes a stack-complete day if nothing else was missing

#### Scenario: Airplane mode

- **WHEN** the device is offline and an item is ticked
- **THEN** it is recorded and shown as taken without any error

### Requirement: A day is stack complete only when every planned item is taken

The system SHALL mark a day as stack complete when every planned item for
that day has an intake record. A day with no planned items SHALL be
neutral. Extra doses SHALL NOT replace a planned item.

#### Scenario: One item missing

- **WHEN** 4 items were planned and 3 were taken plus one extra dose of something else
- **THEN** the day is not stack complete

#### Scenario: Nothing planned

- **WHEN** no item is planned on a day
- **THEN** the day is neither complete nor missed

### Requirement: The Today card shows supplements in two variants

The system SHALL offer a supplements card in the Today layout editor,
available only while the feature is on and at least one product exists. It
SHALL have a *current slot* variant (the next due slot with ticks and "Take
all", collapsing to a done state when the day is complete) and a *whole day*
variant (every slot as compact pills). Turning the feature off SHALL leave
the default Today order unchanged.

#### Scenario: Default order unaffected

- **WHEN** the feature has never been enabled
- **THEN** the Today card order is identical to the order before this change

#### Scenario: Slot variant after the morning

- **WHEN** the morning slot is done and the evening slot has magnesium due
- **THEN** the card shows the evening slot with magnesium and a tick button

### Requirement: Stock and cost are tracked per product

The system SHALL let the user enter pack size (servings) and price per pack,
SHALL subtract each taken serving from the remaining stock, SHALL project
days left from the current schedule, and SHALL show cost per day and per
month.

#### Scenario: Days left

- **WHEN** a pack of 120 capsules at 2 capsules a day has 30 capsules left
- **THEN** 15 days left are shown

#### Scenario: Cost

- **WHEN** a pack of 60 servings costs 450 CZK and 1 serving is planned daily
- **THEN** the cost is shown as 7,50 CZK per day in Czech and about 225 CZK per month

### Requirement: Adherence history is shown per product and overall

The system SHALL show a calendar of stack-complete, partial, missed and
neutral days, and per product the percentage of planned servings taken over
the last 7 and 30 days.

#### Scenario: Partial adherence

- **WHEN** creatine was planned 30 times in the last 30 days and taken 27 times
- **THEN** creatine shows 90 % for 30 days

### Requirement: Supplement data is included in the standalone backup

The system SHALL include supplement products, schedules, intake history and
limit overrides in the standalone-mode data export, and SHALL restore them
on import.

#### Scenario: Export and restore

- **WHEN** a standalone user exports data with 2 products and 10 intake days and restores it on a fresh install
- **THEN** the 2 products and 10 intake days are present after restore
