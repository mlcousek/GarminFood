// check-badge-art.mjs
//
// Keeps Gamification's BadgeArtCatalog.swift and the SVG files under
// ios/BadgeArt in step (redesign-badge-art tasks 2.3). A Swift test cannot
// see the files and no Mac is here to notice a missing image, so CI's
// localization job runs this:
//
//   - every motif the catalog names has motifs/motif-<name>.svg;
//   - every family has frames/frame-<family>-<rarity>.svg for all five
//     rarities;
//   - no SVG file is unused.
//
// Also exports `readCatalog()` for build-badge-gallery.mjs, so the gallery
// resolves a badge exactly as the app does (one table, in Swift).
//
//   node tools/docs/check-badge-art.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const catalogFile = path.join(root, 'ios', 'Gamification', 'Sources', 'Gamification', 'BadgeArtCatalog.swift');
const artDir = path.join(root, 'ios', 'BadgeArt');
export const RARITY_NAMES = ['common', 'uncommon', 'rare', 'epic', 'legendary'];

function section(text, name) {
  const begin = text.indexOf(`// badge-art:${name}:begin`);
  const end = text.indexOf(`// badge-art:${name}:end`);
  if (begin < 0 || end < 0) throw new Error(`BadgeArtCatalog.swift: markers for "${name}" not found`);
  return text.slice(begin, end);
}

/** The catalog's three tables, parsed from the Swift source. */
export function readCatalog() {
  const text = fs.readFileSync(catalogFile, 'utf8');
  const families = text.match(/enum BadgeFamily[^{]*\{\s*case ([^\n]+)/)[1].split(',').map((s) => s.trim());
  const prefixes = Object.fromEntries([...section(text, 'prefixes').matchAll(/"([^"]+)":\s*\.(\w+)/g)].map((m) => [m[1], m[2]]));
  const categories = Object.fromEntries([...section(text, 'categories').matchAll(/\.(\w+):\s*\.(\w+)/g)].map((m) => [m[1], m[2]]));
  const motifs = Object.fromEntries([...section(text, 'motifs').matchAll(/"([^"]+)":\s*"([^"]+)"/g)].map((m) => [m[1], m[2]]));
  return { families, prefixes, categories, motifs };
}

/** The family for a badge, as `BadgeArtCatalog.family(id:category:)`. */
export function familyFor(catalog, id, category) {
  const dot = id.indexOf('.');
  if (dot >= 0 && catalog.prefixes[id.slice(0, dot + 1)]) return catalog.prefixes[id.slice(0, dot + 1)];
  return catalog.categories[category] ?? 'logging';
}

function main() {
  const catalog = readCatalog();
  const problems = [];
  const list = (folder) => new Set(fs.readdirSync(path.join(artDir, folder)).map((name) => name.replace(/\.svg$/, '')));
  const frames = list('frames');
  const motifs = list('motifs');

  for (const family of new Set([...Object.values(catalog.prefixes), ...Object.values(catalog.categories)])) {
    if (!catalog.families.includes(family)) problems.push(`family "${family}" is not a BadgeFamily case`);
  }
  const wantedFrames = new Set(catalog.families.flatMap((family) => RARITY_NAMES.map((rarity) => `frame-${family}-${rarity}`)));
  const wantedMotifs = new Set(Object.values(catalog.motifs).map((name) => `motif-${name}`));
  for (const name of wantedFrames) if (!frames.has(name)) problems.push(`missing frames/${name}.svg`);
  for (const name of wantedMotifs) if (!motifs.has(name)) problems.push(`missing motifs/${name}.svg`);
  for (const name of frames) if (!wantedFrames.has(name)) problems.push(`unused frames/${name}.svg`);
  for (const name of motifs) if (!wantedMotifs.has(name)) problems.push(`unused motifs/${name}.svg`);

  if (problems.length) {
    console.error(`check-badge-art: ${problems.length} problem(s)`);
    for (const problem of problems) console.error(`  ${problem}`);
    process.exit(1);
  }
  console.log(`check-badge-art: OK (${wantedFrames.size} frames, ${wantedMotifs.size} motifs, ${Object.keys(catalog.motifs).length} symbols)`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
