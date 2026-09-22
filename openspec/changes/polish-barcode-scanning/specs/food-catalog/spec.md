## ADDED Requirements

### Requirement: A barcode can be resolved from manual digit entry, not only a camera scan

The system SHALL offer a manual entry path for a barcode when scanning it
with the camera is not possible or not working, and SHALL resolve a
manually entered code through the same resolution logic (including UPC-A/
EAN-13 leading-zero normalisation) used for a camera-scanned code, so the
outcome for the user is identical regardless of entry method.

#### Scenario: Manually entering a barcode that resolves to a Garmin food

- **WHEN** the user types a barcode's digits instead of scanning it
- **THEN** the system attempts resolution exactly as it would for a scanned
  code of the same value
- **AND** a resolved food is presented the same way a camera-scanned result
  would be

#### Scenario: Manually entering an implausible value

- **WHEN** the user types a value that is not shaped like a real barcode
  (too short, too long, or containing non-digit characters)
- **THEN** the system does not attempt a lookup for it
