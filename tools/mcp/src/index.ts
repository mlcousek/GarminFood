#!/usr/bin/env node
// index.ts -- entry point of the GarminFood MCP server (add-mcp-server).
//
// Why it exists: Claude Desktop / Claude Code start this file as a child
// process and talk MCP to it over stdin/stdout. It opens no network
// listener (spec mcp-server). All logging goes to stderr (log.ts), because
// stdout is the protocol channel.
//
// Startup: read the configuration (config.ts), load the route registry
// (a missing or unreadable registry is fatal: no Garmin call may bypass
// it), set up Garmin auth over tools/lib/garmin-auth.mjs (a missing token
// is NOT fatal -- Garmin tools then fail loudly per call, the rest works),
// and register the tools the registry allows (server.ts).

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadConfig } from './config.js';
import { createVaultAuth } from './garmin/auth.js';
import { GarminClient, nodeFetch } from './garmin/client.js';
import { RouteRegistry } from './garmin/registry.js';
import { log } from './log.js';
import { createServer } from './server.js';
import { localDate } from './tools/shape.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const registry = RouteRegistry.load(config.registryPath);
  const auth = await createVaultAuth(config.garminAuthModulePath);
  const garmin = new GarminClient(registry, auth, nodeFetch);

  const token = auth.tokenStatus();
  log(
    token.found ? 'info' : 'warn',
    token.found ? `Garmin token file: ${token.location}` : `no Garmin token file (${token.location}); Garmin tools will ask for sign-in`,
  );
  log('info', `bridge folder: ${config.bridgeDir ?? 'not configured (GARMINFOOD_BRIDGE_DIR)'}`);

  const { server } = createServer({ config, registry, garmin, auth, http: nodeFetch, today: () => localDate() });
  await server.connect(new StdioServerTransport());
  log('info', `ready (registry ${config.registryPath}, last full sweep ${registry.lastFullSweep ?? 'unknown'})`);
}

main().catch((error: unknown) => {
  log('error', `fatal: ${error instanceof Error ? (error.stack ?? error.message) : String(error)}`);
  process.exit(1);
});
