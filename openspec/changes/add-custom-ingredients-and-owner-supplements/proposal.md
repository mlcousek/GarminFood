## Why

The owner reported: "I wanted to track supplements and I cannot create my
own, because I cannot add a custom ingredient and it was not in the
suggestions."

Root cause: the product editor's ingredient row
(`ios/GarminFood/Supplements/SupplementProductEditorView.swift`,
`IngredientRowEditor`, lines 355-359 at 4cea263) was a `Picker` over
`IngredientID.builtIn` -- the 15 ingredients that have an evidence card --
and "Add ingredient" (line 215) always appended magnesium. The data model
already allowed any ingredient id and a `customName`
(`SupplementModels.swift`, `IngredientAmount`), but no screen could
produce one. Units were limited to g/mg/µg (IU only for vitamin D, no ml)
and a form could be entered only for magnesium. A real label -- copper,
turmeric, MSM, glucosamine, a tincture in ml -- could not be entered at
all.

The owner also has ten products in the cupboard and wants to add them
without retyping every label.

## What Changes

- **Custom ingredients.** The ingredient row opens a searchable picker
  (the user's own ingredients, then every known one, matched in English
  and Czech with diacritics ignored). When nothing has the typed name,
  "Add "…" as your own ingredient" creates one: name, unit (mg, µg, g, IU
  or ml) and an optional form ("citrate", "malate", "bisglycinate",
  "cholecalciferol", "MK-7"). It is saved locally at once, in the plan
  file with the same store contract as all supplement data, and the search
  finds it afterwards. A name that exists is reused, never duplicated.
- **Units and forms for every row.** ml is a unit; a custom ingredient
  totals in its own unit (ml is never converted to a mass). Every row has
  a free "Form (optional)" field with suggestions per ingredient (the
  magnesium list as before, zinc, selenium, copper, D3, K2, B6, B12, C,
  iron, omega-3...), and forms typed for a custom ingredient are offered
  next time.
- **Known ingredients without a card.** 13 ingredients printed on the
  owner's labels get a name (en + cs) and search aliases, no evidence
  card: turmeric, rosehip extract, citrus bioflavonoids, tart cherry,
  valerian root, GABA, L-theanine, green tea extract, MSM, glucosamine,
  chondroitin, collagen type I and II (copper and calcium reuse existing
  names). No limit, range or health text is invented for them.
- **Branded products in the catalog.** A new "Brand products" section in
  the catalog with the owner's ten products, each with brand, name as on
  the pack, form, serving, per-serving actives with their chemical form,
  pack size, barcode where the page states it, the source URL, the
  quality facts the maker or seller states, and `verifiedOn: 2026-09-30`.
  Data is a bundled JSON file (`branded-supplements.json`).
- Custom ingredient names are shown by name (not id) in totals, limits,
  warnings and label-score findings.

### The ten products and their sources

All read on 2026-09-30. "Not stated" means the source page says nothing
about it, and the catalog leaves it empty.

