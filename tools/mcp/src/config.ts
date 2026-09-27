// config.ts -- where the server finds things on this PC.
//
// Why it exists: the server is configured only through environment
// variables and file paths (spec mcp-server, "runs locally over stdio and
// is configured by file paths"), never hard-coded, so the same build runs
// under Claude Desktop, Claude Code and CI:
//   - GARMINFOOD_BRIDGE_DIR -- the PC side of the phone bridge folder
//     (owner answer Q1: C:\Users\jmlcousek\iCloudDrive\GarminFood Bridge).
//     Nothing reads it yet in wave 2 beyond server_status; bridge tools
//     arrive in wave 5.
//   - GARMIN_TOKENS / VAULT_ROOT -- consumed by tools/lib/garmin-auth.mjs
//     exactly as by the other tools in tools/ (see garmin/auth.ts).
//   - GARMINFOOD_MCP_EXPERIMENTAL_WRITES -- comma-separated operation
//     names; no experimental write exists yet (wave 7), it is only reported.
// The repository root is found by walking up from this file to the folder
// holding docs/garmin-routes.json, so it works from src/ (tests) and from
// dist/src/ (the built server) alike.

import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export interface ServerConfig {
  repoRoot: string;
  registryPath: string;
  garminAuthModulePath: string;
  bridgeDir: string | null;
  experimentalWrites: string[];
}

export function findRepoRoot(start: string = dirname(fileURLToPath(import.meta.url))): string {
  let dir = resolve(start);
  for (;;) {
    if (existsSync(join(dir, 'docs', 'garmin-routes.json')) && existsSync(join(dir, 'tools', 'lib', 'garmin-auth.mjs'))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir) {
      throw new Error(`Could not find the GarminFood repository root (a folder with docs/garmin-routes.json) above ${start}`);
    }
    dir = parent;
  }
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env, repoRoot: string = findRepoRoot()): ServerConfig {
  const bridge = env.GARMINFOOD_BRIDGE_DIR?.trim();
  return {
    repoRoot,
    registryPath: join(repoRoot, 'docs', 'garmin-routes.json'),
    garminAuthModulePath: join(repoRoot, 'tools', 'lib', 'garmin-auth.mjs'),
    bridgeDir: bridge ? bridge : null,
    experimentalWrites: (env.GARMINFOOD_MCP_EXPERIMENTAL_WRITES ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0),
  };
}
