## Context

`BadgeMedallion(symbol:rarity:isLocked:size:)` is the only badge drawing in
the app, used at 40 to 120 pt from 11 call sites (Achievements grid and
detail, level tiers, sport and body, seasonal, supplements, the unlock
moment overlay). Badges carry a `badgeSymbol` (an SF Symbol name) and an
`AchievementRarity` (common, uncommon, rare, epic, legendary). There is no
Mac: Swift is compiled only in CI and seen only after a sideload, but SVG
renders in any browser here.

## Goals / Non-Goals

**Goals:** badges that look drawn rather than generated; a family and a
rarity readable without colour; art the owner can approve on this PC before
a build; one place that maps a badge to its picture, tested.

**Non-Goals:** see the proposal.

## Decisions

### D1. Style: "sticker"

A 3 pt (at 60 pt) dark outline in a warm near-black, flat fills in two tones
(base and shade, split on a diagonal), one soft highlight blob top-left, no
gradients inside motifs. Rounded joins everywhere. This is the cartoon look
the owner asked for and it survives 40 pt, where thin detail disappears.

*Alternatives:* glossy 3D medals (need gradients and filters that asset
catalog SVG support handles unevenly); flat line icons (close to today's SF
Symbols, so little gain). The owner picks between sticker and a flatter
"modern" variant on the gallery (task 0.1); both use the same layers, so the
choice changes fills and outline weight only.

### D2. Two layers: frame and motif

A badge is `frame(family, rarity)` + `motif`. Drawing 237 one-off pictures by
hand is not realistic and would not stay consistent; two layers give every
badge its own look from about 60 + 60 drawings.

- **Frame shape = family:** streak (flame-topped shield), logging (plate),
  macros (hexagon), levels (star), boss (horned shield), bingo (rounded
  square), journeys (pennant), records (rosette), collections (stamp with a
  scalloped edge), seasonal (wreath), sport and body (gear), supplements
  (capsule), secrets (keyhole).
- **Frame trim = rarity:** common plain; uncommon a second inner ring; rare
  two side gems; epic ribbon tails as well; legendary a crown as well. The
  rarity colours stay as they are, as the frame's fill.
- **Motif:** a 24 x 24 unit drawing in the frame's centre, in white and a
  light tint with the dark outline.

### D3. SVG in the asset catalog, composed in SwiftUI

The sources are SVG files under `ios/BadgeArt/` (written by
`tools/docs/write-badge-art.mjs` from hand-written path data; the files are
committed). Each frame and motif is one SVG file in an imageset with "Preserve Vector
Data" on and rendering "Original". `BadgeMedallion` stacks
`Image("badge-frame-<family>-<rarity>")` and `Image("badge-motif-<name>")`
in a `ZStack`, sized by `size`.

Only a conservative SVG subset is allowed, because Xcode's SVG support is
partial and a mistake shows up only on device: `path` only, absolute `M L C Z`
commands, solid `fill`/`stroke` with optional opacity, `stroke-linejoin`,
`stroke-linecap`. No
`filter`, `mask`, `clipPath`, `text`, `use`, gradients, CSS or transforms on
groups. A lint (`tools/docs/lint-badge-svg.mjs`) refuses anything else and
runs in CI.

*Alternative:* SwiftUI `Path` code per motif. Rejected: unreadable to
review, and the gallery would need a second copy of every drawing.

*Risk:* an SVG that Xcode renders differently from the browser. Mitigation:
the subset above, a first wave of only one family built and checked on
device before the rest is drawn (task 3.x), and the fallback in D5.

### D4. The catalog lives in Gamification

`BadgeArtCatalog` resolves a badge to `(family, motif)` from what every
badge already carries, so there is no table with one row per badge:

- **family** from the badge id's namespace (`bingo.`, `journey.`,
  `secret.`, ...), else from its `AchievementCategory` for the core
  `achv-*` badges;
- **motif** from the badge's `badgeSymbol`: 94 SF Symbol names map to 51
  drawings (`trophy`, `trophy.fill` and `rosette` are all the trophy). A
  new badge with a known symbol gets art without touching the catalog; an
  unknown symbol falls back (D5).

Badges of one series (all "N-day streak" badges) share frame shape and
motif; the rarity trim and colour tell them apart.

Tests: every badge in `BadgeRegistry.all` and every level tier has a motif;
every category has a family; every family is used. That the named motifs
and frames exist as SVG files, and that no file is unused, is checked by
`tools/docs/check-badge-art.mjs` in CI (a Swift test cannot see the files);
it reads the tables from the Swift source, as does the gallery.

### D5. Fallback and locked states

- No motif in the catalog, or an image that fails to load: today's disc and
  SF Symbol, unchanged. The app never shows an empty badge.
- Locked: the family's frame as a flat grey silhouette with the lock glyph;
  the motif is hidden. This tells the user which family the badge belongs to
  without revealing it.
- Hidden secret: the keyhole frame in grey with a question mark, exactly one
  picture for all of them.
- Differentiate Without Colour and VoiceOver: the family shape and rarity
  trim carry what colour carried; the accessibility label keeps naming the
  rarity in words.

### D6. The gallery is the approval gate

`tools/docs/build-badge-gallery.mjs` reads the catalog (exported to JSON by
the guide's existing extractor) and the SVG files and writes
`docs/guide/badges.html`: every badge at 44, 60 and 120 pt, locked and
unlocked, on light and dark backgrounds, with a filter by family. The owner
approves it in the browser; app code starts only after that.

## Risks / Trade-offs

- **Hand-written SVG takes time and taste.** The first wave draws the frames
  and 10 motifs only; the owner sees the style before the other 50.
- **Xcode's SVG rendering** (D3).
- **App size.** Budget 400 KB for all SVG; the lint reports the total.
- **40 pt legibility.** The gallery shows the smallest size next to the
  largest; a motif that turns to mush at 44 pt is redrawn simpler.

## Migration

None. No stored data changes; an old build and a new build read the same
stores.

## Owner answers (2026-10-01)

1. Sticker (outlined, cel-shaded). The gallery no longer shows the modern
   variant.
2. A locked badge shows its family shape in grey.
3. No one-off pictures in the first release.

## Open Questions (original wording)

1. Sticker (outlined, cel-shaded) or the flatter modern variant? Default:
   sticker.
2. Should a locked badge show its family shape (default) or stay a plain
   grey disc as today?
3. Any badge that deserves its own one-off picture in the first release
   (for example the level-20 tier or the hardest boss)? Default: none.
