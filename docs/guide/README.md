# GarminFood guide

`index.html` is an interactive guide to the whole app: architecture, every
screen and flow, the full gamification catalog (achievements, challenges,
daily challenges, bingo, bosses, journeys, records, collections, seasonal
events, secrets, sport & body), supplements, localization and a glossary.
It has search, EN/CS catalog text, rarity/feature/category/standalone filters
and a spoiler switch for secret badges and undiscovered collection entries.

## Open it

- **As a file:** open `docs/guide/index.html` in a browser. The catalog data
  is embedded in the page (`<script id="guide-data">`), so it works on its
  own. Badge icons come from Lucide on cdn.jsdelivr.net; offline, each
  medallion falls back to a letter.
- **Served from the repo** (for example `python -m http.server` in
  `docs/guide/`): the page loads the sibling `data/*.json` files and prefers
  them over the embedded copy.
- **As a claude.ai artifact:** publish `index.html` alone; everything it
  needs is inline.

## Regenerate the data

```sh
node tools/docs/extract-guide-data.mjs --embed
```

This rewrites `docs/guide/data/*.json` from the Swift sources and string
tables and refreshes the embedded copy inside `index.html`. Without
`--embed` only the JSON files are written. Node only, no dependencies.

The output depends only on `ios/`, so re-running it on the same commit
produces identical files. `data/meta.json` (and the line under the page
title) records the last commit that touched `ios/`, and whether `ios/` had
uncommitted changes.

How each catalog is read is recorded in every file's `source` field:

- `parsed`: read from a literal Swift table (`BingoTask(...)`,
  `Spec(...)`, `static let` constants and so on).
- `mirrored`: the Swift code builds the catalog in a loop (core achievement
  families, challenge ladders, daily-challenge variants, the level curve,
  the XP budget). The loop inputs are parsed; the loop body (id pattern,
  window and XP formula, English sentence) is mirrored in the script. The
  script checks that the Swift formula text it mirrors is still present and
  fails with “mirror out of date” when it isn't. Update the script then.
- `hand-read`: prose written from reading the code (for example which days
  a boss counts). The file it came from is named next to it.

Czech text comes from `Gamification/Resources/cs.lproj/{Catalog,Localizable,Collections}.strings`,
`FoodLogCore/Resources/cs.lproj/Localizable.strings(dict)` and
`GarminFood/Resources/Localizable.xcstrings`. Any catalog string without a
Czech translation is listed in `data/l10n-gaps.json` and marked “EN” in the
page.

The screen and flow sections of the page are written by hand from the code;
update them when behaviour changes. `review-notes.md` lists inconsistencies
found while writing the guide.
