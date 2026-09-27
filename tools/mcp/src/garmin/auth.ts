// auth.ts -- Garmin credentials for the MCP server, via tools/lib/garmin-auth.mjs.
//
// Why it exists: this PC already signs in to Garmin with the Obsidian
// vault's long-lived OAuth1 token, exchanged for a ~24 h OAuth2 token by
// tools/lib/garmin-auth.mjs (scripted SSO login is blocked by Cloudflare
// since March 2026, so a token can only be obtained in a browser). The
// server reuses that module unchanged (design D5) -- same token discovery
// (GARMIN_TOKENS, else VAULT_ROOT's scripts/.garmin-tokens.json or the
// garmin-health-sync plugin's data.json), same exchange -- and only adds
// the loud, typed failure (errors.ts) the MCP tools need.
//
// The module is imported by absolute path at runtime (not a relative
// import) so the same code works from src/ under test and from dist/src/.
// Tokens never leave this process: they are not logged, not returned by any
// tool, and never written to the bridge folder (design D8).

import { pathToFileURL } from 'node:url';
import { GarminAuthError } from './errors.js';

export interface TokenStatus {
  found: boolean;
  /** Where the token was found, or where it was looked for. */
  location: string;
  problem?: string;
}

export interface AuthProvider {
  /** A valid OAuth2 access token; throws GarminAuthError. */
  accessToken(): Promise<string>;
  /** Whether a token file is present -- no network. */
  tokenStatus(): TokenStatus;
}

interface GarminAuthModule {
  loadTokens(): { oauth1: unknown; oauth2: unknown; source: string };
  getAccessToken(tokens: { oauth1: unknown; oauth2: unknown; source: string }): Promise<string>;
}

export function describeTokenSearch(env: NodeJS.ProcessEnv = process.env): string {
  if (env.GARMIN_TOKENS) return `GARMIN_TOKENS=${env.GARMIN_TOKENS}`;
  if (env.VAULT_ROOT) return `VAULT_ROOT=${env.VAULT_ROOT} (scripts/.garmin-tokens.json or .obsidian/plugins/garmin-health-sync/data.json)`;
  return 'neither GARMIN_TOKENS nor VAULT_ROOT is set (tools/lib/garmin-auth.mjs then guesses ../Jirkas_world next to the repo)';
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export async function createVaultAuth(garminAuthModulePath: string, env: NodeJS.ProcessEnv = process.env): Promise<AuthProvider> {
  const mod = (await import(pathToFileURL(garminAuthModulePath).href)) as GarminAuthModule;

  const status = (): TokenStatus => {
    try {
      return { found: true, location: mod.loadTokens().source };
    } catch (error) {
      return { found: false, location: describeTokenSearch(env), problem: message(error) };
    }
  };

  return {
    tokenStatus: status,
    async accessToken(): Promise<string> {
      let tokens: ReturnType<GarminAuthModule['loadTokens']>;
      try {
        tokens = mod.loadTokens();
      } catch (error) {
        throw new GarminAuthError(`no usable Garmin token file (${message(error).split('\n')[0]})`, describeTokenSearch(env));
      }
      try {
        return await mod.getAccessToken(tokens);
      } catch (error) {
        throw new GarminAuthError(`the OAuth1 -> OAuth2 token exchange failed (${message(error).split('\n')[0]})`, tokens.source);
      }
    },
  };
}
