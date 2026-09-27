// fakeHttp.ts -- the tests' stand-in for the network.
//
// Why it exists: no test may call the live Garmin API (design D5), so every
// Garmin / Open Food Facts request in the tests goes through FakeHttp, which
// answers from canned replies (shape-only fixtures, see fixtures.ts) and
// records each request so tests can assert on the exact URL and headers
// sent. An unexpected request fails the test instead of reaching the
// network. fakeAuth() likewise never reads a token file.

import type { HttpFetch, HttpRequest, HttpResponse } from '../src/garmin/client.js';
import type { AuthProvider } from '../src/garmin/auth.js';

export interface FakeReply {
  status?: number;
  body?: unknown;
  /** Sent verbatim instead of JSON-encoding `body`. */
  text?: string;
  headers?: Record<string, string>;
}

interface Route {
  prefix: string;
  reply: FakeReply | ((url: URL) => FakeReply);
}

export class FakeHttp {
  readonly requests: { url: string; request: HttpRequest }[] = [];
  private readonly routes: Route[] = [];

  /** Answer requests whose pathname + search (or host + pathname + search) starts with `prefix`. */
  on(prefix: string, reply: FakeReply | ((url: URL) => FakeReply)): this {
    this.routes.push({ prefix, reply });
    return this;
  }

  readonly fetch: HttpFetch = async (url: string, request: HttpRequest): Promise<HttpResponse> => {
    this.requests.push({ url, request });
    const parsed = new URL(url);
    const pathAndQuery = parsed.pathname + parsed.search;
    const route = this.routes.find((r) => pathAndQuery.startsWith(r.prefix) || (parsed.host + pathAndQuery).startsWith(r.prefix));
    if (!route) throw new Error(`FakeHttp: no canned reply for ${url}`);
    const reply = typeof route.reply === 'function' ? route.reply(parsed) : route.reply;
    const headers = new Map<string, string>([['content-type', 'application/json;charset=UTF-8']]);
    for (const [k, v] of Object.entries(reply.headers ?? {})) headers.set(k.toLowerCase(), v);
    const text = reply.text ?? (reply.body === undefined ? '' : JSON.stringify(reply.body));
    return {
      status: reply.status ?? 200,
      headers: { get: (name: string) => headers.get(name.toLowerCase()) ?? null },
      text: async () => text,
    };
  };
}

/** An auth provider that never touches a token file or the network. */
export function fakeAuth(token = 'test-access'): AuthProvider {
  return {
    accessToken: async () => token,
    tokenStatus: () => ({ found: true, location: 'GARMIN_TOKENS=<test fixture>' }),
  };
}