| # | Product | Actives per serving | Serving / pack | Quality facts stated | Source |
|---|---------|---------------------|----------------|----------------------|--------|
| 1 | BrainMax Zinc Complex® | zinc 15 mg (bisglycinate), copper 1 mg (citrate), selenium 100 µg (L-selenomethionine), organic turmeric 420 mg | 1 capsule / 100 capsules = 100 servings | vegan; lab protocols published (heavy metals, microbiology, PAH); SZÚ safety certificate; tested at DSHS Köln per WADA list (maker's statement) | https://www.brainmarket.cz/brainmax-zinc-complex/ |
| 2 | BrainMax Liposomal Vitamin C® UPGRADE | vitamin C 500 mg (liposomal, LipoComplex®), rosehip extract 5:1 30 mg, citrus bioflavonoids 30 mg | 1 capsule / 60 = 60 | vegan; liposomal; LipoComplex®; lab protocol published; DSHS Köln (maker's statement). SZÚ not stated | https://www.brainmarket.cz/brainmax-liposomal-vitamin-c--500-mg--60-rostlinnych-kapsli/ |
| 3 | BrainMax Vitamin D3 & K2® | D3 4000 IU = 100 µg (cholecalciferol from lanolin), K2 150 µg (all-trans MK-7, K2VITAL®DELTA), organic turmeric 435 mg | 1 capsule / 100 = 100 | K2VITAL®DELTA; lab protocol published; DSHS Köln (maker's statement). The shop tags it "Vegan" while the label says D3 from lanolin -- vegan left out | https://www.brainmarket.cz/brainmax-vitamin-d3-k2-mk7-100-rostlinnych-kapsli/ |
| 4 | BrainMax® Omega-3 HIGH EPA Fish Oil | EPA 1200 mg + DHA 400 mg (stored as EPA+DHA 1600 mg, re-esterified triglyceride) from 2000 mg concentrate | 2 softgels / 60 softgels = 30 servings | rTG form; TOTOX ≤ 10; VivoMega® (Norway). IFOS / Friend of the Sea: not stated | https://www.brainmarket.cz/brainmax-omega-3-high-epa-fish-oil--60-softgel-kapsli/ |
| 5 | BrainMax Energy Magnesium® | magnesium 175.5 mg (Mg20+: 90 % malate, 10 % oxide), vitamin B6 1.4 mg (P5P) | 1 capsule (label: 1-2) / 200 = 200 | vegan; Nutrascience Minerals Mg20+; lab protocols; SZÚ certificate. DSHS not stated | https://www.brainmarket.cz/brainmax-energy-magnesium-1000-mg-200-kapsli-magnesium-malat/ |
| 6 | BrainMax Sleep Magnesium® | magnesium 250 mg (bisglycinate MagChel®), tart cherry juice 100 mg, valerian root 100 mg, GABA 80 mg, decaf green tea extract 80 mg, L-theanine 50 mg, B6 2.8 mg (P5P) | 2 capsules / 100 = 50 | vegan; MagChel®; lab protocols; SZÚ certificate. DSHS not stated | https://www.brainmarket.cz/brainmax-sleep-magnesium-250-mg-100-kapsli/ |
| 7 | Performance Magnesium® (BrainMax) | magnesium 200 mg (MagChel® Mg 20+: 80 % bisglycinate, 20 % oxide), B6 1.4 mg (P5P) | 1 capsule (label: 1-2) / 100 = 100. The URL says "tbl", the page says capsules | vegan; MagChel®; lab protocols; SZÚ certificate; DSHS Köln (maker's statement) | https://www.brainmarket.cz/performance-magnesium-1000-mg-100-tbl/ |
| 8 | Kreatin monohydrát Accelerate | creatine monohydrate 3 g | 3 g / 300 g ≈ 100 servings | none stated | action.com returned HTTP 403; used https://accelerate-nutrition.com/fr-fr/products/creatine-monohydraat (maker) and https://www.vsecochces.cz/kreatin-monohydrat-accelerate (300 g, ~100 portions, EAN) |
| 9 | ALAVIS™ MAXIMA Triple Blend Extra Silný | MSM 1958 mg (Lignisul®), glucosamine sulfate 2KCl 1565 mg, chondroitin sulfate 652 mg, collagen type I 15 mg (COLLYSS™), collagen type II 22.5 mg (CARTIDYSS™), vitamin C 19.3 mg | 1 scoop 4.5 g / 700 g (servings per pack not stated; maker: "pack for 5 months") | branded raw materials only; GMP, testing: not stated. Contains fish and crustaceans | https://www.grizly.cz/alavis-maxima-triple-blend-extra-silny-700-g, maker https://www.alavis-maxima.cz/domu/20-triple-blend-extra-silny-8594191410288.html |
| 10 | Magnosolv 365 mg granules for oral solution | magnesium 365 mg (169 mg from light magnesium carbonate + 196 mg from light magnesium oxide; forms citrate in water); from excipients potassium 194.8 mg, sodium 238.93 mg | 1 sachet 6.1 g / 30 sachets | registered medicinal product, SÚKL 0286435, prescription (Rx) -- not a food supplement | https://www.lekarnaave.cz/pp-detail/5547899/magnosolv-365mg-por-gra-sol-scc-30 (no composition on it), leaflet https://www.lekarna.cz/magnosolv-365mg-por-gra-sol-scc-30/pribalovy-letak/, SÚKL https://prehledy.sukl.cz/prehledy/v1/dlp/0286435 |

## Non-goals

- Evidence cards, limits or reference ranges for the new known
  ingredients -- a card needs cited limits (add-supplements D8); owned by a
  later evidence change if the owner wants them.
- Matching a scanned barcode against the branded catalog offline (the
  entries carry EANs, so a follow-up can do it) -- `polish-barcode-scanning`
  territory.
- Renaming or deleting custom ingredients from a management screen.
- Any Garmin interaction: supplements stay local only (add-supplements).
- Food targets, fasting, rewards (`GarminFood-wt-nutrition` work) and
  custom-food serving validation (review work) are untouched.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `supplement-tracking`: custom ingredients, units incl. ml, forms on any
  row, and branded catalog products.

## Impact

- **Depends on**: `add-supplements` (models, plan store, editor, catalog).
- **Unblocks**: offline barcode match against the branded catalog; more
  branded products added as data only.
- Code: FoodLogCore `Supplements/` (new `CustomIngredients.swift`,
  `IngredientCatalog.swift`, `SupplementCatalog+Branded.swift`; changes in
  `SupplementModels.swift`, `SupplementCatalog.swift`,
  `SupplementPlanStore.swift`, `EvidenceCatalog.swift`), a bundled
  `Resources/branded-supplements.json`, en + cs package strings; app
  `Supplements/` (new `SupplementIngredientPicker.swift`; editor, stack
  picker, controller, limits/warnings/label-score name display) and 18
  `Localizable.xcstrings` keys.
- Data: `supplement-plan.json` gains an optional `customIngredients`
  array. Files without it decode as before; a plan without custom
  ingredients encodes byte-for-byte as before.
- No new store file, no Garmin route, no network.
