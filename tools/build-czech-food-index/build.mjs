#!/usr/bin/env node
/**
 * build.mjs — builds the Czech offline food index the iOS app downloads
 * (openspec/changes/add-offline-czech-food-index). Run weekly by
 * .github/workflows/food-index.yml; safe to run locally too. Read-only and
 * anonymous against Open Food Facts; never touches Garmin.
 *
 * Data source (design.md spike, 2026-09-23): Search-a-licious
 * (`GET https://search.openfoodfacts.org/search`), filtered to
 * `countries_tags:"en:czech-republic"`. It answers in ~0.3 s but refuses to
 * page past 10,000 results per query, so the Czech subset is partitioned
 * by barcode prefix (`code:85*`, …), splitting a prefix further whenever
 * its count isn't exact or reaches the window. The legacy
 * /api/v2/search endpoint was rejected: it 503s/401s on deep pages.
 *
 * Output (in --out, default ./dist/food-index):
 *   czech-food-index-v1.json.gz  gzipped `{ schema, products: [...] }`
 *   manifest.json                version, count, sha256 + size of the .gz
 *
 * Usage:
 *   node tools/build-czech-food-index/build.mjs [--out DIR] [--max-pages N] [--drop-optional]
 *     --max-pages N    stop after N result pages (a quick size spike)
 *     --drop-optional  omit fiber/sugar/salt (design.md D1 trimming, if > 5 MB)
 */

import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { gzipSync, constants as zlibConstants } from 'node:zlib';
import { buildIndex, manifestFor, INDEX_FILE_NAME, MANIFEST_FILE_NAME } from './transform.mjs';

const BASE_URL = 'https://search.openfoodfacts.org/search';
const COUNTRY_FILTER = 'countries_tags:"en:czech-republic"';
const FIELDS = 'code,product_name,product_name_cs,product_name_en,generic_name,generic_name_cs,lang,brands,quantity,nutriments';
const PAGE_SIZE = 100;
const WINDOW = 10_000;
const USER_AGENT = 'GarminFood offline index builder - https://github.com/mlcousek/GarminFood';
const REQUEST_TIMEOUT_MS = 30_000;
const MAX_ATTEMPTS = 5;
const POLITE_DELAY_MS = 200;

function parseArgs(argv) {
  const args = { out: 'dist/food-index', maxPages: Infinity, dropOptional: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--out') args.out = argv[++i];
    else if (arg === '--max-pages') args.maxPages = Number(argv[++i]);
    else if (arg === '--drop-optional') args.dropOptional = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return args;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJSON(params) {
  const url = `${BASE_URL}?${new URLSearchParams(params)}`;
  for (let attempt = 1; ; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(url, { headers: { 'User-Agent': USER_AGENT }, signal: controller.signal });
      if (response.ok) return await response.json();
      const retryable = response.status === 429 || response.status >= 500;
      if (!retryable || attempt >= MAX_ATTEMPTS) {
        throw new Error(`HTTP ${response.status} for ${url}: ${(await response.text()).slice(0, 300)}`);
      }
      const retryAfter = Number(response.headers.get('retry-after'));
      await sleep(Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : 1000 * 2 ** attempt);
    } catch (error) {
      if (attempt >= MAX_ATTEMPTS || String(error.message).startsWith('HTTP ')) throw error;
      await sleep(1000 * 2 ** attempt);
    } finally {
      clearTimeout(timer);
    }
  }
}

function queryFor(prefix) {
  return `${COUNTRY_FILTER} AND code:${prefix}*`;
}

async function countFor(prefix) {
  const json = await getJSON({ q: queryFor(prefix), page_size: '1', fields: 'code' });
  return { count: json.count ?? 0, exact: json.is_count_exact !== false };
}

/** Barcode prefixes whose result sets each fit inside Search-a-licious's paging window. */
async function planPartitions(prefixes = '0123456789'.split('')) {
  const plan = [];
  for (const prefix of prefixes) {
    const { count, exact } = await countFor(prefix);
    await sleep(POLITE_DELAY_MS);
    if (count === 0) continue;
    if (!exact || count >= WINDOW) {
      if (prefix.length >= 8) throw new Error(`Prefix ${prefix} still exceeds the window`);
      plan.push(...(await planPartitions('0123456789'.split('').map((d) => prefix + d))));
    } else {
      plan.push({ prefix, count });
    }
  }
  return plan;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const started = Date.now();
  const plan = await planPartitions();
  const expected = plan.reduce((sum, p) => sum + p.count, 0);
  console.log(`Partitions: ${plan.map((p) => `${p.prefix}*=${p.count}`).join(' ')} (total ${expected})`);

  const products = [];
  let pages = 0;
  outer: for (const { prefix, count } of plan) {
    const pageCount = Math.ceil(count / PAGE_SIZE);
    for (let page = 1; page <= pageCount; page++) {
      if (pages >= args.maxPages) break outer;
      const json = await getJSON({ q: queryFor(prefix), page_size: String(PAGE_SIZE), page: String(page), fields: FIELDS });
      pages++;
      const hits = json.hits ?? [];
      products.push(...hits);
      if (hits.length < PAGE_SIZE) break;
      await sleep(POLITE_DELAY_MS);
    }
  }
  console.log(`Fetched ${products.length} products in ${pages} pages`);

  const index = buildIndex(products, { dropOptional: args.dropOptional });
  const raw = Buffer.from(JSON.stringify(index));
  // mtime 0 in the gzip header (Node's default), so identical input -> identical bytes.
  const gz = gzipSync(raw, { level: zlibConstants.Z_BEST_COMPRESSION });
  const sha256 = createHash('sha256').update(gz).digest('hex');
  const builtAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
  const manifest = manifestFor({ index, gzipBytes: gz.length, sha256, builtAt });

  const outDir = resolve(args.out);
  mkdirSync(outDir, { recursive: true });
  writeFileSync(join(outDir, INDEX_FILE_NAME), gz);
  writeFileSync(join(outDir, MANIFEST_FILE_NAME), JSON.stringify(manifest, null, 2) + '\n');

  const seconds = ((Date.now() - started) / 1000).toFixed(1);
  console.log(`Kept ${index.products.length} of ${products.length} (name + kcal); raw ${raw.length} B, gzipped ${gz.length} B; ${seconds}s`);
  console.log(`Wrote ${join(outDir, INDEX_FILE_NAME)} and ${MANIFEST_FILE_NAME}`);
  if (Number.isFinite(args.maxPages)) return;
  if (index.products.length < 1000) throw new Error(`Only ${index.products.length} products — refusing to publish a suspiciously small index`);
  if (gz.length > 5 * 1024 * 1024 && !args.dropOptional) console.warn('WARNING: index exceeds 5 MB; consider --drop-optional (design.md D1)');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
