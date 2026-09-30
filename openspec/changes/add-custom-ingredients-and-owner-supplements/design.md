## Context

`add-supplements` modelled ingredients as an open identifier
(`IngredientID`, any string) with an optional `customName` on each label
row, but its only editor listed the 15 evidence-card ingredients in a
`Picker`. The owner could not enter a real label. This change adds the
missing UI path and data, plus the owner's ten products as catalog
entries.

## Goals / Non-Goals

**Goals:** any ingredient can be entered, in any common unit, with its
form; custom ingredients persist and are searchable; the owner's products
are one tap away with their verified labels.

**Non-Goals:** see the proposal. In particular no evidence card, limit or
health text is written for ingredients that have none.

## Decisions

### D1. Custom ingredients live in the plan file, not a new store

`SupplementPlan.customIngredients: [CustomIngredient]?`, written by
`SupplementPlanStore.saveCustomIngredient`. Alternatives: a separate
`custom-ingredients.json` store. Rejected: it would need its own
AppServices/AppEnvironment wiring, a StoreCatalog/backup entry and a
fixture, and could be quarantined independently of the products that
reference it. The plan file already has the store contract
(fix-silent-store-wipe: quarantine, unreadable-file latch, load before
write) and is in every backup. The field is optional and decoded per
entry (`LossyCustomIngredient`): a damaged entry is dropped, never the
plan. A plan without custom ingredients encodes exactly as before
(tested).

An older build reading a newer plan ignores the unknown key and would drop
the list on its next write; the product rows keep their `customName` and
unit, so labels and totals still read correctly. Acceptable for a
single-owner app, so the store's schema version stays 1.

### D2. The id carries the unit: `custom:<unit>:<uuid>`

`IngredientID.canonicalUnit` is a property of the id alone -- totals,
limits and warnings call it without a plan at hand. Encoding the unit in
the id makes a custom ingredient total in its own unit everywhere with no
lookup: 2 × 2.5 ml = 5 ml, and a row entered in g against an ml
ingredient is reported "not included" rather than converted (tested).
Rows of a custom ingredient in IU or ml offer only that unit; mass units
still convert among g/mg/µg. Any other id without a card keeps counting in
mg, as before. Rows also copy the name into `customName`, so a label line
reads right from the product alone.

A new name that matches an existing custom ingredient (case and
diacritics folded with `SearchText.fold`) reuses it and merges the typed
form -- the picker also hides "Add" when the exact name exists.

### D3. Two tiers of known ingredient

`IngredientID.builtIn` (with evidence cards) is unchanged, so
EvidenceCatalogTests' invariants still hold. `IngredientCatalog.extra` adds
13 label-only ingredients with en + cs names and search aliases, counted
in mg; `EvidenceCatalog.name(of:)` falls back to them. `LabelScore`
already reports "no reference range" for an ingredient without a card.
Suggested forms are label text (untranslated), like the magnesium forms
before.

### D4. Branded catalog as bundled JSON

`Resources/branded-supplements.json` decoded into the existing
`CatalogProduct` with a new optional `label: CatalogLabel` (brand,
product name as printed, barcode, pack servings/count, source URL(s),
quality facts, bilingual label details, `verifiedOn`). JSON rather than
Swift literals because these are data rows with provenance, reviewable
against the source table and addable without code. Decoding is strict per
entry -- a malformed entry fails `BrandedSupplementCatalogTests` -- but at
run time a broken file yields an empty list and a DiagnosticsLog error,
never a crash. `SupplementCatalog.all` stays the generic list (its
"every ingredient has a card" invariant), `branded` is separate, and
`product(id:)` finds both.

`CatalogProduct.Serving` gains `.measure(grams: Double)` (4.5 g scoop) and
`.sachet(grams: Double)`; the existing `.scoop(grams: Int)` key is kept
untouched.

`quality` is a list of typed facts (`labTested`, `dshsCologneTested`,
`szuSafetyCertificate`, `vegan`, `liposomal`, `triglycerideForm`,
`oxidationSpec`, `brandedRawMaterial`, `registeredMedicine`) worded in
the app's languages. They are statements of the maker or seller, never
the app's certification: the manual certification toggles of
add-supplements D7 are unchanged and not pre-ticked. "Tested at DSHS
Köln" is worded as the maker's statement and is not a Kölner Liste
listing.

### D5. Evidence: what was read, and how

Every page was downloaded on 2026-09-30 and its composition table,
"Složení" text, "Doplňkové parametry" (EAN, vegan tag, patented raw
material) and lab/certificate section read directly (not through a
summariser). Findings worth keeping:

- brainmarket.cz pages 1-7: HTTP 200. Composition tables per serving as in
  the proposal table. The DSHS Köln paragraph appears on pages 1, 2, 3 and
  7 only; lab-protocol links (heavy metals, microbiology) and an SZÚ
  certificate link on pages 1, 5, 6, 7; page 2 and 3 link one lab protocol.
- Page 2 is internally inconsistent: the table says LipoComplex 795 mg with
  235 mg phospholipids, the ingredient line says 735 mg. Only the
  consistent actives (vitamin C 500 mg, rosehip 30 mg, bioflavonoids
  30 mg) are stored.
- Page 3 tags the product "Vegan" but states D3 from lanolin; vegan is not
  stored.
- Page 4 (omega-3): no IFOS, Friend of the Sea or MSC statement anywhere;
  TOTOX max 10, peroxide value max 2, VivoMega®, rTG form, Norway.
- action.com: HTTP 403 to both curl and the fetch tool. The maker's page
  (accelerate-nutrition.com) states 3 g per daily serving = 3000 mg
  creatine monohydrate, 100 % creatine monohydrate; vsecochces.cz states
  300 g, about 100 portions, product no. 3218530, EAN 8719979204525.
- grizly.cz: composition per 4.5 g scoop; the maker's page gives the same
  amounts and names vitamin C as NUTRA-C™ (calcium/magnesium ascorbate),
  where grizly says L-ascorbic acid -- the maker's wording is stored. No
  servings-per-pack figure: left empty.
- lekarnaave.cz: product page has no composition; the SÚKL open-data API
  (HTTP 200) confirms light basic magnesium carbonate + light magnesium
  oxide, 365 mg, 30 sachets, prescription-only; the package leaflet
  (lekarna.cz) gives 670 mg carbonate (169 mg Mg) + 342 mg oxide (196 mg
  Mg) per 6.1 g sachet, 194.8 mg potassium and 238.93 mg sodium per dose.
  A search-engine summary claimed a 5.6 g sachet; the leaflet read directly
  says 6.1 g, which is stored.

## Risks / Trade-offs

- [Labels change] → every entry carries `verifiedOn` and its source, shown
  in the catalog ("Label from brainmarket.cz, checked 30 Sept 2026"), and
  the editor lets the user change every amount.
- [Magnosolv is a medicine, 365 mg Mg is over the EU supplemental 250 mg
  limit] → it is labelled a registered medicine; the existing over-limit
  warning is informational and the user can raise their own limit.
- [No local compiler] → the logic is in FoodLogCore with package tests;
  the app changes are thin views over it. CI is the compile signal.
