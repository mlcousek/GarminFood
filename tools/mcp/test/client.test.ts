// client.test.ts -- task 2.3: the Garmin client's URL building and its
// loud, typed failures, against FakeHttp (no live call), plus auth.ts over
// tools/lib/garmin-auth.mjs with temp token files (no network either).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GarminClient, fillRoute, parseRetryAfter } from '../src/garmin/client.js';
import { GarminAuthError, GarminHttpError, GarminRateLimitError } from '../src/garmin/errors.js';
import { RouteRegistry } from '../src/garmin/registry.js';
import { createVaultAuth } from '../src/garmin/auth.js';
import { findRepoRoot } from '../src/config.js';
import { fixturePath } from './fixtures.js';
import { FakeHttp, fakeAuth } from './fakeHttp.js';

const registry = () => RouteRegistry.load(fixturePath('registry-small.json'));
const client = (http: FakeHttp) => new GarminClient(registry(), fakeAuth(), http.fetch, () => Date.parse('2026-01-10T12:00:00Z'));

test('reads a verified route with the bearer token and the mobile user agent', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/2026-01-03', { body: { mealDate: '2026-01-03' } });
  const body = await client(http).read('dailyFoodLog', { date: '2026-01-03' });
  assert.deepEqual(body, { mealDate: '2026-01-03' });
  assert.equal(http.requests.length, 1);
  const sent = http.requests[0]!;
  assert.equal(sent.url, 'https://connectapi.garmin.com/nutrition-service/food/logs/2026-01-03');
  assert.equal(sent.request.method, 'GET');
  assert.equal(sent.request.headers.Authorization, 'Bearer test-access');
  assert.equal(sent.request.headers['User-Agent'], 'com.garmin.android.apps.connectmobile');
});

test('fills query placeholders by key first, drops absent ones, keeps literals', () => {
  const r = registry();
  assert.equal(
    fillRoute(r.get('calorieSummaryDaily')!, { startDate: '2026-01-01', endDate: '2026-01-07' }),
    '/nutrition-service/calorie/summary/daily?startDate=2026-01-01&endDate=2026-01-07',
  );
  assert.equal(
    fillRoute(r.get('foodSearch')!, { searchExpression: 'mléko', start: 0, limit: 20 }),
    '/nutrition-service/food/search?searchExpression=ml%C3%A9ko&start=0&limit=20',
  );
  assert.equal(
    fillRoute(r.get('getWeighIns')!, { startdate: '2026-01-01', enddate: '2026-01-31' }),
    '/weight-service/weight/range/2026-01-01/2026-01-31?includeAll=true',
  );
  assert.throws(() => fillRoute(r.get('dailyFoodLog')!, {}), /missing path parameter "date"/);
});

test('refuses an unverified or missing read route without sending anything', async () => {
  const http = new FakeHttp();
  await assert.rejects(client(http).read('foodSearchByBarcode', { barCode: '123' }), /Refusing to call Garmin: .*status 404/);
  await assert.rejects(client(http).read('createFoodLogEntry'), /Refusing to call Garmin: .*"write"/);
  await assert.rejects(client(http).read('noSuchOperation'), /missing from docs\/garmin-routes\.json/);
  assert.equal(http.requests.length, 0);
});

for (const status of [401, 403]) {
  test(`HTTP ${status} is a loud auth error naming the token location`, async () => {
    const http = new FakeHttp().on('/nutrition-service/food/logs/', { status, body: { message: 'denied' } });
    await assert.rejects(client(http).read('dailyFoodLog', { date: '2026-01-03' }), (error: unknown) => {
      assert.ok(error instanceof GarminAuthError);
      assert.equal(error.status, status);
      assert.match(error.message, /^Garmin sign-in needed on this PC/);
      assert.match(error.message, /GARMIN_TOKENS=<test fixture>/);
      assert.match(error.message, /restart this MCP server/);
      return true;
    });
  });
}

test('an auth provider failure stops the call before any request', async () => {
  const http = new FakeHttp();
  const failing = {
    accessToken: async () => {
      throw new GarminAuthError('no usable Garmin token file', 'GARMIN_TOKENS=/nowhere');
    },
    tokenStatus: () => ({ found: false, location: 'GARMIN_TOKENS=/nowhere' }),
  };
  const c = new GarminClient(registry(), failing, http.fetch);
  await assert.rejects(c.read('dailyFoodLog', { date: '2026-01-03' }), GarminAuthError);
  assert.equal(http.requests.length, 0);
});

test('429 reports Retry-After in seconds and is not retried', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/', { status: 429, headers: { 'Retry-After': '120' } });
  await assert.rejects(client(http).read('dailyFoodLog', { date: '2026-01-03' }), (error: unknown) => {
    assert.ok(error instanceof GarminRateLimitError);
    assert.equal(error.retryAfterSeconds, 120);
    assert.match(error.message, /wait 120 s/);
    assert.match(error.message, /Nothing was retried/);
    return true;
  });
  assert.equal(http.requests.length, 1);
});

