## Why

The owner asked for achievements *"like things from real word"* and chose
**food collections** — a "food Pokédex". Collecting is one of the most
durable game loops there is, and food is naturally collectable: the Czech
classics (svíčková, guláš, smažený sýr, utopenci…), dishes from around the
world, fermented foods, a rainbow of fruit and veg colours, and Czech brands
from the shop shelf. Unlike a streak, a collection rewards *variety* and
curiosity, and a silhouette with a riddle is an invitation to try something.

## What Changes

- **Five collections** with ~85 entries: Czech Classics (24), Around the
  World (22), Fermented Friends (11), Rainbow (6 colours), Czech Brands (22).
- Each entry is matched by collection food tags (this change's own
  tag-rule file) or, for brands, by brand name; the first logged match
  **discovers** the entry permanently, recording when and with which food.
- Undiscovered entries show as a **silhouette with a riddle hint**
  ("Cream sauce, cranberries, a slice of lemon — Sunday at grandma's").
- Rewards: 5 XP per discovery; badges at 25 %, 50 % and 100 % of each
  collection; "Rainbow Day" (all six colours in one day); "Brand Explorer"
  tiers for distinct Czech brands (including unknown brands detected only by
  an 859 barcode); an overall "Food Pokédex" badge at 50 % and 100 %.
- A Collections screen on the Progress tab.

## Capabilities

### New Capabilities

- `food-collections` - permanent, discoverable food collections with
  silhouettes, riddle hints and completion badges.

### Modified Capabilities

(none)

## Non-goals

- Photos or artwork per entry (SF Symbols + emoji only; no art pipeline).
- User-defined collections.
- Nutrition judgement — collections celebrate variety, not "healthy" food
  (smažený sýr is a proud member of Czech Classics).
- Rewriting the foundation's core tagger rules.

## Impact

Owned files only: `Gamification/Sources/Gamification/Features/Collections/*`,
`FoodLogCore/Sources/FoodLogCore/Signals/FoodTagRules+Collections.swift`
(stub filled), `FoodLogCore/Sources/FoodLogCore/Signals/FoodTag+Collections.swift`
(new), `GarminFood/Progress/Slots/CollectionsSlotView.swift`,
`GarminFood/Progress/Collections/*`, and tests.

**Depends on**: `add-gamification-signals` (tagger rule-set slot, core
colour/cuisine/fermented/czechBrand tags, `CzechBrands`,
`FoodProvenanceStore` barcodes, feature seam, `RewardLedger`).

**Unblocks**: nothing.
