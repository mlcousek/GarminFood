#!/usr/bin/env node
// index.ts -- entry point of the GarminFood MCP server (add-mcp-server).
//
// Why it exists: Claude Desktop / Claude Code start this file as a child
// process and talk MCP to it over stdin/stdout. It opens no network
// listener (spec mcp-server). All logging goes to stderr (log.ts), because
// stdout is the protocol channel.
//
// Depends on config.ts for paths. Wave 2.1 is the bare skeleton: a named
// server with no tools yet.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadConfig } from './config.js';
import { log } from './log.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const server = new McpServer({ name: 'garminfood', version: '0.1.0' });
  await server.connect(new StdioServerTransport());
  log('info', `started (repo ${config.repoRoot}, bridge ${config.bridgeDir ?? 'not configured'})`);
}

main().catch((error: unknown) => {
  log('error', `fatal: ${error instanceof Error ? error.stack ?? error.message : String(error)}`);
  process.exit(1);
});
