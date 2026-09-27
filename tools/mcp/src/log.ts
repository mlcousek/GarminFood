// log.ts -- the server's only logger.
//
// Why it exists: over stdio, stdout IS the MCP channel; a single stray
// console.log there corrupts the JSON-RPC stream and Claude drops the
// server. Everything human-readable therefore goes to stderr, which Claude
// Desktop writes to its per-server log file (%APPDATA%\Claude\logs\
// mcp-server-garminfood.log) and Claude Code shows with `claude --debug`.
// Used by every other module; depends on nothing.

export type LogLevel = 'info' | 'warn' | 'error';

export function log(level: LogLevel, message: string): void {
  process.stderr.write(`[garminfood-mcp] ${new Date().toISOString()} ${level.toUpperCase()} ${message}\n`);
}
