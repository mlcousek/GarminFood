## 1. Custom ingredients (FoodLogCore)

- [x] 1.1 Confirm the root cause: `IngredientRowEditor` offered only `IngredientID.builtIn`; "Add ingredient" appended magnesium; units g/mg/µg (+IU for D); form only for magnesium.
- [x] 1.2 `CustomIngredient` (name, unit, forms), id `custom:<unit>:<uuid>`; `IngredientID.canonicalUnit` reads the unit from a custom id; `DoseUnit.ml` and `DoseUnit.pickable`.
- [x] 1.3 `SupplementPlan.customIngredients` (optional, lossy per entry); `SupplementPlanStore.saveCustomIngredient` reusing an existing name; `SupplementPlan.ingredientName`.
- [x] 1.4 `IngredientCatalog`: 13 label-only known ingredients (en + cs names, aliases), suggested forms; `IngredientSearch` (custom first, prefix before contains, folded en + cs); `EvidenceCatalog.name` falls back to the extras.
- [x] 1.5 Tests (`CustomIngredientTests`): relaunch + search, no duplicate names, ml totals, unconvertible unit, old plan files, lossy entries, unchanged encoding, search in both languages, names in both languages, suggested forms.

## 2. Custom ingredients (app)

- [x] 2.1 `SupplementIngredientPicker` + `CustomIngredientEditor` (name, unit mg/µg/g/IU/ml, optional form); "Add ingredient" opens the picker.
- [x] 2.2 Ingredient row: picker button, units per ingredient (custom IU/ml fixed), free form field with suggestions, forms remembered for custom ingredients.
- [x] 2.3 `SupplementsController`: custom ingredients, create, remember form, `ingredientName`; totals, limits, warnings and label-score findings show custom names.
- [x] 2.4 en + cs strings (18 `Localizable.xcstrings` keys, package `.strings`); `node tools/check-localizations.mjs --scan` passes.

## 3. Branded catalog

- [x] 3.1 Read each of the ten product pages (or the maker's page / leaflet / SÚKL where the shop page lacked data) on 2026-09-30; record sources and gaps in the proposal table and design D5.
- [x] 3.2 `Resources/branded-supplements.json`; `CatalogLabel`, `QualityFact`, `SupplementCatalog.branded`; `Serving.measure` / `.sachet`; `makeProduct` carries brand, barcode, pack servings.
- [x] 3.3 Catalog picker: "Brand products" section with quality facts, label details and source/date.
- [x] 3.4 Tests (`BrandedSupplementCatalogTests`): strict decode, ≥ 1 active with an amount and a convertible unit per entry, known ingredients only, https sources, `verifiedOn`, pinned label values, malformed entries rejected.

## 4. Verification

- [x] 4.1 `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`, `openspec validate add-custom-ingredients-and-owner-supplements --strict`.
- [ ] 4.2 CI: `swift test` for FoodLogCore and the app build (no local Swift toolchain).
- [ ] 4.3 Owner check on device: create a custom ingredient, find it again after a restart, add each of the ten products and compare with the packs.
