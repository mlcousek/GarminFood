## ADDED Requirements

### Requirement: Badges are drawn from a frame and a motif

The app SHALL draw each badge as a frame chosen by the badge's family and
rarity, with a motif chosen by the badge's subject on top of it. The frame's
shape SHALL identify the family and the frame's trim SHALL identify the
rarity, so that neither depends on colour alone.

#### Scenario: Two badges of different families

- **WHEN** a streak badge and a collections badge of the same rarity are shown side by side
- **THEN** their frames have different shapes and the same rarity trim

#### Scenario: Two rarities of one series

- **WHEN** a common and a legendary badge of the same series are shown
- **THEN** they share the motif and the frame shape, and the legendary one carries the legendary trim

#### Scenario: Differentiate Without Colour

- **WHEN** the system setting Differentiate Without Colour is on
- **THEN** family and rarity can still be told apart by shape and trim, and VoiceOver names the rarity in words

### Requirement: Every badge resolves to art or to the fallback

Every badge the app can show SHALL resolve through one catalog to a family
and a motif. A badge without a motif, or whose image cannot be loaded, SHALL
be drawn as the previous disc with its SF Symbol. The app SHALL never show
an empty badge.

#### Scenario: A badge with no motif yet

- **WHEN** a badge has no motif in the catalog
- **THEN** it is shown as the coloured disc with its SF Symbol, as before this change

#### Scenario: The catalog and the files agree

- **WHEN** CI runs
- **THEN** it fails if a motif or frame named in the catalog has no SVG file, or an SVG file is not used by the catalog

### Requirement: Locked and secret badges do not reveal their subject

A locked badge SHALL show its family's frame as a grey silhouette with a
lock and SHALL NOT show its motif. A hidden secret badge SHALL show one
shared grey frame with a question mark, whatever its family.

#### Scenario: A locked badge

- **WHEN** a badge is not yet earned and is not a hidden secret
- **THEN** its frame shape is visible in grey with a lock, and its motif is not

#### Scenario: A hidden secret

- **WHEN** a secret badge is not yet earned
- **THEN** it shows the shared question-mark frame and nothing that tells its family or subject

### Requirement: Badge art uses a restricted SVG subset

Badge art SHALL be SVG limited to paths, circles, rectangles and groups with
solid fills and strokes. A lint SHALL refuse filters, masks, clip paths,
text, references, gradients and embedded styles, and SHALL report the total
size of the set.

#### Scenario: A drawing uses a gradient

- **WHEN** an SVG file under the badge art sources contains a gradient
- **THEN** the lint fails and names the file

### Requirement: The style is approved on a gallery before it ships

A gallery page SHALL be generated from the same SVG files and the same
catalog as the app, showing every badge at 44, 60 and 120 points, locked and
unlocked, on light and dark backgrounds. The badge drawing code in the app
SHALL NOT change until the owner has approved the gallery.

#### Scenario: The owner reviews the style

- **WHEN** the gallery is opened in a browser on the owner's PC
- **THEN** every badge appears at the three sizes in both states and both appearances, with a filter by family
