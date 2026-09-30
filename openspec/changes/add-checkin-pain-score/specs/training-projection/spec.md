## ADDED Requirements

### Requirement: Day pains are decoded tolerantly

Each projection day's `pains` SHALL be decoded as "not asked" when absent,
`null` or not a list; as "nothing hurts" when `[]`; and otherwise as a list
of entries, dropping (and recording) an entry without a numeric score,
reading an unknown site as `other` and a missing or `null` note as none.

#### Scenario: Unknown site

- **WHEN** a day has `pains: [{"site": "hip-left", "score": 2}]`
- **THEN** it decodes to one entry, site `other`, score 2, no note

#### Scenario: Broken entry

- **WHEN** a day has one entry without a score and one valid entry
- **THEN** the valid entry is kept and the broken one is dropped
