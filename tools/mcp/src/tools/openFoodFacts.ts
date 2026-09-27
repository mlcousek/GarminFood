// openFoodFacts.ts -- food_lookupBarcode, the PC's stand-in for scanning.
//
// Why it exists: the camera scan is phone-only (design, not offered), but a
// barcode typed on the PC can still be looked up. Garmin's own barcode
// route 404s (registry: foodSearchByBarcode), so this uses Open Food Facts'
// public, read-only product route, the same one the app uses in standalone
// mode (docs/openfoodfacts-product-route.md, probed 2026-09-25): no auth,
// and "not found" is read from the body's `status`, not the HTTP code (an
// unknown code is a 404 with a JSON body; an invalid one a 200 with
// status 0). Any other failure is an error, never a quiet "no product".
// Not a Garmin route, so it bypasses the registry and GarminClient.

import { z } from 'zod';
import { defineTool } from './types.js';
import { num, obj, round, str } from './shape.js';

export const OFF_PRODUCT_URL = 'https://world.openfoodfacts.org/api/v2/product/';
const OFF_FIELDS =
  'code,product_name,product_name_cs,product_name_en,generic_name,generic_name_cs,lang,brands,quantity,serving_size,serving_quantity,nutriments';
export const OFF_USER_AGENT = 'GarminFood/1.0 (personal app)';

export const foodLookupBarcode = defineTool({
  name: 'food_lookupBarcode',
  title: 'Look up a barcode (Open Food Facts)',
  summary:
    'Look up a product by its EAN/UPC barcode in Open Food Facts (not Garmin): name, brand, package size and ' +
    'nutrition per 100 g. found: false means Open Food Facts does not know the code. To log the product, find a ' +
    'matching Garmin food with food_search.',
  acts: 'Open Food Facts public API, read-only, answered immediately. Not Garmin, not the phone.',
  garminOperations: [],
  otherRoute: `GET ${OFF_PRODUCT_URL}{barcode}.json (docs/openfoodfacts-product-route.md, probed 2026-09-25)`,
  inputShape: {
    barcode: z.string().regex(/^\d{8,14}$/, 'must be 8-14 digits (EAN-8, UPC-A, EAN-13, GTIN-14)').describe('The digits under the barcode.'),
  },
  async run(args, ctx) {
    const url = `${OFF_PRODUCT_URL}${args.barcode}.json?fields=${OFF_FIELDS}`;
    let response;
    try {
      response = await ctx.http(url, { method: 'GET', headers: { 'User-Agent': OFF_USER_AGENT, Accept: 'application/json' } });
    } catch (error) {
      throw new Error(`Open Food Facts product route failed: network error -- ${error instanceof Error ? error.message : String(error)}`);
    }
    const text = await response.text();
    if (response.status !== 404 && (response.status < 200 || response.status >= 300)) {
      throw new Error(`Open Food Facts product route failed: HTTP ${response.status} -- ${text.slice(0, 200)}`);
    }
    let body: Record<string, unknown> | null;
    try {
      body = obj(JSON.parse(text));
    } catch {
      throw new Error(`Open Food Facts product route returned something that is not JSON (HTTP ${response.status}).`);
    }
    const product = obj(body?.product);
    if (response.status === 404 || num(body?.status) !== 1 || !product) {
      return { barcode: args.barcode, found: false, reason: str(body?.status_verbose) ?? 'product not found' };
    }
    const n = obj(product.nutriments);
    const per100 = (key: string) => round(num(n?.[`${key}_100g`]));
    return {
      barcode: args.barcode,
      found: true,
      name:
        str(product.product_name_cs) ?? str(product.product_name) ?? str(product.product_name_en) ?? str(product.generic_name_cs) ?? str(product.generic_name),
      brands: str(product.brands),
      quantity: str(product.quantity),
      servingSize: str(product.serving_size),
      per100g: {
        calories: round(num(n?.['energy-kcal_100g']), 0),
        protein: per100('proteins'),
        carbs: per100('carbohydrates'),
        sugar: per100('sugars'),
        fat: per100('fat'),
        saturatedFat: per100('saturated-fat'),
        fiber: per100('fiber'),
        salt: per100('salt'),
      },
    };
  },
});
