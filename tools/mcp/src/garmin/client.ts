// client.ts -- the MCP server's one door to Garmin Connect.
//
// Why it exists: every Garmin request the server makes goes through here,
// so the project rules hold in one place instead of in every tool:
//   - the route comes from the registry by operation name (registry.ts),
//     never from a string in a tool -- an operation missing from
//     docs/garmin-routes.json cannot be called at all;
//   - wave 2 is read-only: read() refuses anything but a verified GET, and
//     there is no write method yet (writes arrive with their own gating in
//     waves 6-7);
//   - failures are typed and loud (errors.ts): 401/403, a missing token, a
//     failed token exchange, or an HTML sign-in page -> GarminAuthError;
//     429 -> GarminRateLimitError with Retry-After, and no retry; anything
//     else -> GarminHttpError naming the route. Never an empty answer.
// The HTTP layer is injected (HttpFetch) so tests run against a fake and
// never reach the live API. Auth comes from auth.ts. Used by
// tools/definitions.ts.

import type { AuthProvider } from './auth.js';
import { GarminAuthError, GarminHttpError, GarminRateLimitError } from './errors.js';
import type { RouteEntry, RouteRegistry } from './registry.js';

export interface HttpRequest {
  method: string;
  headers: Record<string, string>;
}

export interface HttpResponse {
  status: number;
  headers: { get(name: string): string | null };
  text(): Promise<string>;
}

export type HttpFetch = (url: string, request: HttpRequest) => Promise<HttpResponse>;

/** Node's global fetch, with a timeout so a hung request can't hang a tool call. */
export const nodeFetch: HttpFetch = (url, request) =>
  fetch(url, { method: request.method, headers: request.headers, signal: AbortSignal.timeout(30_000) });

/** Same identity as tools/lib/garmin-auth.mjs's UA and the iOS app's GarminClient. */
export const GARMIN_USER_AGENT = 'com.garmin.android.apps.connectmobile';
const DEFAULT_BASE = 'connectapi.garmin.com';

export type RouteParams = Record<string, string | number | undefined>;

/**
 * Fills a registry path template.
 *   - Path placeholders ({date}) are required.
 *   - A query pair whose value is a placeholder (startDate={date}) is filled
 *     from the query KEY first (params.startDate), then from the
 *     placeholder name (params.date) -- the registry reuses {date} for both
 *     ends of calorieSummaryDaily -- and dropped when neither is given.
 *   - Literal query pairs (includeAll=true) are kept as written.
 */
export function fillRoute(entry: RouteEntry, params: RouteParams): string {
  const q = entry.path.indexOf('?');
  const pathPart = q < 0 ? entry.path : entry.path.slice(0, q);
  const queryPart = q < 0 ? '' : entry.path.slice(q + 1);

  const path = pathPart.replace(/\{([^}]+)\}/g, (_match, name: string) => {
    const value = params[name];
    if (value === undefined || value === '') throw new Error(`${entry.operation}: missing path parameter "${name}"`);
    return encodeURIComponent(String(value));
  });

  const pairs: string[] = [];
  for (const pair of queryPart ? queryPart.split('&') : []) {
    const eq = pair.indexOf('=');
    const key = eq < 0 ? pair : pair.slice(0, eq);
    const rawValue = eq < 0 ? '' : pair.slice(eq + 1);
    const placeholder = /^\{([^}]+)\}$/.exec(rawValue);
    if (!placeholder) {
      pairs.push(pair);
      continue;
    }
    const value = params[key] ?? params[placeholder[1] ?? ''];
    if (value !== undefined && value !== '') pairs.push(`${key}=${encodeURIComponent(String(value))}`);
  }
  return pairs.length ? `${path}?${pairs.join('&')}` : path;
}

/** Seconds from a Retry-After header (delta-seconds or an HTTP date), or null. */
export function parseRetryAfter(header: string | null, now: number = Date.now()): number | null {
  if (!header) return null;
  const trimmed = header.trim();
  if (/^\d+$/.test(trimmed)) return Number(trimmed);
  const at = Date.parse(trimmed);
  if (Number.isNaN(at)) return null;
  return Math.max(0, Math.ceil((at - now) / 1000));
}

export class GarminClient {
  constructor(
    private readonly registry: RouteRegistry,
    private readonly auth: AuthProvider,
    private readonly http: HttpFetch = nodeFetch,
    private readonly now: () => number = Date.now,
  ) {}

  /** The full URL a read of `operation` would request (no network). */
  urlFor(operation: string, params: RouteParams): string {
    const entry = this.readEntry(operation);
    return `https://${entry.base ?? DEFAULT_BASE}${fillRoute(entry, params)}`;
  }

  /** GET a verified read route and return its parsed JSON body (null for an empty body). */
  async read(operation: string, params: RouteParams = {}): Promise<unknown> {
    const entry = this.readEntry(operation);
    const url = this.urlFor(operation, params);
    const route = `${entry.method} ${entry.path}`;

    const token = await this.auth.accessToken();
    let response: HttpResponse;
    try {
      response = await this.http(url, {
        method: 'GET',
        headers: { 'User-Agent': GARMIN_USER_AGENT, Authorization: `Bearer ${token}`, Accept: 'application/json' },
      });
    } catch (error) {
      throw new GarminHttpError(operation, route, 'network', error instanceof Error ? error.message : String(error));
    }

    const { status } = response;
    if (status === 401 || status === 403) {
      throw new GarminAuthError(`Garmin answered HTTP ${status} on ${operation}`, this.auth.tokenStatus().location, status);
    }
    if (status === 429) {
      throw new GarminRateLimitError(operation, parseRetryAfter(response.headers.get('retry-after'), this.now()));
    }

    const text = await response.text();
    if (status < 200 || status >= 300) {
      throw new GarminHttpError(operation, route, status, text.slice(0, 300));
    }
    const contentType = response.headers.get('content-type') ?? '';
    if (contentType.includes('html') || text.trimStart().startsWith('<')) {
      // A 200 carrying Garmin's sign-in page is a failed auth, not data.
      throw new GarminAuthError(`Garmin returned its sign-in page instead of data on ${operation}`, this.auth.tokenStatus().location, status);
    }
    if (!text.trim()) return null;
    try {
      return JSON.parse(text);
    } catch {
      throw new GarminHttpError(operation, route, status, `response is not JSON: ${text.slice(0, 120)}`);
    }
  }

  private readEntry(operation: string): RouteEntry {
    const problem = this.registry.readProblem(operation);
    if (problem) throw new Error(`Refusing to call Garmin: ${problem}.`);
    return this.registry.get(operation) as RouteEntry;
  }
}
