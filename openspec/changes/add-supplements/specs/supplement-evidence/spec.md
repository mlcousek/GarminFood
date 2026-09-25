## ADDED Requirements

### Requirement: Evidence cards explain each ingredient offline with cited sources

The system SHALL provide, without network access, an evidence card for
every built-in ingredient showing what it is used for, evidence strength,
typical dose, timing notes, the default upper limit, the sources with
links, and a statement that the information is not medical advice.

#### Scenario: Offline card

- **WHEN** the device is offline and the user opens the vitamin D card
- **THEN** it shows a default upper limit of 100 µg (4000 IU) per day, cites EFSA, and shows the disclaimer

#### Scenario: No EU upper limit

- **WHEN** the user opens the vitamin C card
- **THEN** it states that no EU upper limit is set and shows the US figure labelled as US

### Requirement: Daily ingredient totals are compared with the user's own limits

The system SHALL sum each ingredient across all products taken on a day,
convert units (including vitamin D IU to µg at 40 IU = 1 µg), and compare
the total with the user's target and upper limit. The user SHALL be able to
override the target and upper limit per ingredient and reset them to the
default.

#### Scenario: Zinc from two products

- **WHEN** a multivitamin with 10 mg zinc and a zinc tablet with 25 mg are both taken
- **THEN** today's zinc total is 35 mg and it is marked over the default 25 mg limit

#### Scenario: Athlete override

- **WHEN** the user raises the magnesium upper limit to 500 mg and takes 450 mg supplemental magnesium
- **THEN** no over-limit warning is shown for magnesium

#### Scenario: Reset

- **WHEN** the user resets the magnesium limit
- **THEN** the limit is 250 mg supplemental again

### Requirement: Over-limit warnings are informational and calm

The system SHALL show an over-limit warning on the totals and evidence views
for any ingredient whose day total is above the user's upper limit, and a
non-blocking notice when logging an extra dose that would exceed it. The
system SHALL NOT block logging, and SHALL NOT send a push notification about
limits.

#### Scenario: Extra dose over the limit

- **WHEN** caffeine is at 350 mg today and the user logs an extra 100 mg dose
- **THEN** the dose is logged and a notice explains that 450 mg is above the 400 mg daily limit

### Requirement: A label score explains product quality from the label only

The system SHALL compute for each product a 0–100 label score from label
transparency, dose relative to the evidence card's effective range, and
headroom under the user's upper limits. It SHALL always show the breakdown
alongside the number, and SHALL NOT present it as an external or official
rating.

#### Scenario: Proprietary blend

- **WHEN** a product lists a "proprietary blend" without per-ingredient amounts
- **THEN** its transparency part is reduced and the breakdown names the blend as the reason

#### Scenario: Effective dose

- **WHEN** a creatine product provides 5 g per serving
- **THEN** its dose part is at maximum

### Requirement: Certification is verified by the user through official lists

The system SHALL offer links that open the NSF Certified for Sport, Informed
Sport and Kölner Liste product search pages, and SHALL let the user mark a
product as certified by one of them, with the date. The system SHALL NOT
claim a certification the user has not set.

#### Scenario: Mark certified

- **WHEN** the user checks Kölner Liste and marks their creatine as listed on 2026-10-02
- **THEN** the product shows a "Kölner Liste (checked 2. 10. 2026)" badge in Czech

### Requirement: Barcode lookup prefills a product without blocking

The system SHALL look up a scanned barcode in Open Food Facts first and, for
US/Canada codes, in the NIH DSLD database, prefilling what is found. It
SHALL cache a successful lookup locally, and SHALL fall back to manual entry
when both lookups fail or the device is offline. It SHALL require the user
to confirm the ingredient amounts before saving.

#### Scenario: US product

- **WHEN** a UPC-A code starting with 0 is not in Open Food Facts but is in DSLD
- **THEN** name, brand and ingredient rows are prefilled for confirmation

#### Scenario: Offline scan

- **WHEN** the device is offline and a barcode is scanned
- **THEN** the manual editor opens with the barcode filled in
