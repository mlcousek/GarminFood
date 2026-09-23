## ADDED Requirements

### Requirement: Search returns one ranked list across all sources

The system SHALL return search results as a single list ranked by relevance.
The list covers the user's own foods (custom foods, favorites, previously
logged foods), Garmin's database (`GET /nutrition-service/food/search`,
confirmed 2026-09-14), and Czech Open Food Facts. Each result SHALL show a
small source badge. Duplicates of the same product across sources SHALL
appear once.

#### Scenario: Own custom food found by typing

- **WHEN** the user has a custom food "Domácí tvaroh" and types "tvaroh"
- **THEN** "Domácí tvaroh" appears in the results, marked as the user's own food

#### Scenario: Same product from two sources

- **WHEN** Garmin and Open Food Facts both return "Madeta Jihočeský tvaroh" with calories within 5% per 100 g
- **THEN** it appears once, as the directly loggable Garmin item

### Requirement: Matching tolerates Czech inflection, word order, diacritics and typos

The system SHALL match a query against food names regardless of:

- diacritics and letter case;
- word order;
- common Czech inflected forms;
- a single-character typo in words of four or more letters.

#### Scenario: Inflection

- **WHEN** the user searches "rohlíky"
- **THEN** foods named "Rohlík" are among the top results

#### Scenario: Word order and no diacritics

- **WHEN** the user searches "tvaroh mekky"
- **THEN** "Měkký tvaroh" is among the top 3 results

#### Scenario: Typo

- **WHEN** the user searches "banan" or "chlba"
- **THEN** "Banán" or "Chléb" respectively is among the top 3 results

#### Scenario: Unrelated garbage is not shown

- **WHEN** no word of a candidate matches any query word at any tier
- **THEN** that candidate is not shown

### Requirement: Foods the user eats often rank higher

The system SHALL boost results by how often and how recently the user has
logged them, and by favorite status, so that among comparable matches the
user's usual food ranks first.

#### Scenario: Usual yogurt first

- **WHEN** two yogurts match "jogurt" equally and the user logged one of them 10 times last month
- **THEN** that yogurt ranks above the other

### Requirement: Results appear instantly and update without jumping

The system SHALL show matching local foods on the first keystroke without
waiting on the network. The system SHALL merge remote results as they arrive
without reordering rows already shown. It SHALL keep previous results visible
while loading, and SHALL never report a cancelled request as an error.

#### Scenario: Offline typing

- **WHEN** the device is offline and the user types the name of a food they logged before
- **THEN** that food is shown immediately, with a note that online databases are unavailable

#### Scenario: Fast typing

- **WHEN** the user types quickly, cancelling in-flight requests
- **THEN** no error message flashes
