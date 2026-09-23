# Czech offline food index builder

Builds the slim, weekly-refreshed copy of Czech Open Food Facts products that
the iOS app downloads and searches locally
(`openspec/changes/add-offline-czech-food-index`).

```sh
node tools/build-czech-food-index/build.mjs --out dist/food-index
node --test tools/build-czech-food-index/transform.test.mjs
```

No npm dependencies (Node 20+: built-in `fetch`, `zlib`, `crypto`).

## Output

- `czech-food-index-v1.json.gz` — gzipped `{ "schema": 1, "products": [...] }`,
  sorted by barcode, short keys (see `transform.mjs` header).
- `manifest.json` — `version`, `count`, `sha256` and `bytes` of the `.gz`,
  source and licence. The app compares `sha256` with what it has installed
  and verifies it after download.

Both are published by `.github/workflows/food-index.yml` to the rolling
`food-index` GitHub Release. The app reads
`https://github.com/mlcousek/GarminFood/releases/download/food-index/manifest.json`.

## Source

Search-a-licious (`search.openfoodfacts.org`), `countries_tags:"en:czech-republic"`,
partitioned by barcode prefix to stay under its 10,000-result paging window.
Anonymous and read-only. Products with no name or no kcal are dropped.

## Licence

Data © Open Food Facts contributors, under the
[Open Database License (ODbL) 1.0](https://opendatacommons.org/licenses/odbl/1-0/).
The derived index is published under ODbL 1.0 as well.
