// definitions.ts -- the tool list, decided against the route registry.
//
// Why it exists: spec mcp-garmin-direct says the server refuses to offer a
// tool whose Garmin route is missing (or not verified) in
// docs/garmin-routes.json, names the missing operation in its startup log,
// and puts the route and its lastVerified date in each tool's description.
// This module does exactly that once at startup; server.ts registers the
// result over MCP and the tests use it directly.

import { log } from '../log.js';
import type { RouteRegistry } from '../garmin/registry.js';
import { garminReadTools } from './garminReads.js';
import { foodLookupBarcode } from './openFoodFacts.js';
import { serverStatus } from './serverStatus.js';
import type { ToolDef, ToolReport } from './types.js';

export const ALL_TOOLS: ToolDef[] = [serverStatus, ...garminReadTools, foodLookupBarcode];

export interface ToolSelection {
  offered: { def: ToolDef; description: string }[];
  report: ToolReport;
}

export function describeTool(def: ToolDef, registry: RouteRegistry): string {
  const lines = [def.summary, '', `Acts on: ${def.acts}`];
  for (const op of def.garminOperations) {
    const entry = registry.get(op);
    if (entry) lines.push(`Garmin route: ${op} = ${entry.method} ${entry.path} (last verified ${entry.lastVerified ?? 'unknown'}).`);
  }
  if (def.otherRoute) lines.push(`Route: ${def.otherRoute}.`);
  return lines.join('\n');
}

export function selectTools(registry: RouteRegistry, tools: ToolDef[] = ALL_TOOLS): ToolSelection {
  const offered: ToolSelection['offered'] = [];
  const report: ToolReport = { offered: [], notOffered: [] };
  for (const def of tools) {
    const problems = def.garminOperations.map((op) => registry.readProblem(op)).filter((p): p is string => p !== null);
    if (problems.length) {
      const reason = problems.join('; ');
      report.notOffered.push({ name: def.name, reason });
      log('warn', `tool ${def.name} not offered: ${reason}`);
      continue;
    }
    offered.push({ def, description: describeTool(def, registry) });
    report.offered.push(def.name);
  }
  return { offered, report };
}
