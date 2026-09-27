// types.ts -- what a tool is, and what it gets to work with.
//
// Why it exists: tools are plain data + an async `run` (no MCP types), so
// the tests can call them directly against a fake HTTP layer, and server.ts
// alone knows how to expose them over MCP. Each tool declares the Garmin
// operations it needs; definitions.ts offers it only when every one of them
// is a verified read in docs/garmin-routes.json, and builds its description
// from the registry (route + lastVerified).

import type { z } from 'zod';
import type { AuthProvider } from '../garmin/auth.js';
import type { GarminClient, HttpFetch } from '../garmin/client.js';
import type { RouteRegistry } from '../garmin/registry.js';
import type { ServerConfig } from '../config.js';

export interface ToolReport {
  offered: string[];
  notOffered: { name: string; reason: string }[];
}

export interface ToolContext {
  config: ServerConfig;
  registry: RouteRegistry;
  garmin: GarminClient;
  auth: AuthProvider;
  /** For non-Garmin public APIs (Open Food Facts). */
  http: HttpFetch;
  /** Today's date on this PC, yyyy-MM-dd. */
  today(): string;
  /** Filled in by definitions.ts once the tool list is decided. */
  toolReport: ToolReport;
}

export interface ToolDef<Shape extends z.ZodRawShape = z.ZodRawShape> {
  /** Wire name, `area_verb` (the design's `area.verb`; see README "Tool names"). */
  name: string;
  title: string;
  /** What the tool does, for Claude. Route and freshness lines are appended. */
  summary: string;
  /** Where it acts and when (spec: every description says so). */
  acts: string;
  /** Garmin operations it reads; all must be verified reads for it to be offered. */
  garminOperations: string[];
  /** A non-Garmin route, described verbatim (e.g. Open Food Facts). */
  otherRoute?: string;
  inputShape: Shape;
  run(args: z.infer<z.ZodObject<Shape>>, ctx: ToolContext): Promise<unknown>;
}

/** Keeps each tool's own input type while storing them in one list. */
export function defineTool<Shape extends z.ZodRawShape>(def: ToolDef<Shape>): ToolDef {
  return def as unknown as ToolDef;
}
