// registry.test.ts -- task 2.2: the route registry gate (design D7).
// Runs against a small fixture registry and, as a drift check, against the
// real docs/garmin-routes.json (read from disk only; no network).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { RouteRegistry } from '../src/garmin/registry.js';
import { findRepoRoot } from '../src/config.js';
import { fixturePath } from './fixtures.js';

const small = () => RouteRegistry.load(fixturePath('registry-small.json'));

test('looks operations up by name across sections', () => {
  const r = small();
  assert.equal(r.lastFullSweep, '2026-01-01');
  assert.equal(r.get('dailyFoodLog')?.path, '/nutrition-service/food/logs/{date}');
  assert.equal(r.get('dailyFoodLog')?.section, 'read');
  assert.equal(r.get('createFoodLogEntry')?.section, 'write');
  assert.equal(r.get('exchangeOAuth1ForOAuth2')?.section, 'auth');
  assert.equal(r.get('nope'), undefined);
});

test('a read is usable only when it is a GET last observed with 200', () => {
  const r = small();
  assert.equal(r.isVerifiedRead('dailyFoodLog'), true);
  assert.match(r.readProblem('foodSearchByBarcode') ?? '', /status 404/);
  assert.match(r.readProblem('createFoodLogEntry') ?? '', /listed under "write"/);
  assert.match(r.readProblem('missingOp') ?? '', /missing from docs\/garmin-routes\.json/);
});

test('a removed operation is reported as missing, so its tool can be disabled', () => {
  const json = JSON.parse(readFileSync(fixturePath('registry-small.json'), 'utf8'));
  json.read = json.read.filter((e: { operation: string }) => e.operation !== 'dailyFoodLog');
  const r = RouteRegistry.fromJSON(json);
  assert.equal(r.has('dailyFoodLog'), false);
  assert.equal(r.isVerifiedRead('dailyFoodLog'), false);
  assert.match(r.readProblem('dailyFoodLog') ?? '', /missing/);
});

test('writes are classified confirmed / modelled / unconfirmed', () => {
  const r = small();
  assert.equal(r.classifyWrite('createFoodLogEntry'), 'confirmed');
  assert.equal(r.classifyWrite('addWeighIn'), 'confirmed');
  assert.equal(r.classifyWrite('addHydration'), 'confirmed');
  assert.equal(r.classifyWrite('deleteFoodLogEntries'), 'modelled');
  assert.equal(r.classifyWrite('createCustomFood'), 'unconfirmed');
  assert.equal(r.classifyWrite('quickAddFoodLogEntry'), 'unconfirmed');
  assert.equal(r.classifyWrite('dailyFoodLog'), null);
  assert.equal(r.classifyWrite('missingOp'), null);
});

test('a malformed entry is skipped and a duplicate operation keeps the first', () => {
  const r = RouteRegistry.fromJSON({
    read: [
      { operation: 'a', method: 'GET', path: '/first', observedStatus: 200 },
      { operation: 'a', method: 'GET', path: '/second', observedStatus: 200 },
      { method: 'GET', path: '/no-operation' },
      'not an object',
    ],
  });
  assert.deepEqual(r.operations(), ['a']);
  assert.equal(r.get('a')?.path, '/first');
});

test('an unreadable registry fails loudly', () => {
  assert.throws(() => RouteRegistry.load(fixturePath('does-not-exist.json')), /Could not read the Garmin route registry/);
  assert.throws(() => RouteRegistry.fromJSON('nope'), /not a JSON object/);
});

test('the real registry classifies as design D7 says (drift check)', () => {
  const r = RouteRegistry.load(join(findRepoRoot(), 'docs', 'garmin-routes.json'));
  for (const op of ['dailyFoodLog', 'mealsForDate', 'foodSearch', 'nutritionSettings', 'calorieSummaryDaily', 'getWeighIns', 'weighInsDayView', 'hydrationDaily', 'recentFoods']) {
    assert.equal(r.readProblem(op), null, op);
  }
  for (const op of ['createFoodLogEntry', 'addWeighIn', 'weighInDelete', 'addHydration']) {
    assert.equal(r.classifyWrite(op), 'confirmed', op);
  }
  assert.equal(r.classifyWrite('deleteFoodLogEntries'), 'modelled');
  for (const op of ['createCustomFood', 'createCustomMeal', 'quickAddFoodLogEntry', 'bulkCreateFoodLogEntries', 'calculateGoals']) {
    assert.equal(r.classifyWrite(op), 'unconfirmed', op);
  }
});
