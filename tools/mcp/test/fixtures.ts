// fixtures.ts -- where the tests' JSON fixtures live.
//
// Why it exists: tsc compiles test/*.ts to dist/test/ but does not copy the
// .json fixtures, so compiled tests resolve them back in the source tree
// (tools/mcp/test/fixtures/) from the repo root. Every fixture is
// shape-only: field names as recorded in docs/garmin-routes.json, with
// synthetic values -- never the owner's own Garmin data.

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { findRepoRoot } from '../src/config.js';

export function fixturePath(name: string): string {
  return join(findRepoRoot(dirname(fileURLToPath(import.meta.url))), 'tools', 'mcp', 'test', 'fixtures', name);
}

export function fixture(name: string): unknown {
  return JSON.parse(readFileSync(fixturePath(name), 'utf8'));
}
