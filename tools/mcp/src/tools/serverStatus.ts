// serverStatus.ts -- server_status: what works right now, and why not.
//
// Why it exists: the server has several independent ways to be half-set-up
// (no token, an expired token, no bridge folder, a route missing from the
// registry), and each must degrade only its own tools (spec mcp-server
// "configured by file paths"). This tool reports all of them in one place
// without touching the network, and lists the actions that stay
// phone-only by design, so Claude can say "do that on the phone" instead
// of searching for a tool that will never exist.

import { existsSync, statSync } from 'node:fs';
import { defineTool } from './types.js';

export const SERVER_VERSION = '0.1.0';

/** Design feature inventory, actions marked "not offered" (D6/D8). */
export const PHONE_ONLY_ACTIONS = [
  'Garmin sign-in and sign-out',
  'Choosing or switching the data mode (Garmin / standalone), incl. "copy the last 90 days from Garmin"',
  'Restoring a backup or importing a backup file',
  'Granting notification permission',
  'Viewing, copying or clearing the diagnostics log',
  'Scanning a barcode with the camera (type the code into food_lookupBarcode instead)',
  'Changing the app icon',
  'Changing the language (follows iOS)',
  'Retrying, cancelling or discarding items in the sync queue',
  'Dismissing a celebration moment',
  'The goal calculator (Claude can do that arithmetic directly)',
];

function bridgeState(dir: string | null) {
  if (!dir) {
    return {
      configured: false,
      note:
        'PC bridge not configured: set GARMINFOOD_BRIDGE_DIR to the synced folder (e.g. C:\\Users\\<you>\\iCloudDrive\\GarminFood Bridge). ' +
        'Bridge tools (phone-only data, and food/weight/water writes through the phone) arrive in add-mcp-server wave 5.',
    };
  }
  let exists = false;
  try {
    exists = existsSync(dir) && statSync(dir).isDirectory();
  } catch {
    exists = false;
  }
  return {
    configured: true,
    path: dir,
    folderExists: exists,
    note: exists
      ? 'Folder found. Bridge tools arrive in add-mcp-server wave 5; nothing reads or writes it yet.'
      : 'GARMINFOOD_BRIDGE_DIR is set but that folder does not exist on this PC (is iCloud for Windows syncing?).',
  };
}

export const serverStatus = defineTool({
  name: 'server_status',
  title: 'GarminFood MCP server status',
  summary:
    'Reports what this server can do right now: whether a Garmin token file was found (checked without network -- ' +
    'an expired token only shows on the first Garmin call), the bridge folder setting, which tools are offered and ' +
    'which are not (and why, e.g. a route missing from docs/garmin-routes.json), experimental-write flags, and the ' +
    'actions that can only be done on the phone. Call it first when something does not work.',
  acts: 'This PC only (reads local configuration; no network, no phone).',
  garminOperations: [],
  inputShape: {},
  async run(_args, ctx) {
    const token = ctx.auth.tokenStatus();
    return {
      server: { name: 'garminfood', version: SERVER_VERSION },
      garmin: {
        tokenFound: token.found,
        tokenLocation: token.location,
        problem: token.problem,
        note: token.found
          ? 'Token file found. Whether it is still accepted shows on the first Garmin call.'
          : 'Garmin tools will fail with "Garmin sign-in needed on this PC" until a token file is available.',
      },
      bridge: bridgeState(ctx.config.bridgeDir),
      registry: { path: ctx.registry.sourcePath, lastFullSweep: ctx.registry.lastFullSweep },
      tools: ctx.toolReport,
      experimentalWrites: {
        requested: ctx.config.experimentalWrites,
        note: 'No experimental Garmin write tool exists yet (add-mcp-server wave 7); GARMINFOOD_MCP_EXPERIMENTAL_WRITES has no effect.',
      },
      writes:
        'None yet. Food, weight and water written from the PC will go through the phone (owner decision), with the bridge. ' +
        'The separate generic "garmin" MCP server can write to Garmin directly, but its entries do not count toward the ' +
        "app's streak or XP.",
      phoneOnlyActions: PHONE_ONLY_ACTIONS,
    };
  },
});
