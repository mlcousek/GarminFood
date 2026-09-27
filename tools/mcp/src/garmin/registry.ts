// registry.ts -- the route registry gate (add-mcp-server design D7, spec
// mcp-garmin-direct "Every Garmin call goes through the route registry").
//
// Why it exists: Garmin's private API is undocumented and changes without
// notice, so this project records every route it depends on, with the date
// and status it was last observed, in docs/garmin-routes.json. The MCP
// server may only call routes listed there, looks each one up by its
// `operation` name at startup, and derives what is allowed from the
// recorded status -- so moving a route to "confirmed" in the registry is
// picked up without a code change here:
//   - reads: offered only when `observedStatus` is 200 (spec "Reads use
//     only routes verified as working");
//   - writes: classified confirmed / modelled / unconfirmed (D7). Wave 2
//     offers no write tool at all; the classification is here so waves 5-7
//     gate on it rather than on a hard-coded list.
// Used by garmin/client.ts (URL building) and tools/definitions.ts (which
// tools to offer, and the route + lastVerified text in each description).

import { readFileSync } from 'node:fs';

export type RouteSection = 'auth' | 'read' | 'write';
export type WriteClass = 'confirmed' | 'modelled' | 'unconfirmed';

export interface RouteEntry {
  operation: string;
  method: string;
  path: string;
  base?: string;
  lastVerified?: string;
  observedStatus?: number | string;
  notes?: string;
  section: RouteSection;
}

interface RegistryFile {
  lastFullSweep?: unknown;
  auth?: unknown;
  read?: unknown;
  write?: unknown;
}

const SECTIONS: RouteSection[] = ['auth', 'read', 'write'];

export class RouteRegistry {
  private readonly byOperation = new Map<string, RouteEntry>();

  private constructor(
    readonly lastFullSweep: string | null,
    readonly sourcePath: string | null,
  ) {}

  static load(path: string): RouteRegistry {
    let parsed: unknown;
    try {
      parsed = JSON.parse(readFileSync(path, 'utf8'));
    } catch (error) {
      throw new Error(`Could not read the Garmin route registry at ${path}: ${error instanceof Error ? error.message : String(error)}`);
    }
    return RouteRegistry.fromJSON(parsed, path);
  }

  static fromJSON(json: unknown, sourcePath: string | null = null): RouteRegistry {
    if (!json || typeof json !== 'object') throw new Error('Garmin route registry is not a JSON object');
    const file = json as RegistryFile;
    const registry = new RouteRegistry(typeof file.lastFullSweep === 'string' ? file.lastFullSweep : null, sourcePath);
    for (const section of SECTIONS) {
      const list = file[section];
      if (!Array.isArray(list)) continue;
      for (const raw of list) {
        const entry = toEntry(raw, section);
        // First entry wins: the registry is hand-edited, and a duplicate
        // operation is a mistake, not an override.
        if (entry && !registry.byOperation.has(entry.operation)) registry.byOperation.set(entry.operation, entry);
      }
    }
    return registry;
  }

  get(operation: string): RouteEntry | undefined {
    return this.byOperation.get(operation);
  }

  has(operation: string): boolean {
    return this.byOperation.has(operation);
  }

  operations(): string[] {
    return [...this.byOperation.keys()];
  }

  /** Why `operation` may not be used as a read, or null when it may. */
  readProblem(operation: string): string | null {
    const entry = this.get(operation);
    if (!entry) return `operation "${operation}" is missing from docs/garmin-routes.json`;
    if (entry.section !== 'read') return `operation "${operation}" is listed under "${entry.section}", not "read"`;
    if (entry.method.toUpperCase() !== 'GET') return `operation "${operation}" is ${entry.method}, not GET`;
    if (entry.observedStatus !== 200) {
      return `operation "${operation}" was last observed with status ${JSON.stringify(entry.observedStatus ?? null)}, not 200`;
    }
    return null;
  }

  isVerifiedRead(operation: string): boolean {
    return this.readProblem(operation) === null;
  }

  /**
   * D7's three buckets, from what the registry records:
   *   - confirmed: a 2xx status was observed, or the status text says it
   *     was exercised on a real device with no failure or caveat
   *     (addHydration: "exercised on a real device, owner reports entries
   *     arriving in Garmin");
   *   - modelled: "modelled on a live-tested client, not yet exercised by
   *     this project" (deleteFoodLogEntries);
   *   - unconfirmed: everything else -- documented only, guessed, never
   *     sent, or exercised with an error (createCustomFood's 400).
   * Returns null for an operation that is missing or not a write.
   */
  classifyWrite(operation: string): WriteClass | null {
    const entry = this.get(operation);
    if (!entry || entry.section !== 'write') return null;
    const status = entry.observedStatus;
    if (typeof status === 'number') return status >= 200 && status < 300 ? 'confirmed' : 'unconfirmed';
    if (typeof status !== 'string') return 'unconfirmed';
    const text = status.toLowerCase();
    if (text.startsWith('modelled')) return 'modelled';
    const caveat = /\b[45]\d\d\b|not yet|never|not exercised|unconfirmed|guess/.test(text);
    if (text.startsWith('exercised on a real device') && !caveat) return 'confirmed';
    return 'unconfirmed';
  }
}

function toEntry(raw: unknown, section: RouteSection): RouteEntry | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.operation !== 'string' || typeof r.method !== 'string' || typeof r.path !== 'string') return null;
  const entry: RouteEntry = { operation: r.operation, method: r.method, path: r.path, section };
  if (typeof r.base === 'string') entry.base = r.base;
  if (typeof r.lastVerified === 'string') entry.lastVerified = r.lastVerified;
  if (typeof r.observedStatus === 'number' || typeof r.observedStatus === 'string') entry.observedStatus = r.observedStatus;
  if (typeof r.notes === 'string') entry.notes = r.notes;
  return entry;
}
