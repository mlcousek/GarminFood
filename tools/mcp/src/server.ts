// server.ts -- builds the MCP server from the selected tools.
//
// Why it exists: the one place that knows MCP. It registers every offered
// tool (definitions.ts) with its zod input schema -- so the SDK rejects an
// invalid input with a message naming the field -- and turns each tool's
// outcome into a CallToolResult: the answer as pretty JSON text, or, for
// any failure, an error result whose text is the failure's own message
// (GarminAuthError's "Garmin sign-in needed on this PC ..." etc.). A tool
// never answers an auth failure with an empty result (spec
// mcp-garmin-direct). Separate from index.ts so tests can connect a client
// to it in memory, without stdio.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import { GarminAuthError, GarminRateLimitError } from './garmin/errors.js';
import { log } from './log.js';
import { selectTools } from './tools/definitions.js';
import { SERVER_VERSION } from './tools/serverStatus.js';
import type { ToolContext, ToolDef } from './tools/types.js';

export async function runTool(def: ToolDef, args: unknown, ctx: ToolContext): Promise<CallToolResult> {
  try {
    const result = await def.run(args as never, ctx);
    return { content: [{ type: 'text', text: JSON.stringify(result, null, 2) }] };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const level = error instanceof GarminAuthError || error instanceof GarminRateLimitError ? 'error' : 'warn';
    log(level, `${def.name} failed: ${message}`);
    return { isError: true, content: [{ type: 'text', text: message }] };
  }
}

export function createServer(ctx: Omit<ToolContext, 'toolReport'>, tools?: ToolDef[]): { server: McpServer; context: ToolContext } {
  const selection = selectTools(ctx.registry, tools);
  const context: ToolContext = { ...ctx, toolReport: selection.report };
  const server = new McpServer({ name: 'garminfood', version: SERVER_VERSION });

  for (const { def, description } of selection.offered) {
    server.registerTool(
      def.name,
      {
        title: def.title,
        description,
        inputSchema: def.inputShape,
        annotations: { readOnlyHint: true, openWorldHint: def.garminOperations.length > 0 || def.otherRoute !== undefined },
      },
      // The SDK has already validated `args` against inputSchema.
      ((args: unknown) => runTool(def, args ?? {}, context)) as never,
    );
  }
  log('info', `offering ${selection.report.offered.length} tools: ${selection.report.offered.join(', ')}`);
  return { server, context };
}
