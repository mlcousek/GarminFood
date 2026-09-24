## Context

Uses `add-gamification-signals`: the `.collections` tag-rule slot
(`FoodTagRules+Collections.swift`, owned here), core tags (`colour.*`,
`fermented`, `czechBrand`), `CzechBrands`, barcodes from
`FoodProvenanceStore` via `SignalEntry.barcode`, the feature seam and
`RewardLedger`. No network.

## Decisions

### D1 — One matching engine: every entry is a tag

Each collection entry has a tag `dish.<id>` (or `brand.<id>`) declared in
`FoodTag+Collections.swift`, and a `FoodTagRule` in the `.collections` rule
set (phrases + exclusions, or `anyBrands` for brands). Discovery is simply
"some logged entry carries this tag". This reuses the tagger's folding and
Czech stemming and its golden-test approach. Rainbow entries reuse the core
`colour.*` tags.

### D2 — Collections

**Czech Classics** (`czech-classics`, 24): svíčková (svíčková na smetaně),
guláš, řízek, smažený sýr, knedlíky (houskový/bramborový knedlík),
bramboráky (bramborák), koprovka (koprová omáčka), kulajda, trdelník,
buchty, vepřo-knedlo-zelo ("vepřová pečeně" + knedlík + zelí on one day,
or a food named so), tatarák (tatarský biftek), utopenci, nakládaný
hermelín, česnečka, rajská omáčka, ovocné knedlíky, palačinky, chlebíček,
bramboračka, segedínský guláš, španělský ptáček, koláč, frgál.

**Around the World** (`world`, 22): sushi, ramen, curry, tikka masala,
tacos, burrito, pho, pad thai, pizza, lasagne, risotto, gyros, souvlaki,
falafel, hummus, kebab, paella, bibimbap, dim sum/dumplings (jiaozi),
croissant, pierogi, borščč (borscht).

**Fermented Friends** (`fermented`, 11): kefír, kysané zelí, kimchi,
jogurt, kombucha, miso, tempeh, zákys/acidofilní mléko, olomoucké
tvarůžky, kvašáky (kvašené okurky), kváskový chléb (sourdough).

**Rainbow** (`rainbow`, 6): red, orange, yellow, green, purple, white
(core `colour.*` tags from fruit/veg keywords; e.g. purple = lilek,
borůvky, červené zelí, řepa, švestky; white = květák, cibule, česnek,
žampiony).

**Czech Brands** (`czech-brands`, 22): Madeta, Kunín, Tatra, Olma,
Hollandia, Pilos, Albert Quality, Penam, Opavia, Orion, Kofola, Mattoni,
Relax, Hamé, Vitana, Jihlavanka, Kostelecké uzeniny, Choceňská mlékárna,
Pribináček, Emco, Bonavita, Semix — the same list as `CzechBrands.all`, one
entry each.

Each entry: `id`, display `name`, `emoji` or SF Symbol, `hint` (a riddle,
max ~80 characters, e.g. svíčková: "Cream sauce, cranberries, a lemon
slice — Sunday lunch at babička's"; utopenci: "Sausages that 'drowned' in a
jar of vinegar and onion"; kimchi: "Korea's spicy answer to kysané zelí").

Special entry rules:
- **Vepřo-knedlo-zelo** is discovered either by one food matching the
  phrase or by a single day containing `meat` + `knedlik` + a
  sauerkraut/cabbage (`zeli`) entry — the dish is often logged as parts.
- **Brands** match `brand` text only (not the name), so "Jogurt s příchutí
  Kofoly" (unlikely but possible) does not count as Kofola.

### D3 — Discovery and persistence

- On each run the feature scans the snapshot's days (42-day window) for
  entry tags not yet discovered and records `discovered[entryId] =
  (day, foodName)`. The first run thereby back-fills the last 42 days.
- Discovery is permanent: deleting the entry later does not undiscover.
- `CollectionsStore` (`features/collections/collections.json`):
  `{ discovered: {entryId: {day, foodName}}, czechBrandsSeen: [String]?,
  mysteryCzechBarcodes: [String]?, rainbowDays: Int? }`, Optional fields,
  quarantine helpers.
- **Brand Explorer** counts distinct Czech brands: named brands from the
  list, plus each distinct 859-barcode product whose brand is unknown
  (stored by barcode, capped at 500).

### D4 — Rewards

- Each new discovery: `collection.found.<entryId>` → 5 XP.
- Per collection: `collection.<id>.25`, `.50`, `.100` badges (common /
  rare / epic; Rainbow uses 50 % and 100 % only).
- `collection.rainbow-day`: all six colours on one day (rare);
  `collection.rainbow-day-10`: ten such days (epic).
- `collection.brand-explorer-10` / `-25` / `-50` distinct Czech brands
  (uncommon / rare / epic; 50 is only reachable with 859 "mystery" brands,
  intentionally).
- `collection.pokedex-50` / `-100`: 50 % / 100 % of all entries across
  collections (epic / legendary).
- Moments: at most **one** discovery moment per feature run (if several,
  "3 new discoveries — Kimchi, Pho, Kefír"), style `.celebration`, so a
  big back-fill does not flood the overlay; the first run's back-fill
  shows a single summary moment ("Your collections start with 17 finds").

### D5 — UI

- `CollectionsSlotView`: "Collections 17/85" with five mini progress rings.
- `Progress/Collections/CollectionsView.swift`: one section per collection,
  a grid of tiles. Discovered: emoji/symbol, name, date and the food that
  found it. Undiscovered: a greyed silhouette (`questionmark` over a plate
  symbol), "???", and the riddle hint. Tapping shows the hint large.
  VoiceOver reads "Undiscovered, hint: …".

### D6 — Testing

- Tag rules golden: every entry has at least one positive and, where risky,
  one negative fixture (e.g. "gulášová polévka" → guláš yes; "Pizza
  ochucovadlo" → pizza no; "Hollandia" brand → brand.hollandia; name
  "Kefírové mléko" → kefír).
- Discovery: back-fill from 42 days; permanence after deletion;
  vepřo-knedlo-zelo by parts on one day but not across two days.
- Brand Explorer with named brands + 859 unknown-brand barcodes (distinct
  counting, cap).
- Rewards: XP per discovery once; percentage badges at exact thresholds
  (6/24 = 25 %); single aggregated moment.
- Store round-trip and old-file decode.

## Risks / Trade-offs

- 85 riddles are content work; they can ship short and be improved later
  without code changes to logic.
- Brand matching depends on brand text being present; Garmin/FatSecret
  foods often lack brands. The 859 fallback and `FoodProvenanceStore` help
  for scanned or OFF foods.

## Open Questions

1. Show undiscovered entry *names* (easier) or only riddles (more fun)?
   Default: riddles only, name revealed on discovery.
2. Which brands does the owner actually buy? The list is easy to extend.
