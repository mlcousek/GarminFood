/**
 * transform.mjs — the pure half of the Czech offline food index builder
 * (openspec/changes/add-offline-czech-food-index, design.md D1).
 *
 * Why it's split from build.mjs: everything here is deterministic and
 * network-free, so it's covered by `node --test` (transform.test.mjs)
 * while build.mjs only does fetching, paging and file I/O.
 *
 * The record shape is the app's contract — FoodLogCore's
 * `OfflineFoodIndexFile` decodes exactly these short keys:
 *   c  barcode (string, required)      n  display name (required)
 *   e  alternate name (English/other)  b  brand(s)
 *   q  pack quantity ("250 g")         k  kcal / 100 g (required)
 *   cb carbs  p protein  f fat  s sugar  fi fiber  sa salt  (g / 100 g)
 * Absent values are omitted rather than written as null, to keep the file
 * small; the app treats a missing key as "unknown".
 *
 * Name choice mirrors OpenFoodFactsClient.names(for:) in the app, so a
 * product reads the same whether it came from live OFF or from this index.
 */

export const SCHEMA = 1;
export const INDEX_FILE_NAME = `czech-food-index-v${SCHEMA}.json.gz`;
export const MANIFEST_FILE_NAME = 'manifest.json';

const KJ_PER_KCAL = 4.184;

function clean(value) {
  if (Array.isArray(value)) value = value.map(clean).filter(Boolean).join(', ');
  if (typeof value !== 'string') return null;
  const trimmed = value.replace(/\s+/g, ' ').trim();
  return trimmed.length ? trimmed : null;
}

function number(value) {
  if (value === null || value === undefined || value === '') return null;
  const parsed = typeof value === 'number' ? value : Number(String(value).replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : null;
}

/** One decimal place is plenty for per-100 g label values, and it keeps the file small. */
export function round1(value) {
  return Math.round(value * 10) / 10;
}

/**
 * Display name plus one alternate, best first: product_name_cs, the main
 * product_name when the product's language is Czech, generic_name_cs, then
 * any product_name / product_name_en / generic_name.
 */
export function pickNames(product) {
  const czechMain = product.lang === 'cs' ? clean(product.product_name) : null;
  const ordered = [
    clean(product.product_name_cs),
    czechMain,
    clean(product.generic_name_cs),
    clean(product.product_name),
    clean(product.product_name_en),
    clean(product.generic_name),
  ].filter(Boolean);
  if (!ordered.length) return null;
  const display = ordered[0];
  const alternate = ordered.find((name) => name.toLowerCase() !== display.toLowerCase()) ?? null;
  return { display, alternate };
}

/** kcal per 100 g; derived from kJ when only kJ is on the label. */
export function kcalPer100g(nutriments) {
  if (!nutriments) return null;
  const kcal = number(nutriments['energy-kcal_100g']);
  if (kcal !== null) return kcal;
  const kj = number(nutriments['energy-kj_100g']) ?? (nutriments.energy_unit === 'kJ' ? number(nutriments['energy_100g']) : null);
  return kj === null ? null : kj / KJ_PER_KCAL;
}

/** An OFF product -> a compact index record, or null when it has no code, name or kcal. */
export function toRecord(product) {
  const code = clean(product?.code);
  if (!code || !/^\d{4,14}$/.test(code)) return null;
  const names = pickNames(product);
  if (!names) return null;
  const kcal = kcalPer100g(product.nutriments);
  if (kcal === null || kcal < 0 || kcal > 1000) return null;

  const n = product.nutriments ?? {};
  const record = { c: code, n: names.display };
  if (names.alternate) record.e = names.alternate;
  const brand = clean(product.brands);
  if (brand) record.b = brand;
  const quantity = clean(product.quantity);
  if (quantity) record.q = quantity;
  record.k = round1(kcal);
  const optional = [
    ['cb', 'carbohydrates_100g'],
    ['p', 'proteins_100g'],
    ['f', 'fat_100g'],
    ['s', 'sugars_100g'],
    ['fi', 'fiber_100g'],
    ['sa', 'salt_100g'],
  ];
  for (const [key, field] of optional) {
    const value = number(n[field]);
    if (value !== null && value >= 0 && value <= 100) record[key] = round1(value);
  }
  return record;
}

/**
 * Every usable product once (first occurrence of a code wins), sorted by
 * code so the same input always produces byte-identical output.
 */
export function buildIndex(products, { dropOptional = false } = {}) {
  const byCode = new Map();
  for (const product of products) {
    const record = toRecord(product);
    if (!record || byCode.has(record.c)) continue;
    if (dropOptional) {
      delete record.fi;
      delete record.s;
      delete record.sa;
    }
    byCode.set(record.c, record);
  }
  const records = [...byCode.values()].sort((a, b) => (a.c < b.c ? -1 : a.c > b.c ? 1 : 0));
  return { schema: SCHEMA, products: records };
}

export function manifestFor({ index, gzipBytes, sha256, builtAt }) {
  return {
    schema: SCHEMA,
    version: builtAt,
    builtAt,
    count: index.products.length,
    file: INDEX_FILE_NAME,
    sha256,
    bytes: gzipBytes,
    source: 'Open Food Facts (https://world.openfoodfacts.org), products sold in Czechia',
    license: 'ODbL-1.0',
    licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
  };
}
