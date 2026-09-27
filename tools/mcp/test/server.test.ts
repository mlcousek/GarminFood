// server.test.ts -- the tools as Claude sees them: an MCP client connected
// in memory to createServer(). Covers the spec scenarios that live at the
// protocol level: a route removed from the registry removes its tool,
// descriptions name the route and lastVerified, invalid input is refused
// naming the field, and an auth failure is an error result, never empty.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { createServer } from '../src/server.js';
import { RouteRegistry } from '../src/garmin/registry.js';
import { GarminAuthError } from '../src/garmin/errors.js';
import { fixture, fixturePath } from './fixtures.js';
import { FakeHttp } from './fakeHttp.js';
import { testContext } from './context.js';

type Ctx = ReturnType<typeof testContext>;

async function connect(ctx: Ctx) {
  const { server } = createServer(ctx);
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: 'test', version: '0.0.0' });
  await Promise.all([server.connect(serverSide), client.connect(clientSide)]);
  return client;
}

const text = (result: any): string => result.content.map((c: any) => c.text).join('\n');

test('offers the wave-2 read tools with route and lastVerified in each description', async () => {
  const client = await connect(testContext());
  const { tools } = await client.listTools();
  const names = tools.map((t) => t.name).sort();
  assert.deepEqual(names, [
    'food_getDay',
    'food_getRange',
    'food_lookupBarcode',
    'food_recent',
    'food_search',
    'goals_get',
    'server_status',
    'water_get',
    'weight_list',
  ]);
  const getDay = tools.find((t) => t.name === 'food_getDay')!;
  assert.match(getDay.description ?? '', /Garmin route: dailyFoodLog = GET \/nutrition-service\/food\/logs\/\{date\} \(last verified 2026-01-03\)/);
  assert.match(getDay.description ?? '', /Acts on: Garmin Connect, read-only, answered immediately/);
  assert.equal(getDay.annotations?.readOnlyHint, true);
  for (const tool of tools) assert.match(tool.name, /^[a-zA-Z0-9_-]{1,64}$/, `${tool.name} must be a valid Claude tool name`);
});

test('a route removed from the registry removes its tool, and server_status says why', async () => {
  const json = JSON.parse(readFileSync(fixturePath('registry-small.json'), 'utf8'));
  json.read = json.read.filter((e: { operation: string }) => e.operation !== 'dailyFoodLog');
  const client = await connect(testContext(new FakeHttp(), { registry: RouteRegistry.fromJSON(json) }));
  const names = (await client.listTools()).tools.map((t) => t.name);
  assert.ok(!names.includes('food_getDay'));
  assert.ok(names.includes('food_search'));
  const status = JSON.parse(text(await client.callTool({ name: 'server_status', arguments: {} })));
  assert.deepEqual(status.tools.notOffered, [{ name: 'food_getDay', reason: 'operation "dailyFoodLog" is missing from docs/garmin-routes.json' }]);
});

test('invalid input is refused with a message naming the field, and nothing is sent', async () => {
  const http = new FakeHttp();
  const client = await connect(testContext(http));
  const bad = await client.callTool({ name: 'food_getDay', arguments: { date: '2026-02-30' } });
  assert.equal(bad.isError, true);
  assert.match(text(bad), /date/);
  const badLimit = await client.callTool({ name: 'food_search', arguments: { query: 'x', limit: 500 } });
  assert.equal(badLimit.isError, true);
  assert.match(text(badLimit), /limit/);
  assert.equal(http.requests.length, 0);
});

test('an expired Garmin token is a loud error result, and server_status still works', async () => {
  const expired = {
    accessToken: async () => {
      throw new GarminAuthError('the OAuth1 -> OAuth2 token exchange failed (HTTP 401)', 'C:/vault/scripts/.garmin-tokens.json');
    },
    tokenStatus: () => ({ found: true, location: 'C:/vault/scripts/.garmin-tokens.json' }),
  };
  const client = await connect(testContext(new FakeHttp(), { auth: expired }));
  for (const [name, args] of [
    ['food_getDay', {}],
    ['weight_list', { startDate: '2026-01-01', endDate: '2026-01-02' }],
    ['water_get', {}],
  ] as const) {
    const result = await client.callTool({ name, arguments: args });
    assert.equal(result.isError, true, name);
    assert.match(text(result), /^Garmin sign-in needed on this PC/, name);
    assert.match(text(result), /C:\/vault\/scripts\/\.garmin-tokens\.json/, name);
  }
  const status = await client.callTool({ name: 'server_status', arguments: {} });
  assert.notEqual(status.isError, true);
});

test('a successful call returns the tool answer as JSON text with defaults applied', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/search', { body: fixture('garmin-food-search.json') });
  const client = await connect(testContext(http));
  const result = await client.callTool({ name: 'food_search', arguments: { query: 'tvaroh' } });
  assert.notEqual(result.isError, true);
  assert.match(http.requests[0]!.url, /start=0&limit=20&regionCode=CZ$/);
  assert.equal(JSON.parse(text(result)).results.length, 2);
});
