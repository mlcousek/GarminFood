// context.ts -- a ToolContext for tests: fixture registry, fake auth and
// FakeHttp, a fixed "today". Nothing in it reads a real token file or
// reaches the network.

import { RouteRegistry } from '../src/garmin/registry.js';
import { GarminClient } from '../src/garmin/client.js';
import type { AuthProvider } from '../src/garmin/auth.js';
import type { ServerConfig } from '../src/config.js';
import type { ToolContext } from '../src/tools/types.js';
import { fixturePath } from './fixtures.js';
import { FakeHttp, fakeAuth } from './fakeHttp.js';

export const TODAY = '2026-01-03';

export function testConfig(overrides: Partial<ServerConfig> = {}): ServerConfig {
  return {
    repoRoot: '/repo',
    registryPath: fixturePath('registry-small.json'),
    garminAuthModulePath: '/repo/tools/lib/garmin-auth.mjs',
    bridgeDir: null,
    experimentalWrites: [],
    ...overrides,
  };
}

export function testContext(
  http: FakeHttp = new FakeHttp(),
  options: { registry?: RouteRegistry; auth?: AuthProvider; config?: Partial<ServerConfig> } = {},
): Omit<ToolContext, 'toolReport'> & { toolReport: ToolContext['toolReport'] } {
  const registry = options.registry ?? RouteRegistry.load(fixturePath('registry-small.json'));
  const auth = options.auth ?? fakeAuth();
  return {
    config: testConfig(options.config),
    registry,
    auth,
    garmin: new GarminClient(registry, auth, http.fetch),
    http: http.fetch,
    today: () => TODAY,
    toolReport: { offered: [], notOffered: [] },
  };
}
