## 1. Tags (FoodLogCore)

- [x] 1.1 `Signals/FoodTag+Collections.swift`: `dish.*` and `brand.*` tag constants for every entry.
- [x] 1.2 Fill `Signals/FoodTagRules+Collections.swift`: phrases/exclusions per dish; `anyBrands` per brand.
- [x] 1.3 `CollectionsTaggerTests`: ≥ 1 positive per entry, negatives for risky ones (design D6).

## 2. Catalog and evaluation (Gamification)

- [x] 2.1 `Features/Collections/FoodCollectionCatalog.swift`: 5 collections, ~85 entries with name, symbol/emoji, riddle hint.
- [x] 2.2 `CollectionsEvaluator`: discovery from snapshot (incl. vepřo-knedlo-zelo by parts), rainbow days, Brand Explorer counting with 859 barcodes.
- [x] 2.3 `CollectionsStore` (Optional fields, caps, quarantine helpers).
- [x] 2.4 Badges (design D4) with `featureId: "collections"` and rarity overrides.
- [x] 2.5 Replace the stub `FoodCollectionsFeature`: grants `collections.found.<id>`, badges, one aggregated moment, summary; expose `overview()` for the UI.
- [x] 2.6 Tests: back-fill, permanence, parts rule same-day only, thresholds, brand counting + cap, single moment, store decode.

## 3. UI (thin)

- [x] 3.1 `Progress/Slots/CollectionsSlotView.swift`: total + five mini rings.
- [x] 3.2 `Progress/Collections/CollectionsView.swift`: sections, discovered tiles, silhouettes with hints, detail sheet; VoiceOver, Dynamic Type, dark mode.

## 4. Verify

- [x] 4.1 `openspec validate add-food-collections --strict` passes.
- [x] 4.2 CI green (`swift test` FoodLogCore + Gamification; app + widget build). *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.3 On-device check: first launch shows a single back-fill moment; the Collections screen lists discoveries from recent logs; logging a new Czech-brand product discovers its brand.