test('Retry-After as an HTTP date, and a missing one', () => {
  const now = Date.parse('2026-01-10T12:00:00Z');
  assert.equal(parseRetryAfter('Sat, 10 Jan 2026 12:01:30 GMT', now), 90);
  assert.equal(parseRetryAfter('Sat, 10 Jan 2026 11:00:00 GMT', now), 0);
  assert.equal(parseRetryAfter(null, now), null);
  assert.equal(parseRetryAfter('soon', now), null);
});

test('any other HTTP failure names the route', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/', { status: 500, text: 'Internal error' });
  await assert.rejects(client(http).read('dailyFoodLog', { date: '2026-01-03' }), (error: unknown) => {
    assert.ok(error instanceof GarminHttpError);
    assert.equal(error.status, 500);
    assert.match(error.message, /dailyFoodLog \(GET \/nutrition-service\/food\/logs\/\{date\}\) failed: HTTP 500 -- Internal error/);
    return true;
  });
});

test('a sign-in page served with 200 is an auth error, not data', async () => {
  const http = new FakeHttp().on('/nutrition-service/food/logs/', { text: '<!DOCTYPE html><html>Sign in</html>', headers: { 'content-type': 'text/html' } });
  await assert.rejects(client(http).read('dailyFoodLog', { date: '2026-01-03' }), /Garmin sign-in needed on this PC: Garmin returned its sign-in page/);
});

test('a network failure is a GarminHttpError; an empty body reads as null', async () => {
  const broken = new GarminClient(registry(), fakeAuth(), async () => {
    throw new Error('ECONNRESET');
  });
  await assert.rejects(broken.read('dailyFoodLog', { date: '2026-01-03' }), /failed: network error -- ECONNRESET/);

  const http = new FakeHttp().on('/nutrition-service/food/logs/', { status: 204, text: '' });
  assert.equal(await client(http).read('dailyFoodLog', { date: '2026-01-03' }), null);
});

// --- auth.ts over the real tools/lib/garmin-auth.mjs (temp files, no network) ---

const authModule = join(findRepoRoot(), 'tools', 'lib', 'garmin-auth.mjs');

async function withGarminTokensEnv<T>(value: string, run: () => Promise<T>): Promise<T> {
  const previous = process.env.GARMIN_TOKENS;
  process.env.GARMIN_TOKENS = value;
  try {
    return await run();
  } finally {
    if (previous === undefined) delete process.env.GARMIN_TOKENS;
    else process.env.GARMIN_TOKENS = previous;
  }
}

test('a missing token file is a loud auth error and tokenStatus says not found', async () => {
  const missing = join(mkdtempSync(join(tmpdir(), 'gf-mcp-')), 'absent.json');
  await withGarminTokensEnv(missing, async () => {
    const auth = await createVaultAuth(authModule, process.env);
    const status = auth.tokenStatus();
    assert.equal(status.found, false);
    assert.match(status.location, /GARMIN_TOKENS=.*absent\.json/);
    await assert.rejects(auth.accessToken(), (error: unknown) => {
      assert.ok(error instanceof GarminAuthError);
      assert.match(error.message, /^Garmin sign-in needed on this PC: no usable Garmin token file/);
      assert.match(error.message, /absent\.json/);
      return true;
    });
  });
});

test('an unexpired OAuth2 token in the file is used as is (no exchange, no network)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gf-mcp-'));
  const file = join(dir, 'garmin-auth-fixture.json');
  const future = Math.floor(Date.now() / 1000) + 3600;
  writeFileSync(file, JSON.stringify({ oauth1: { oauth_token: 'o1', oauth_token_secret: 's1' }, oauth2: { access_token: 'fixture-access', expires_at: future } }));
  await withGarminTokensEnv(file, async () => {
    const auth = await createVaultAuth(authModule, process.env);
    assert.deepEqual(auth.tokenStatus(), { found: true, location: file });
    assert.equal(await auth.accessToken(), 'fixture-access');
  });
});

test('a failed OAuth1 -> OAuth2 exchange is a loud auth error naming the token source', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'gf-mcp-'));
  const stub = join(dir, 'stub-garmin-auth.mjs');
  writeFileSync(
    stub,
    "export function loadTokens() { return { oauth1: {}, oauth2: null, source: 'C:/vault/scripts/.garmin-tokens.json' }; }\n" +
      "export async function getAccessToken() { throw new Error('OAuth1 -> OAuth2 exchange failed: HTTP 401 expired'); }\n",
  );
  const auth = await createVaultAuth(stub, {});
  await assert.rejects(auth.accessToken(), (error: unknown) => {
    assert.ok(error instanceof GarminAuthError);
    assert.match(error.message, /token exchange failed \(OAuth1 -> OAuth2 exchange failed: HTTP 401 expired\)/);
    assert.match(error.message, /C:\/vault\/scripts\/\.garmin-tokens\.json/);
    return true;
  });
});
