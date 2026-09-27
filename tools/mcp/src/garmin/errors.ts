// errors.ts -- the typed failures of a Garmin call.
//
// Why it exists: "auth failures are loud, everything else degrades quietly"
// is a hard rule of this project (CLAUDE.md), because a silent auth failure
// already cost it once. So a Garmin tool never turns a failure into an empty
// answer: each failure becomes one of these, and tools/definitions.ts turns
// it into an MCP tool error whose text says what happened and what to do
// (spec mcp-garmin-direct "Garmin auth failures are loud and actionable"):
//   - GarminAuthError: missing token file, failed OAuth1 -> OAuth2 exchange,
//     401/403, or an HTML sign-in page where JSON was expected;
//   - GarminRateLimitError: 429 -- reports Retry-After and stops, never
//     retries on its own;
//   - GarminHttpError: any other failure, naming the route.
// Thrown by garmin/client.ts and garmin/auth.ts.

export const AUTH_FIX_HINT =
  'To fix: get a fresh OAuth1 token with a browser sign-in (the Obsidian vault\'s garmin-health-sync plugin stores it; ' +
  'GARMIN_TOKENS or VAULT_ROOT must point at it, as for tools/garmin-get.mjs), then restart this MCP server. ' +
  'Tools that do not need Garmin (server_status, food_lookupBarcode) keep working.';

export class GarminAuthError extends Error {
  override readonly name = 'GarminAuthError';

  constructor(
    readonly reason: string,
    readonly tokenLocation: string,
    readonly status?: number,
  ) {
    super(`Garmin sign-in needed on this PC: ${reason}. Token: ${tokenLocation}. ${AUTH_FIX_HINT}`);
  }
}

export class GarminRateLimitError extends Error {
  override readonly name = 'GarminRateLimitError';

  constructor(
    readonly operation: string,
    readonly retryAfterSeconds: number | null,
  ) {
    super(
      `Garmin is rate-limiting this PC (HTTP 429 on ${operation}). ` +
        (retryAfterSeconds === null
          ? 'Garmin sent no Retry-After; wait a few minutes before trying again.'
          : `Retry-After says wait ${retryAfterSeconds} s before trying again.`) +
        ' Nothing was retried automatically.',
    );
  }
}

export class GarminHttpError extends Error {
  override readonly name = 'GarminHttpError';

  constructor(
    readonly operation: string,
    readonly route: string,
    readonly status: number | 'network',
    readonly detail: string,
  ) {
    super(`Garmin route ${operation} (${route}) failed: ${status === 'network' ? 'network error' : `HTTP ${status}`}${detail ? ` -- ${detail}` : ''}`);
  }
}
