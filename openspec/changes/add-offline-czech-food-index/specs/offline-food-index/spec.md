## ADDED Requirements

### Requirement: Czech foods are searchable offline

Once the Czech offline index has been downloaded, the system SHALL search it
locally. It SHALL rank its results with the same relevance rules as every
other source, and SHALL return them without any network access.

#### Scenario: Airplane mode

- **WHEN** the device is offline and the user searches "tvaroh"
- **THEN** Czech quark products from the offline index are listed immediately

#### Scenario: No index yet

- **WHEN** the index has never been downloaded
- **THEN** search works exactly as without it, and Settings shows that the offline database is not downloaded

### Requirement: The index updates safely and cheaply

The system SHALL check for a new index version at most once a day. It SHALL
download a new version only on Wi-Fi, unless the user allows cellular. It
SHALL verify the file's SHA-256 against the manifest before replacing the
current index. A failed or corrupted download SHALL never replace a working
index.

#### Scenario: Corrupted download

- **WHEN** a downloaded index file's SHA-256 does not match the manifest
- **THEN** the file is discarded, the previous index keeps working, and the failure is visible in Settings and Diagnostics

### Requirement: Barcodes unknown to Garmin fall back to the offline index

When Garmin's barcode lookup has no match, the system SHALL look up the
scanned barcode in the offline index. On a hit, it SHALL continue through the
existing Garmin-match flow.

#### Scenario: Czech product barcode

- **WHEN** the user scans a Czech product's EAN that Garmin does not know, and the offline index contains it
- **THEN** the product is shown by its Czech name and can be matched and logged

### Requirement: Open Food Facts is credited

The system SHALL credit Open Food Facts and the ODbL licence in Settings →
About, and in the published index's release notes.

#### Scenario: About screen

- **WHEN** the user opens Settings → About
- **THEN** an "Open Food Facts (ODbL)" credit with a link is shown
