## Why

Every badge in the app (237 achievements, plus level tiers, boss, bingo,
journey, record, collection, seasonal, sport and supplement badges) is the
same picture: a coloured disc with a white SF Symbol on it
(`DesignSystem/BadgeMedallion.swift`). Only 16 distinct symbols are named in
Gamification's sources, so most badges differ by colour alone. The owner asked
for better images, "a bit cartoon looking or in modern style".

`BadgeMedallion`'s header says real image assets were avoided because nothing
could be previewed without a Mac. That is no longer the whole story: SVG can
be drawn and previewed in a browser on this Windows machine, the interactive
guide (`docs/guide/`) already shows every badge, and Xcode asset catalogs
compile SVG directly. So art can be authored, reviewed and approved here
before it is ever built.

## What Changes

- A drawn badge style ("sticker"): a thick dark outline, flat cel-shaded
  fills with one highlight, and a frame whose **shape** tells the badge's
  family and whose **trim** tells its rarity, so rarity no longer rests on
  colour alone.
- Badges are composed from two layers: a **frame** (family x rarity) and a
  **motif** (what the badge is about: flame, fork, scale, drop, moon, boss
  face, ...). About 12 frame shapes x 5 rarities and about 60 motifs cover
  every badge; no badge gets a one-off picture in the first release.
- The art lives as SVG under `ios/BadgeArt/` (outside the app target's
  folder, which XcodeGen globs into the bundle) and is
  compiled into `Assets.xcassets` as vector imagesets. A catalog in
  Gamification names each badge's motif and family; `BadgeMedallion` draws
  frame + motif, and falls back to today's disc + SF Symbol for any badge
  without a motif.
- A gallery page (`docs/guide/badges.html`, generated from the same SVG and
  the same catalog) shows every badge at 44, 60 and 120 pt, locked and
  unlocked, light and dark. The owner approves the style on that page
  **before** any app code changes.
- A locked badge shows its frame shape as a grey silhouette with a lock; a
  hidden secret stays a question mark on a plain frame.

## Capabilities

### New Capabilities

- `badge-art` - the drawn badge style, the frame + motif composition, the
  motif catalog, the gallery and the fallback rules.

### Modified Capabilities

None. Which badges exist, how they unlock and what they are called does not
change.

## Non-goals

- **Raster art or AI-generated images.** Everything is hand-written SVG, so
  it stays small, sharp at 120 pt and reviewable as a diff.
- **Animated badges.** The existing one-shot shine for epic and legendary
  stays; no new animation.
- **New badges, renamed badges or changed unlock rules.**
- **The app icon and the widget.** The widget target does not link
  Gamification and shows no badges.

## Impact

`ios/GarminFood/DesignSystem/BadgeMedallion.swift` (drawing), its 11 call
sites (a new `family`/`motif` argument, or a badge value), a new
`Gamification/BadgeArtCatalog.swift` with tests, new SVG sources and
imagesets, `tools/docs/` (gallery generator and an SVG lint), `docs/guide/`.
App size grows by the SVG set (budget: under 400 KB).

**Depends on**: nothing. **Unblocks**: per-badge one-off art later.
