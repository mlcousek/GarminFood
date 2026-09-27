// tools.test.ts -- task 2.4: each read tool against shape-only fixtures
// served by FakeHttp. Checks the exact route requested and the reshaped
// answer (units, nulls for absent fields, calorie total source).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { foodGetDay, foodGetRange, foodRecent, foodSearch, goalsGet, waterGet, weightList } from '../src/tools/garminReads.js';
import { foodLookupBarcode } from '../src/tools/openFoodFacts.js';
import { serverStatus, PHONE_ONLY_ACTIONS } from '../src/tools/serverStatus.js';
import type { ToolDef } from '../src/tools/types.js';
import { fixture } from './fixtures.js';
import { FakeHttp } from './fakeHttp.js';
import { TODAY, testContext } from './context.js';

// Tools are called as the SDK would after validation: defaults applied.
const run = (def: ToolDef, args: Record<string, unknown>, http: FakeHttp, options = {}) =>
  def.run(args as never, testContext(http, options)) as Promise<Record<string, any>>;

test('food_getDay lists entries per meal and takes the total from dailyNutritionContent', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/2026-01-03', { body: fixture('garmin-daily-food-log.json') });
  const day = await run(foodGetDay, {}, http);
  assert.equal(http.requests[0]!.url, 'https://connectapi.garmin.com/nutrition-service/food/logs/2026-01-03');
  assert.equal(day.date, TODAY);
  assert.deepEqual(day.totals, { calories: 450, protein: 30, carbs: 50, fat: 15 });
  assert.equal(day.goals.adjustedCalories, 2200);
  assert.deepEqual(day.dayWindow, { start: '04:00:00', end: '17:00:00' });
  assert.equal(day.entryCount, 2);
  assert.deepEqual(day.meals.map((m: any) => m.meal), ['BREAKFAST', 'LUNCH', 'DINNER']);
  assert.deepEqual(day.meals[0].entries[0], {
    logId: 'aaaa0000000000000000000000000001',
    name: 'Example food A',
    brand: 'Example brand',
    foodId: '900001',
    source: 'FATSECRET',
    servingQty: 1.5,
    servingId: '800001',
    servingUnit: 'g',
    numberOfUnits: 100,
    calories: 300,
    protein: 20,
    carbs: 30,
    fat: 10,
    loggedAt: '2026-01-03T07:30:00.000',
    loggedBy: 'GCW',
  });
  assert.equal(day.meals[1].entries[0].brand, null);
  assert.deepEqual(day.meals[2].totals, { calories: null, protein: null, carbs: null, fat: null });
});

test('food_getDay reads the requested date', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/2025-12-31', { body: { mealDetails: [] } });
  const day = await run(foodGetDay, { date: '2025-12-31' }, http);
  assert.equal(day.date, '2025-12-31');
  assert.equal(day.entryCount, 0);
});

test('food_search pages with start = page x limit and normalises lenient numbers', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/search', { body: fixture('garmin-food-search.json') });
  const out = await run(foodSearch, { query: 'tvaroh', limit: 20, page: 1, regionCode: 'CZ' }, http);
  assert.equal(
    http.requests[0]!.url,
    'https://connectapi.garmin.com/nutrition-service/food/search?searchExpression=tvaroh&start=20&limit=20&regionCode=CZ',
  );
  assert.equal(out.moreDataAvailable, true);
  assert.equal(out.results.length, 2);
  assert.equal(out.results[0].servings.length, 2);
  assert.deepEqual(out.results[1], {
    foodId: '900002',
    name: 'Example food B',
    brand: null,
    source: 'GARMIN',
    foodType: null,
    servings: [{ servingId: '800002', unit: 'piece', numberOfUnits: 1, calories: 150, protein: 10, carbs: null, fat: 5, fiber: null, sugar: null }],
  });
});

test('food_getRange fills startDate/endDate separately and marks empty days', async () => {
  const http = new FakeHttp().on('/nutrition-service/calorie/summary/daily', { body: fixture('garmin-calorie-summary.json') });
  const out = await run(foodGetRange, { startDate: '2026-01-01', endDate: '2026-01-03' }, http);
  assert.equal(
    http.requests[0]!.url,
    'https://connectapi.garmin.com/nutrition-service/calorie/summary/daily?startDate=2026-01-01&endDate=2026-01-03',
  );
  assert.deepEqual(out.days.map((d: any) => d.logged), [true, false, true]);
  assert.equal(out.days[1].calories, null);
  assert.equal(out.loggedDays, 2);
  assert.equal(out.averageCaloriesOnLoggedDays, 2000);
});

test('food_getRange refuses more than 31 days or a reversed range, without a request', async () => {
  const http = new FakeHttp();
  await assert.rejects(run(foodGetRange, { startDate: '2026-01-01', endDate: '2026-02-01' }, http), /32 days; at most 31/);
  await assert.rejects(run(foodGetRange, { startDate: '2026-01-05', endDate: '2026-01-01' }, http), /before startDate/);
  assert.equal(http.requests.length, 0);
});

test('food_recent finds the list tolerantly (shape not yet recorded)', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/recent/2026-01-03', { body: fixture('garmin-recent-foods.json') });
  const out = await run(foodRecent, { limit: 20 }, http);
  assert.equal(out.count, 2);
  assert.equal(out.items[0].foodId, '900001');
  assert.deepEqual(out.items[1], { somethingElse: 'passed through as sent' });
});

