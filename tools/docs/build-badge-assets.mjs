// build-badge-assets.mjs
//
// Copies the badge art (ios/BadgeArt/*.svg) into the app's asset catalog
// as vector imagesets (redesign-badge-art tasks 3.1, design D3):
//
//   ios/GarminFood/Assets.xcassets/BadgeArt/badge-frame-<family>-<rarity>.imageset
//   ios/GarminFood/Assets.xcassets/BadgeArt/badge-motif-<name>.imageset
//
// The names are the ones Gamification's BadgeArtCatalog returns
// (`frameAssetName`, `motifAssetName`). Each imageset keeps its vector data
// ("preserves-vector-representation") so a badge is sharp at 120 pt, and is
// "original" rendering; the app asks for a template image itself when it
// draws a locked badge's silhouette.
//
// The output is committed. Re-run after changing the art:
//
//   node tools/docs/write-badge-art.mjs && node tools/docs/build-badge-assets.mjs
//
// `--check` writes nothing and fails when the catalog is out of date (CI).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const artDir = path.join(root, 'ios', 'BadgeArt');
const outDir = path.join(root, 'ios', 'GarminFood', 'Assets.xcassets', 'BadgeArt');
const checkOnly = process.argv.includes('--check');

function contents(filename) {
  return JSON.stringify({
    images: [{ filename, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'original' },
  }, null, 2) + '\n';
}

/** relative path -> text, for everything the folder should hold. */
const wanted = new Map();
for (const folder of ['frames', 'motifs']) {
  for (const name of fs.readdirSync(path.join(artDir, folder)).sort()) {
    if (!name.endsWith('.svg')) continue;
    const set = `badge-${name.replace(/\.svg$/, '')}.imageset`;
    // LF always, whatever the checkout's line endings: the output is stable.
    wanted.set(`${set}/${name}`, fs.readFileSync(path.join(artDir, folder, name), 'utf8').replace(/\r\n/g, '\n'));
    wanted.set(`${set}/Contents.json`, contents(name));
  }
}

if (checkOnly) {
  const problems = [];
  for (const [relative, text] of wanted) {
    const file = path.join(outDir, relative);
    if (!fs.existsSync(file)) problems.push(`missing ${relative}`);
    else if (fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') !== text) problems.push(`out of date ${relative}`);
  }
  const sets = new Set([...wanted.keys()].map((relative) => relative.split('/')[0]));
  if (fs.existsSync(outDir)) {
    for (const name of fs.readdirSync(outDir)) if (!sets.has(name)) problems.push(`unexpected ${name}`);
  }
  if (problems.length) {
    console.error(`build-badge-assets: ${problems.length} problem(s); run node tools/docs/build-badge-assets.mjs`);
    for (const problem of problems.slice(0, 20)) console.error(`  ${problem}`);
    process.exit(1);
  }
  console.log(`build-badge-assets: OK (${sets.size} imagesets)`);
} else {
  fs.rmSync(outDir, { recursive: true, force: true });
  for (const [relative, text] of wanted) {
    const file = path.join(outDir, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
  console.log(`build-badge-assets: wrote ${wanted.size / 2} imagesets to ${path.relative(root, outDir)}`);
}
