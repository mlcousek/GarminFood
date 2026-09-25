# Open Food Facts product-by-barcode route

Probed **2026-09-25** for add-standalone-mode task 3.5. This is **not a Garmin
route**. It is Open Food Facts' public, read-only product API. It needs no
auth, and the probe made no writes of any kind. The app uses it only in
standalone mode, as step 2 of the barcode chain (design D5, spec "Barcodes
resolve without Garmin"):

1. your own custom foods, by their barcode;
2. the offline Czech index;
3. **this route**;
4. otherwise the custom-food editor, with the barcode filled in.

Implemented by `OpenFoodFactsClient.product(barcode:)` and
`StandaloneBarcodeResolution` (FoodLogCore).

## Request

```
GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json
    ?fields=code,product_name,product_name_cs,product_name_en,generic_name,generic_name_cs,lang,brands,quantity,serving_size,serving_quantity,nutriments
User-Agent: GarminFood/1.0 (personal app)
```

`fields=` is optional. With it, the found-product body shrank from 12.4 kB to
about 1.2 kB, and the shape of the fields it returns stayed the same.

## Observed responses

| Barcode | HTTP | Body |
|---|---|---|
| `8594003963391` (Billa tvaroh odtučněný) | **200** | `{"code", "product": {...}, "status": 1, "status_verbose": "product found"}` |
| `8594003849149` (valid EAN-13, not in OFF) | **404** | `{"code":"8594003849149","status":0,"status_verbose":"product not found"}` |
| `0000000000000` | **200** | `{"code":"00000000","status":0,"status_verbose":"no code or invalid code"}` |

The same results came back with and without `fields=`.

**How to read the result.** Look at the `status` field (1 means found). The
HTTP code alone is not enough: an unknown code returns 404 with a JSON body,
and an invalid code returns 200 with `status: 0`. The client treats a 404,
`status != 1` or a missing `product` as "no product" (`nil`). It treats any
other non-2xx code, or a body it can't decode, as an error. The screen shows
the error with a retry and a "create a custom food" option. It never quietly
reads an error as "no product".

## `product` payload (found case, trimmed to the fields the app reads)

```json
{
  "code": "8594003963391",
  "product_name": "Tvaroh odtučněný",
  "product_name_cs": "Tvaroh odtučněný",
  "generic_name": "",
  "brands": "Billa, Polabské Mlékárny",
  "lang": "cs",
  "quantity": "250 g",
  "product_quantity": 250,
  "product_quantity_unit": "g",
  "serving_size": "250.0g",
  "serving_quantity": 250,
  "nutrition_data_per": "100g",
  "nutriments": {
    "energy-kcal": 67, "energy-kcal_100g": 67, "energy-kcal_serving": 168, "energy-kcal_unit": "kcal",
    "energy_100g": 280, "energy_serving": 700, "energy_unit": "kJ",
    "carbohydrates_100g": 4, "carbohydrates_serving": 10,
    "proteins_100g": 12, "proteins_serving": 30,
    "fat_100g": 0.5, "fat_serving": 1.25,
    "saturated-fat_100g": 0.200000002980232, "saturated-fat_serving": 0.5,
    "sugars_100g": 4, "sugars_serving": 10
  }
}
```

Notes on the shape:

- **Names.** On this Czech product, `product_name` is the Czech name
  (`lang: "cs"`), and `product_name_cs` is present too. Search-a-licious hits
  often don't include `product_name_cs`, so the client uses the same
  name-preference rule as search (`OpenFoodFactsClient.names(for:)`).
- **Brands** is a comma-separated **string** on this route. Search-a-licious
  sends an array. The decoder accepts both.
- **Nutriments** come as `*_100g` (grams per 100 g, kcal for
  `energy-kcal_100g`), plus `*_serving` when the product declares a serving.
  `serving_size` is free text (`"250.0g"`) and `serving_quantity` is a
  number in grams or ml. The app maps only the per-100 g values, into one
  implicit `100g` serving. This is the same `Food` shape search produces, so
  a scanned product and a searched one are the same food (same id: the
  code). The serving picker's grams entry covers package sizes. The
  `*_serving` values and `serving_quantity` are recorded here but not used
  yet.
- Keys missing from the product may be absent, or sent as `""` (known OFF
  behaviour). The decoder reads every number leniently, as for search.