test('weight_list converts grams to kg and keeps samplePk', async () => {
  const http = new FakeHttp().on('/weight-service/weight/range/', { body: fixture('garmin-weight-range.json') });
  const out = await run(weightList, { startDate: '2026-01-01', endDate: '2026-01-07' }, http);
  assert.equal(http.requests[0]!.url, 'https://connectapi.garmin.com/weight-service/weight/range/2026-01-01/2026-01-07?includeAll=true');
  assert.equal(out.count, 3);
  assert.deepEqual(out.weighIns.map((w: any) => w.weightKg), [70, 70.5, 71.23]);
  assert.equal(out.weighIns[0].samplePk, 3002);
  assert.equal(out.weighIns[0].timestampUTC, new Date(1767423600000).toISOString());
  assert.equal(out.averageKg, 70.58);
  assert.equal(out.lastBeforeRange.weightKg, 71.5);
});

test('water_get reports the day total, goal and what is left', async () => {
  const http = new FakeHttp().on('/usersummary-service/usersummary/hydration/daily/2026-01-03', { body: fixture('garmin-hydration-daily.json') });
  const out = await run(waterGet, {}, http);
  assert.equal(out.totalMl, 1500);
  assert.equal(out.goalMl, 2500);
  assert.equal(out.remainingMl, 1000);
  assert.equal(out.sweatLossMl, null);
});

test('goals_get reports calorie/macro goals and the weight goal in kg', async () => {
  const http = new FakeHttp().on('/nutrition-service/settings/2026-01-03', { body: fixture('garmin-nutrition-settings.json') });
  const out = await run(goalsGet, {}, http);
  assert.equal(out.calorieGoal, 2000);
  assert.deepEqual(out.macroGoalsGrams, { protein: 100, carbs: 250, fat: 60 });
  assert.deepEqual(out.weightGoal, { type: 'LOSS', startingWeightKg: 80, targetWeightKg: 75, weeklyChangeGrams: 250, targetDate: '2026-06-01' });
  assert.match(out.localGoals, /bridge snapshot/);
});

test('food_lookupBarcode reads Open Food Facts, prefers the Czech name, reads lenient numbers', async () => {
  const http = new FakeHttp().on('world.openfoodfacts.org/api/v2/product/00000000000017.json', { body: fixture('off-product-found.json') });
  const out = await run(foodLookupBarcode, { barcode: '00000000000017' }, http);
  assert.match(http.requests[0]!.url, /^https:\/\/world\.openfoodfacts\.org\/api\/v2\/product\/00000000000017\.json\?fields=/);
  assert.equal(http.requests[0]!.request.headers['User-Agent'], 'GarminFood/1.0 (personal app)');
  assert.equal(out.found, true);
  assert.equal(out.name, 'Ukázkový výrobek');
  assert.deepEqual(out.per100g, { calories: 67, protein: 12, carbs: 4, sugar: 4, fat: 0.5, saturatedFat: 0.2, fiber: null, salt: null });
});

test('food_lookupBarcode: 404 and status 0 are "not found", 500 is an error', async () => {
  const notFound = new FakeHttp().on('/api/v2/product/', { status: 404, body: { code: '1', status: 0, status_verbose: 'product not found' } });
  assert.deepEqual(await run(foodLookupBarcode, { barcode: '12345678' }, notFound), { barcode: '12345678', found: false, reason: 'product not found' });
  const invalid = new FakeHttp().on('/api/v2/product/', { body: { code: '00000000', status: 0, status_verbose: 'no code or invalid code' } });
  assert.equal((await run(foodLookupBarcode, { barcode: '00000000' }, invalid)).found, false);
  const broken = new FakeHttp().on('/api/v2/product/', { status: 503, text: 'maintenance' });
  await assert.rejects(run(foodLookupBarcode, { barcode: '12345678' }, broken), /Open Food Facts product route failed: HTTP 503/);
});

test('server_status reports token, bridge, tools and phone-only actions without any request', async () => {
  const http = new FakeHttp();
  const bridge = mkdtempSync(join(tmpdir(), 'gf-bridge-'));
  const ctx = testContext(http, { config: { bridgeDir: bridge, experimentalWrites: ['createCustomFood'] } });
  ctx.toolReport = { offered: ['server_status'], notOffered: [{ name: 'food_getDay', reason: 'x' }] };
  const out = (await serverStatus.run({} as never, ctx)) as Record<string, any>;
  assert.equal(http.requests.length, 0);
  assert.equal(out.garmin.tokenFound, true);
  assert.deepEqual(out.bridge, { configured: true, path: bridge, folderExists: true, note: out.bridge.note });
  assert.deepEqual(out.tools.notOffered, [{ name: 'food_getDay', reason: 'x' }]);
  assert.deepEqual(out.experimentalWrites.requested, ['createCustomFood']);
  assert.deepEqual(out.phoneOnlyActions, PHONE_ONLY_ACTIONS);
  assert.ok(out.phoneOnlyActions.some((a: string) => /Restoring a backup/.test(a)));

  const none = (await serverStatus.run({} as never, testContext(http))) as Record<string, any>;
  assert.equal(none.bridge.configured, false);
  assert.match(none.bridge.note, /PC bridge not configured/);
});

test('no fixture carries anything that looks like a credential', () => {
  for (const name of ['garmin-daily-food-log.json', 'garmin-food-search.json', 'garmin-calorie-summary.json', 'garmin-weight-range.json', 'garmin-hydration-daily.json', 'garmin-nutrition-settings.json', 'garmin-recent-foods.json', 'off-product-found.json', 'registry-small.json']) {
    const text = JSON.stringify(fixture(name));
    assert.doesNotMatch(text, /access_token|token_secret|oauth_token|consumer_secret|password|Bearer /i, name);
  }
});
