## ADDED Requirements

### Requirement: Any ingredient can be entered, including the user's own

The system SHALL let the user choose a product row's ingredient from a
searchable list of the user's own ingredients and every ingredient the app
knows, matching names in English and Czech with case and diacritics
ignored. When no listed ingredient has the typed name, the system SHALL
offer to create a custom ingredient with a name, a unit (mg, µg, g, IU or
ml) and an optional form. A created ingredient SHALL be stored on the
device at once and SHALL be found by later searches. Creating one with
the name of an existing custom ingredient SHALL reuse the existing one.

#### Scenario: Ingredient not in the suggestions

- **WHEN** the user searches "Ashwagandha", which is not listed, and adds it as their own ingredient in mg with form "KSM-66"
- **THEN** the row shows "Ashwagandha", and after the app restarts a search for "ashwa" lists "Ashwagandha" first under the user's ingredients

#### Scenario: Czech search in any language

- **WHEN** the user searches "hořčík" or "horcik"
- **THEN** magnesium is the first result

#### Scenario: Same name twice

- **WHEN** a custom "Ashwagandha" exists and the user creates "ashwagandha" again with form "Sensoril"
- **THEN** there is still one "Ashwagandha", now offering both forms

### Requirement: A custom ingredient is totalled in its own unit

The system SHALL total a custom ingredient in the unit it was created
with, SHALL NOT convert millilitres or IU of a custom ingredient to a
mass, and SHALL list an amount entered in an unconvertible unit as not
included rather than show a converted number.

#### Scenario: Tincture in ml

- **WHEN** a product has 2.5 ml of a custom "Echinacea tincture" (ml) per serving and 2 servings are taken
- **THEN** that day's total for it is 5 ml

#### Scenario: Wrong unit

- **WHEN** a row gives 1 g of that ml ingredient
- **THEN** the ingredient is listed as not included in the day's totals

### Requirement: Every ingredient row can state its form

The system SHALL let the user enter the chemical form printed on the label
for any ingredient row and SHALL suggest common forms for known
ingredients (for example citrate, malate and bisglycinate for magnesium,
cholecalciferol for vitamin D, MK-7 for vitamin K2) and the forms
previously entered for a custom ingredient.

#### Scenario: Zinc form

- **WHEN** the user adds zinc 15 mg, picks "bisglycinate" from the suggestions and saves
- **THEN** reopening the product shows zinc 15 mg with form "bisglycinate"

#### Scenario: Magnesium form still counts for the label score

- **WHEN** the user adds magnesium 200 mg and types the form "malate"
- **THEN** the label score does not report magnesium's form as missing

### Requirement: The catalog lists branded products with verified labels

The system SHALL list branded products in the catalog with brand, name as
printed, serving, per-serving active ingredients with their forms, pack
size where stated, the quality facts the maker or seller states, the
source web page and the date it was read. Choosing one SHALL propose a
product with that brand, barcode and servings per pack, editable before
saving. A quality fact SHALL be shown only when the source states it, and
SHALL NOT set any certification the user verifies themselves.

#### Scenario: Zinc Complex from the catalog

- **WHEN** the user adds "BrainMax Zinc Complex®" from the brand products
- **THEN** a product with zinc 15 mg (bisglycinate), copper 1 mg (citrate), selenium 100 µg (L-selenomethionine) and turmeric 420 mg per capsule, brand BrainMax, 100 servings per pack is proposed, and no certification toggle is on

#### Scenario: Unstated pack size

- **WHEN** the user adds "ALAVIS™ MAXIMA Triple Blend Extra Silný", whose page gives only the weight
- **THEN** servings per pack is left empty and the serving reads as a 4.5 g measure

#### Scenario: Medicine in the catalog

- **WHEN** the user views "Magnosolv 365 mg" in the catalog
- **THEN** it is marked as a registered medicine with its SÚKL code, and its 169 mg + 196 mg magnesium add up to 365 mg in the day's totals
