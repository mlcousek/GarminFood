## ADDED Requirements

### Requirement: Five food collections can be discovered by logging matching foods

The system SHALL provide the collections Czech Classics, Around the World,
Fermented Friends, Rainbow and Czech Brands. An entry SHALL be discovered
the first time any logged food matches it — by name for dishes and colours,
by brand for brands — and the discovery date and matching food name SHALL be
recorded. A discovery SHALL be permanent even if the matching entry is later
deleted.

#### Scenario: Discovering svíčková

- **WHEN** the owner logs "Svíčková na smetaně s knedlíkem" for the first time
- **THEN** the Czech Classics entry "Svíčková" is discovered with today's date and that food name

#### Scenario: Brand matched by brand, not name

- **WHEN** the owner logs a food named "Tvaroh" with brand "Madeta"
- **THEN** the Czech Brands entry "Madeta" is discovered

#### Scenario: Deleted entry

- **WHEN** the only food that discovered "Kimchi" is deleted
- **THEN** "Kimchi" stays discovered

#### Scenario: Dish logged as parts

- **WHEN** on one day the owner logs "Vepřová pečeně", "Houskový knedlík" and "Dušené zelí"
- **THEN** "Vepřo-knedlo-zelo" is discovered

### Requirement: Undiscovered entries are shown as silhouettes with a hint

The system SHALL show each undiscovered entry as a silhouette with "???"
and a short riddle hint, and each discovered entry with its name, symbol,
discovery date and the food that discovered it. VoiceOver SHALL read an
undiscovered entry as undiscovered together with its hint.

#### Scenario: Browsing a collection

- **WHEN** the owner opens Czech Classics having discovered 6 of 24 entries
- **THEN** 6 named tiles and 18 silhouettes with hints are shown, with "6/24"

### Requirement: Discoveries and completion levels are rewarded once

The system SHALL award 5 XP once per discovered entry, SHALL unlock each
collection's badges when 25 %, 50 % and 100 % of its entries are discovered
(Rainbow: 50 % and 100 %), a "Rainbow Day" badge when all six colours are
logged on one day, "Brand Explorer" badges at 10, 25 and 50 distinct Czech
brands (counting products with an 859 barcode and unknown brand as distinct
brands), and overall badges at 50 % and 100 % of all entries. Several
discoveries in one evaluation SHALL produce a single combined moment.

#### Scenario: Quarter of Czech Classics

- **WHEN** the 6th of 24 Czech Classics entries is discovered
- **THEN** the 25 % Czech Classics badge unlocks and 5 XP is awarded for the discovery

#### Scenario: First run back-fill

- **WHEN** collections run for the first time and the last 42 days contain 17 matching foods
- **THEN** 17 entries are discovered and exactly one summary moment is shown

#### Scenario: Mystery Czech brand

- **WHEN** the owner logs a product with barcode "8595678901234" and no brand, and 9 named Czech brands were already seen
- **THEN** the distinct Czech brand count becomes 10 and "Brand Explorer 10" unlocks
