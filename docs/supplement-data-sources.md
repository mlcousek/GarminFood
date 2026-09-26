# Supplement data sources

`add-supplements` wave 5 (tasks 5.1, 5.2 and 5.4). Every call below was a
**read-only** GET made from Windows on **2026-09-26**, with the app's own
User-Agent (`GarminFood - iOS - Version 1.0 - https://github.com/mlcousek/GarminFood`).
The code that uses these routes is `SupplementBarcodeLookup.swift`
(FoodLogCore `Supplements/`). Its tests replay the shapes recorded here as
fixtures, with no live network.

## 5.1 Open Food Facts product route

`GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`

| Barcode | Market | Result |
|---|---|---|
| `4058172309250` (Mivolis Magnesium, dm) | Germany | **200**, `status: 1`. `product_name` "Magnesium", `brands` "Mivolis", `quantity` "82 g", `serving_size` "4.1 g". Nutrients are in `nutriments` as **grams**, both `*_100g` and `*_serving` (e.g. `magnesium_serving: 0.00769`, `magnesium_unit: "g"`). |
| `8595011107548` (Vitar Multivitamin 10 Vitamins + Guarana) | Czech Republic | **200**, `status: 1`. Name and brand are present, but there's **no `serving_size` and no vitamin nutrients**. The categories include `en:dietary-supplements`, `en:vitamin-supplements`, `cs:Šumivé tablety`. |
| `0733739020307` (NOW Sports Creatine Monohydrate) | US | **404**, `status: 0`, `"product found with a different product type: beauty"`. OFF files it under another product type, so the food route doesn't return it. |
| `8590000000001` (made up) | – | **404**. |

Search, for finding sample codes:

- `/api/v2/search?categories_tags_en=dietary-supplements&countries_tags_en=czech-republic`
  returned **503** "Page temporarily unavailable" twice. This is server
  load, as `OpenFoodFactsClient` already notes.
- The legacy `/cgi/search.pl` worked. On the Czech mirror, the top 15
  "dietary supplements" for the Czech Republic were almost all **protein
  bars and drinks** (Nutrend, Bombus, Nakd...). That confirms design D7's
  "polluted".

**Conclusion:** use OFF for the **name and brand** (and the serving text
when present) only. Don't take amounts from it: they're per 100 g, often
missing, and in grams. Most Czech supplements will need the label typed
in (design, Risks).

## 5.2 NIH ODS DSLD

| Call | Result |
|---|---|
| `GET https://api.ods.od.nih.gov/dsld/v9/search-filter?q=creatine%20monohydrate&size=5` | **200**. `stats.count` 4787. Each hit is `{ _id, _source: { fullName, brandName, allIngredients, netContents, productType, offMarket, physicalState, claims, events, userGroups, entryDate } }`. |
| `GET .../label/205180` | **200**. Top-level keys include `fullName`, `brandName`, `upcSku` ("7 33739 02030 7"), `servingSizes` (`[{minQuantity: 1.5, unit: "tsp", notes: "approx. 5 g"}]`), `ingredientRows` (`[{name: "Creatine Monohydrate", ingredientGroup: "Creatine", quantity: [{quantity: 5, unit: "Gram(s)"}]}]`) and `netContents`. |
| `search-filter?q="7 33739 02030 7"` (spaced UPC-A, quoted) | **200**, 3 hits. The first is label 205180, the scanned product. |
| `search-filter?q=733739020307` (unspaced) | **200**, **0 hits**. |

- **Rate limits:** no rate-limit or `Retry-After` headers were seen on any
  response. The 1,000 requests/hour figure for keyless use comes from
  third-party documentation and is still unconfirmed. A lookup makes at
  most 2 DSLD calls, and only after a scan.
- **Market:** US only. The app sends only 12-digit UPC-A codes, or
  EAN-13 codes starting with 0, converted to the spaced form.
- **Text search:** the search is a text match, so the app accepts a label
  only when its `upcSku` equals the scanned code.
- **Licence:** CC0.

## 5.4 Certification sites: terms of use

The app **links to each certifier's public search page** and shows the
certifier's name as plain text. It doesn't use logos, doesn't scrape, and
doesn't copy or repost their data. The user checks their batch on the
certifier's site and ticks a manual badge (design D7).

| Certifier | Where the terms are | What they say about this use |
|---|---|---|
| NSF Certified for Sport | nsfsport.com → "Privacy Policy/Copyright" (`/about-us/privacy.php`) | The materials "may not be copied for commercial use or distribution, nor ... reposted to other sites" without permission. Nothing restricts plain links. |
| Informed Sport (LGC) | sport.wetestyoutrust.com → "Privacy Policy & Legal" | Only personal-data terms. Nothing on linking, reuse or marks. |
| Kölner Liste | koelnerliste.com/en → Imprint | "The commercial use of our contents without permission ... is prohibited". The list itself sits behind a terms prompt. A link to its product database page is fine; its data isn't reused. |

Links the app opens:

- `https://www.nsfsport.com/certified-products/`
- `https://sport.wetestyoutrust.com/supplement-search`
- `https://www.koelnerliste.com/en/product-database`
