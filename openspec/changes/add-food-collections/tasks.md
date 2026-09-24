## 1. Tags (FoodLogCore)

- [ ] 1.1 `Signals/FoodTag+Collections.swift`: `dish.*` and `brand.*` tag constants for every entry.
- [ ] 1.2 Fill `Signals/FoodTagRules+Collections.swift`: phrases/exclusions per dish; `anyBrands` per brand.
- [ ] 1.3 `CollectionsTaggerTests`: ≥ 1 positive per entry, negatives for risky ones (design D6).

## 2. Catalog and evaluation (Gamification)

- [ ] 2.1 `Features/Collections/FoodCollectionCatalog.swift`: 5 collections, ~85 entries with name, symbol/emoji, riddle hint.
- [ ] 2.2 `CollectionsEvaluator`: discovery from snapshot (incl. vepřo-knedlo-zelo by parts), rainbow days, Brand Explorer counting with 859 barcodes.
- [ ] 2.3 `CollectionsStore` (Optional fields, caps, quarantine helpers).
- [ ] 2.4 Badges (design D4) with `featureId: "collections"` and rarity overrides.
- [ ] 2.5 Replace the stub `FoodCollectionsFeature`: grants `collection.found.<id>`, badges, one aggregated moment, summary; expose `collections()` for the UI.
- [ ] 2.6 Tests: back-fill, permanence, parts rule same-day only, thresholds, brand counting + cap, single moment, store decode.

## 3. UI (thin)

- [ ] 3.1 `Progress/Slots/CollectionsSlotView.swift`: total + five mini rings.
- [ ] 3.2 `Progress/Collections/CollectionsView.swift`: sections, discovered tiles, silhouettes with hints, detail sheet; VoiceOver, Dynamic Type, dark mode.

## 4. Verify

- [ ] 4.1 `openspec validate add-food-collections --strict` passes.
- [ ] 4.2 CI green (`swift test` FoodLogCore + Gamification; app + widget build).
- [ ] 4.3 On-device check: first launch shows a single back-fill moment; the Collections screen lists discoveries from recent logs; logging a new Czech-brand product discovers its brand.
