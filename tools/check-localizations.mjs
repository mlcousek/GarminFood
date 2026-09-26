#!/usr/bin/env node
/**
 * check-localizations.mjs — CI gate for GarminFood's translations.
 *
 * Why this exists: there is no Mac, so nobody can open Xcode's String
 * Catalog editor, which is what normally keeps catalogs complete and keys in
 * sync with code. Every catalog here is hand-authored JSON / .strings, and a
 * mistake (a missing Czech string, "%d" where Swift generates "%lld", a
 * Czech plural without its "few" form) does not fail any build — it just
 * silently shows English, or the wrong plural, on the fiancée's phone. This
 * script turns those mistakes into a red CI job.
 * See openspec/changes/add-localization/design.md D9 and
 * docs/localization-analysis.md §4.4.
 *
 * What it checks (blocking — exit code 1):
 *   - every ios/**\/*.xcstrings parses, sourceLanguage is "en";
 *   - every key has every TARGET language (LANGUAGES below), in state
 *     "translated" (a "new" / "needs_review" string fails), with the same
 *     format specifiers as the key (e.g. "Level %lld" -> "Úroveň %lld");
 *   - plural variations contain the language's required CLDR categories
 *     (Czech: one, few, other — "many" is fractions, optional);
 *   - package Resources/<lang>.lproj/Localizable.strings: parse, en and every
 *     target language list exactly the same keys, specifiers match;
 *     .stringsdict files (if any) exist for every language with the same keys
 *     and required plural categories;
 *   - every `String(localized: "…")` literal in the app/widget/Shared code is
 *     a key of that target's catalog, and every
 *     `String(localized: "…", bundle: .module)` literal in a package is a key
 *     of that package's .strings/.stringsdict (these are all hand-written, so
 *     a typo is otherwise invisible);
 *   - a key used in ios/Shared/ (compiled into BOTH the app and the widget)
 *     that is in one of the two catalogs is in the other as well;
 *   - no `n == 1 ? "day" : "days"`-style plural ternary in any Swift source
 *     (PLURAL_TERNARY_BASELINE lists the Wave 4 files still pending).
 *
 * Report-only (never fails): with --scan, SwiftUI string literals
 * (Text("…"), Label("…"), .navigationTitle("…"), …) in the app/widget that no
 * catalog key matches — the backlog of untranslated UI. Heuristic: the
 * authoritative, compiler-extracted list is the `xcodebuild
 * -exportLocalizations` artifact from CI's macOS job.
 *
 * Usage:
 *   node tools/check-localizations.mjs            # blocking checks
 *   node tools/check-localizations.mjs --scan     # + untranslated-UI report
 *   node tools/check-localizations.mjs --verbose  # + every literal, file:line
 *
 * Adding a language: add it to LANGUAGES (with its CLDR plural categories),
 * to every catalog and package lproj, and to CFBundleLocalizations in
 * ios/project.yml (design.md D8).
 *
 * Node >= 18, no dependencies.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const IOS = path.join(ROOT, 'ios');
const VERBOSE = process.argv.includes('--verbose');
const SCAN = process.argv.includes('--scan') || VERBOSE;

/** Target languages and the CLDR plural categories each must provide. */
const LANGUAGES = {
  cs: { requiredPlural: ['one', 'few', 'other'], allowedPlural: ['one', 'few', 'many', 'other'] },
};
const SOURCE = { code: 'en', requiredPlural: ['one', 'other'], allowedPlural: ['zero', 'one', 'other'] };

/** App-side targets: catalog + the Swift source folders compiled into it. */
const APP_TARGETS = [
  { name: 'GarminFood', catalog: 'GarminFood/Resources/Localizable.xcstrings', sources: ['GarminFood', 'Shared'] },
  { name: 'GarminFoodWidget', catalog: 'GarminFoodWidget/Resources/Localizable.xcstrings', sources: ['GarminFoodWidget', 'Shared'] },
];
/** SPM packages with .lproj resources (design.md D3). */
const PACKAGES = ['FoodLogCore', 'Gamification', 'GarminKit'];

const errors = [];
const notes = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);
const rel = (p) => path.relative(ROOT, p).split(path.sep).join('/');

// ---------------------------------------------------------------- helpers

function walk(dir, pred, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (['.build', 'build', 'DerivedData', 'node_modules'].includes(e.name) || e.name.endsWith('.xcodeproj')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, pred, out);
    else if (pred(p)) out.push(p);
  }
  return out;
}

const SPEC_RE = /%(?:(\d+)\$)?[-+ 0#']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA])/g;

/** The format specifiers of `s`, normalised and sorted, ignoring "%%". */
function specifiers(s) {
  const out = [];
  const cleaned = s.replace(/%%/g, '');
  for (const m of cleaned.matchAll(SPEC_RE)) out.push(`${m[2] ?? ''}${m[3]}`);
  return out.sort();
}
const sameSpecs = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const isSubset = (small, big) => {
  const pool = [...big];
  return small.every((x) => { const i = pool.indexOf(x); if (i < 0) return false; pool.splice(i, 1); return true; });
};

/** Converts a Swift string literal body (with `\(…)` spans) to a RegExp matching catalog keys. */
function literalToKeyRegex(parts) {
  const esc = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const spec = '%(?:\\d+\\$)?(?:lld|ld|d|lf|f|@|llu|lu|u)';
  return new RegExp('^' + parts.map((p) => (p.interp ? spec : esc(p.text))).join('') + '$');
}

/**
 * Reads a Swift "…" literal starting at src[i] === '"'. Returns
 * { parts: [{text}|{interp:true}], end } or null for multi-line/raw literals.
 * Handles nested strings inside \( … ).
 */
function readSwiftString(src, i) {
  if (src[i] !== '"' || src.startsWith('"""', i)) return null;
  const parts = [];
  let text = '';
  let j = i + 1;
  while (j < src.length) {
    const c = src[j];
    if (c === '\n') return null;
    if (c === '"') { if (text) parts.push({ text }); return { parts, end: j + 1 }; }
    if (c === '\\') {
      const n = src[j + 1];
      if (n === '(') {
        if (text) { parts.push({ text }); text = ''; }
        let depth = 1; j += 2;
        while (j < src.length && depth > 0) {
          if (src[j] === '"') { const inner = readSwiftString(src, j); if (!inner) return null; j = inner.end; continue; }
          if (src[j] === '(') depth++;
          else if (src[j] === ')') depth--;
          j++;
        }
        parts.push({ interp: true });
        continue;
      }
      const map = { n: '\n', t: '\t', '"': '"', "'": "'", '\\': '\\', '0': '\0', r: '\r' };
      text += map[n] ?? n; j += 2; continue;
    }
    text += c; j++;
  }
  return null;
}

/** Every `String(localized: "…" …)` literal in `src`, with whether it passes `bundle:`. */
function localizedCalls(src) {
  const out = [];
  const re = /String\(\s*localized:\s*/g;
  let m;
  while ((m = re.exec(src))) {
    const lit = readSwiftString(src, re.lastIndex);
    if (!lit) continue;
    // Look at the rest of the call (up to the matching ')') for bundle:/defaultValue:.
    let depth = 1, k = lit.end;
    while (k < src.length && depth > 0) { if (src[k] === '(') depth++; else if (src[k] === ')') depth--; k++; }
    // With `defaultValue:` (a semantic key, design.md D4) the literal is
    // still the key, so both forms are checked the same way.
    const rest = src.slice(lit.end, k);
    out.push({ parts: lit.parts, line: src.slice(0, m.index).split('\n').length, module: /bundle:\s*\.module/.test(rest) });
  }
  return out;
}

const stripComments = (src) => src.replace(/\/\*[\s\S]*?\*\//g, (s) => s.replace(/[^\n]/g, ' ')).replace(/(^|[^:"\\])\/\/[^\n]*/g, '$1');

// ------------------------------------------------------------- .xcstrings

/** Yields every stringUnit leaf under a localization, with its variation path. */
function* units(loc, pathSoFar = []) {
  if (!loc || typeof loc !== 'object') return;
  if (loc.stringUnit) yield { unit: loc.stringUnit, path: pathSoFar };
  if (loc.variations) {
    for (const [kind, byCase] of Object.entries(loc.variations)) {
      for (const [cse, sub] of Object.entries(byCase)) yield* units(sub, [...pathSoFar, `${kind}.${cse}`]);
    }
  }
}

function checkPluralSet(where, loc, lang) {
  const plural = loc?.variations?.plural;
  if (!plural) return;
  const cats = Object.keys(plural);
  for (const req of lang.requiredPlural) if (!cats.includes(req)) err(where, `plural is missing the "${req}" form (has: ${cats.join(', ')})`);
  for (const c of cats) if (!lang.allowedPlural.includes(c)) err(where, `plural has a "${c}" form, which this language doesn't use`);
}

function checkCatalog(file) {
  const where = rel(file);
  let json;
  try { json = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { err(where, `invalid JSON: ${e.message}`); return null; }
  if (json.sourceLanguage !== SOURCE.code) err(where, `sourceLanguage must be "${SOURCE.code}", is "${json.sourceLanguage}"`);
  if (!json.strings || typeof json.strings !== 'object') { err(where, 'no "strings" object'); return null; }
  for (const [key, entry] of Object.entries(json.strings)) {
    if (entry.shouldTranslate === false) continue;
    const keyWhere = `${where} [${JSON.stringify(key)}]`;
    const keySpecs = specifiers(key);
    const locs = entry.localizations ?? {};
    if (entry.substitutions || Object.values(locs).some((l) => l?.substitutions)) {
      notes.push(`${keyWhere}: uses substitutions — specifier parity not checked`);
    }
    // Source language (optional; needed for English plurals).
    if (locs[SOURCE.code]) {
      checkPluralSet(`${keyWhere} en`, locs[SOURCE.code], SOURCE);
      for (const { unit, path: p } of units(locs[SOURCE.code])) {
        const s = specifiers(unit.value ?? '');
        if (!(sameSpecs(s, keySpecs) || (p.some((x) => /plural\.(one|zero)/.test(x)) && isSubset(s, keySpecs)))) {
          err(`${keyWhere} en ${p.join('/')}`, `specifiers ${JSON.stringify(s)} differ from the key's ${JSON.stringify(keySpecs)}`);
        }
      }
    }
    for (const [code, lang] of Object.entries(LANGUAGES)) {
      const loc = locs[code];
      if (!loc) { err(keyWhere, `no "${code}" translation`); continue; }
      checkPluralSet(`${keyWhere} ${code}`, loc, lang);
      let any = false;
      for (const { unit, path: p } of units(loc)) {
        any = true;
        const at = `${keyWhere} ${code}${p.length ? ' ' + p.join('/') : ''}`;
        if (unit.state !== 'translated') err(at, `state is "${unit.state}", not "translated"`);
        if (typeof unit.value !== 'string' || !unit.value.trim()) { err(at, 'empty value'); continue; }
        if (entry.substitutions || loc.substitutions) continue;
        const s = specifiers(unit.value);
        const lenient = p.some((x) => /plural\.(one|zero)/.test(x)) && isSubset(s, keySpecs);
        if (!sameSpecs(s, keySpecs) && !lenient) err(at, `specifiers ${JSON.stringify(s)} differ from the key's ${JSON.stringify(keySpecs)}`);
      }
      if (!any) err(keyWhere, `"${code}" has no stringUnit`);
    }
  }
  return new Set(Object.keys(json.strings));
}

// -------------------------------------------------- .strings / .stringsdict

/** Parses an old-style .strings file: "key" = "value"; with comments. */
function parseStrings(text, where) {
  const map = new Map();
  let i = 0;
  const skip = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('/*', i)) { const e = text.indexOf('*/', i + 2); if (e < 0) throw new Error('unterminated comment'); i = e + 2; continue; }
      if (text.startsWith('//', i)) { const e = text.indexOf('\n', i); i = e < 0 ? text.length : e + 1; continue; }
      return;
    }
  };
  const str = () => {
    if (text[i] !== '"') throw new Error(`expected '"' at offset ${i}`);
    let s = ''; i++;
    while (i < text.length && text[i] !== '"') {
      if (text[i] === '\\') { const n = text[i + 1]; s += { n: '\n', t: '\t', '"': '"', '\\': '\\', r: '\r' }[n] ?? n; i += 2; }
      else s += text[i++];
    }
    if (text[i] !== '"') throw new Error('unterminated string');
    i++; return s;
  };
  try {
    if (text.charCodeAt(0) === 0xfeff) i = 1;
    for (;;) {
      skip();
      if (i >= text.length) break;
      const k = str(); skip();
      if (text[i] !== '=') throw new Error(`expected '=' after ${JSON.stringify(k)}`);
      i++; skip();
      const v = str(); skip();
      if (text[i] !== ';') throw new Error(`expected ';' after value of ${JSON.stringify(k)}`);
      i++;
      if (map.has(k)) err(where, `duplicate key ${JSON.stringify(k)}`);
      map.set(k, v);
    }
  } catch (e) { err(where, `parse error: ${e.message}`); }
  return map;
}

/** Minimal XML plist parser (dict/array/key/string/integer/real/true/false). */
function parsePlist(text, where) {
  const tokens = [...text.matchAll(/<(\/?)(dict|array|key|string|integer|real|true|false)(\s*\/)?>|([^<]+)/g)];
  let i = 0;
  const unesc = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
  const value = () => {
    while (i < tokens.length && tokens[i][4] !== undefined) i++;
    const t = tokens[i++];
    if (!t) throw new Error('unexpected end');
    const [, close, tag, selfClose] = t;
    if (close) throw new Error(`unexpected </${tag}>`);
    if (tag === 'true' || tag === 'false') return tag === 'true';
    if (selfClose) return tag === 'dict' ? {} : tag === 'array' ? [] : '';
    if (tag === 'dict') {
      const o = {};
      for (;;) {
        while (i < tokens.length && tokens[i][4] !== undefined) i++;
        if (tokens[i][1] && tokens[i][2] === 'dict') { i++; return o; }
        if (tokens[i][2] !== 'key') throw new Error('expected <key>');
        i++; const k = unesc(tokens[i][4] ?? ''); if (tokens[i][4] !== undefined) i++; i++; // text, </key>
        o[k] = value();
      }
    }
    if (tag === 'array') {
      const a = [];
      for (;;) {
        while (i < tokens.length && tokens[i][4] !== undefined) i++;
        if (tokens[i][1] && tokens[i][2] === 'array') { i++; return a; }
        a.push(value());
      }
    }
    let s = '';
    if (tokens[i] && tokens[i][4] !== undefined) s = unesc(tokens[i++][4]);
    i++; // closing tag
    return tag === 'integer' || tag === 'real' ? Number(s) : s;
  };
  try {
    const body = text.slice(text.indexOf('<plist'));
    const start = tokens.findIndex((t) => t.index >= text.length - body.length && t[2] === 'dict' && !t[1]);
    i = start; return value();
  } catch (e) { err(where, `plist parse error: ${e.message}`); return {}; }
}

function checkStringsdict(dict, where, lang) {
  for (const [key, entry] of Object.entries(dict)) {
    const fmt = entry?.NSStringLocalizedFormatKey;
    if (typeof fmt !== 'string') { err(where, `[${JSON.stringify(key)}] has no NSStringLocalizedFormatKey`); continue; }
    for (const [name, v] of Object.entries(entry)) {
      if (name === 'NSStringLocalizedFormatKey' || v?.NSStringFormatSpecTypeKey !== 'NSStringPluralRuleType') continue;
      const cats = Object.keys(v).filter((c) => ['zero', 'one', 'two', 'few', 'many', 'other'].includes(c));
      for (const req of lang.requiredPlural) if (!cats.includes(req)) err(where, `[${JSON.stringify(key)}] variable "${name}" is missing the "${req}" form`);
    }
  }
}

function checkPackage(pkg) {
  const res = path.join(IOS, pkg, 'Sources', pkg, 'Resources');
  const lproj = (code) => path.join(res, `${code}.lproj`);
  const codes = [SOURCE.code, ...Object.keys(LANGUAGES)];
  const tables = {};
  const anyPresent = codes.some((c) => fs.existsSync(lproj(c)));
  if (!anyPresent) return null;
  for (const code of codes) {
    const dir = lproj(code);
    if (!fs.existsSync(dir)) { err(rel(res), `missing ${code}.lproj (every package language needs one — see design.md D3)`); continue; }
    const sPath = path.join(dir, 'Localizable.strings');
    const dPath = path.join(dir, 'Localizable.stringsdict');
    const strings = fs.existsSync(sPath) ? parseStrings(fs.readFileSync(sPath, 'utf8'), rel(sPath)) : new Map();
    const dict = fs.existsSync(dPath) ? parsePlist(fs.readFileSync(dPath, 'utf8'), rel(dPath)) : {};
    if (fs.existsSync(dPath)) checkStringsdict(dict, rel(dPath), code === SOURCE.code ? SOURCE : LANGUAGES[code]);
    for (const [k, v] of strings) {
      if (!v.trim()) err(rel(sPath), `[${JSON.stringify(k)}] empty value`);
      if (!sameSpecs(specifiers(v), specifiers(k))) err(rel(sPath), `[${JSON.stringify(k)}] specifiers ${JSON.stringify(specifiers(v))} differ from the key's ${JSON.stringify(specifiers(k))}`);
    }
    tables[code] = { strings: new Set(strings.keys()), dict: new Set(Object.keys(dict)) };
  }
  const base = tables[SOURCE.code];
  if (base) {
    for (const code of Object.keys(LANGUAGES)) {
      const t = tables[code]; if (!t) continue;
      for (const kind of ['strings', 'dict']) {
        for (const k of base[kind]) if (!t[kind].has(k)) err(`${rel(lproj(code))}`, `missing ${kind === 'dict' ? '.stringsdict' : '.strings'} key ${JSON.stringify(k)} (present in en)`);
        for (const k of t[kind]) if (!base[kind].has(k)) err(`${rel(lproj(SOURCE.code))}`, `missing ${kind === 'dict' ? '.stringsdict' : '.strings'} key ${JSON.stringify(k)} (present in ${code}) — en must list every key`);
      }
    }
  }
  return base ? new Set([...base.strings, ...base.dict]) : new Set();
}

// ------------------------------------------------------------------- run

const catalogKeys = {};
for (const file of walk(IOS, (p) => p.endsWith('.xcstrings'))) {
  const keys = checkCatalog(file);
  if (keys) catalogKeys[rel(file)] = keys;
}
const matches = (keys, parts) => {
  const re = literalToKeyRegex(parts);
  for (const k of keys) if (re.test(k)) return true;
  return false;
};
const literalText = (parts) => parts.map((p) => (p.interp ? '\\(…)' : p.text)).join('');

// App/widget: String(localized:) literals must be catalog keys.
for (const t of APP_TARGETS) {
  const catalog = `ios/${t.catalog}`;
  const keys = catalogKeys[catalog];
  if (!keys) { err(catalog, 'catalog missing'); continue; }
  for (const dir of t.sources) {
    for (const f of walk(path.join(IOS, dir), (p) => p.endsWith('.swift'))) {
      const src = stripComments(fs.readFileSync(f, 'utf8'));
      for (const call of localizedCalls(src)) {
        if (call.module) continue;
        if (!matches(keys, call.parts)) err(`${rel(f)}:${call.line}`, `String(localized: "${literalText(call.parts)}") has no key in ${catalog}`);
      }
    }
  }
}

// Shared/ keys present in one app-side catalog must be in the other.
{
  const [app, widget] = APP_TARGETS.map((t) => catalogKeys[`ios/${t.catalog}`] ?? new Set());
  const sharedLiterals = [];
  for (const f of walk(path.join(IOS, 'Shared'), (p) => p.endsWith('.swift'))) {
    const src = stripComments(fs.readFileSync(f, 'utf8'));
    for (let i = src.indexOf('"'); i >= 0; ) {
      const lit = readSwiftString(src, i);
      if (lit) { sharedLiterals.push({ parts: lit.parts, file: rel(f) }); i = src.indexOf('"', lit.end); }
      else i = src.indexOf('"', i + 1);
    }
  }
  for (const l of sharedLiterals) {
    const inApp = matches(app, l.parts), inWidget = matches(widget, l.parts);
    if (inApp !== inWidget) err(l.file, `"${literalText(l.parts)}" is compiled into both targets but only in the ${inApp ? 'app' : 'widget'} catalog`);
  }
}

// Packages: String(localized:bundle: .module) literals must be keys.
for (const pkg of PACKAGES) {
  const keys = checkPackage(pkg);
  for (const f of walk(path.join(IOS, pkg, 'Sources'), (p) => p.endsWith('.swift'))) {
    const src = stripComments(fs.readFileSync(f, 'utf8'));
    for (const call of localizedCalls(src)) {
      if (!call.module) { err(`${rel(f)}:${call.line}`, 'package String(localized:) must pass `bundle: .module` (design.md D3)'); continue; }
      if (!keys) { err(`${rel(f)}:${call.line}`, `${pkg} has no Resources/<lang>.lproj yet`); continue; }
      if (!matches(keys, call.parts)) err(`${rel(f)}:${call.line}`, `"${literalText(call.parts)}" has no key in ${pkg}'s Localizable.strings(dict)`);
    }
  }
}

// Plural ternaries (design.md D5, task 6.2): `n == 1 ? "day" : "days"` or
// `"food\(n == 1 ? "" : "s")"` can't express Czech one/few/many/other --
// counts use catalog plural variations / .stringsdict instead. A line is
// flagged when a `== 1 ?` / `!= 1 ?` ternary picks between string literals
// that are text (contain a space) or English plural suffixes ("", "s",
// "y", "ies", "es"); a ternary choosing SF Symbol names ("key.fill") is not
// text and passes. Files listed in PLURAL_TERNARY_BASELINE still have such
// lines and are translated in Wave 4 (gamification copy, owned by other
// in-flight changes); they are reported, not failed. Remove an entry once
// its file is clean (the checker says so).
const PLURAL_TERNARY_BASELINE = new Set([
  // Empty since Wave 4 (add-localization 4.1): every file is clean, so any
  // new plural ternary fails the job.
]);
{
  const TERNARY = /[!=]=\s*1\s*\?/;
  const SUFFIXES = new Set(['', 's', 'y', 'ies', 'es']);
  const flagged = new Map();
  for (const f of walk(IOS, (p) => p.endsWith('.swift') && !/[\\/]Tests[\\/]/.test(p))) {
    const lines = stripComments(fs.readFileSync(f, 'utf8')).split('\n');
    lines.forEach((line, i) => {
      const m = TERNARY.exec(line);
      if (!m) return;
      const tail = line.slice(m.index);
      const literals = [...tail.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((x) => x[1]);
      // "day" / "days", "entry" / "entries": one literal is the other plus
      // an English plural ending.
      const singularPlural = literals.some((a) => /[A-Za-z]/.test(a) && literals.some((b) =>
        b !== a && (b.startsWith(a) && SUFFIXES.has(b.slice(a.length)) || (a.endsWith('y') && b === `${a.slice(0, -1)}ies`))));
      if (singularPlural || literals.some((s) => s.includes(' ') || SUFFIXES.has(s))) {
        const r = rel(f);
        if (!flagged.has(r)) flagged.set(r, []);
        flagged.get(r).push(i + 1);
      }
    });
  }
  for (const [file, lineNos] of flagged) {
    const where = `${file}:${lineNos.join(',')}`;
    if (PLURAL_TERNARY_BASELINE.has(file)) notes.push(`${where}: plural ternary (baseline, Wave 4)`);
    else err(where, 'plural chosen with an `== 1 ?` ternary -- use a catalog plural variation / .stringsdict (design.md D5)');
  }
  for (const file of PLURAL_TERNARY_BASELINE) {
    if (!flagged.has(file)) notes.push(`${file}: no plural ternaries left -- remove it from PLURAL_TERNARY_BASELINE`);
  }
}

// --scan: SwiftUI literals with no catalog key (report only).
if (SCAN) {
  const UI = /\b(Text|Label|Button|navigationTitle|Section|Toggle|TextField|Picker|alert|confirmationDialog|LabeledContent|ContentUnavailableView|Stepper|DatePicker|NavigationLink|Menu|accessibilityLabel|accessibilityHint|accessibilityValue|help|configurationDisplayName|description|displayName)\(\s*(?=")/g;
  for (const t of APP_TARGETS) {
    const keys = catalogKeys[`ios/${t.catalog}`] ?? new Set();
    const perFile = [];
    let total = 0;
    for (const dir of t.sources) {
      for (const f of walk(path.join(IOS, dir), (p) => p.endsWith('.swift'))) {
        const src = stripComments(fs.readFileSync(f, 'utf8'));
        let n = 0; let m;
        UI.lastIndex = 0;
        while ((m = UI.exec(src))) {
          const lit = readSwiftString(src, UI.lastIndex);
          if (!lit || !lit.parts.some((p) => p.text && /[A-Za-z]/.test(p.text))) continue;
          if (!matches(keys, lit.parts)) {
            n++;
            if (VERBOSE) console.log(`    ${rel(f)}:${src.slice(0, m.index).split('\n').length}  ${m[1]}("${literalText(lit.parts)}")`);
          }
        }
        if (n) { perFile.push([rel(f), n]); total += n; }
      }
    }
    console.log(`\n[scan] ${t.name}: ~${total} SwiftUI literals without a catalog key`);
    for (const [f, n] of perFile.sort((a, b) => b[1] - a[1]).slice(0, 25)) console.log(`  ${String(n).padStart(4)}  ${f}`);
  }
}

for (const n of notes) console.log(`note: ${n}`);
const summary = Object.entries(catalogKeys).map(([f, k]) => `${f} (${k.size})`).join(', ');
if (errors.length) {
  console.error(`\nLocalization check FAILED — ${errors.length} problem(s):`);
  for (const e of errors) console.error(`  - ${e}`);
  console.error('\nSee openspec/changes/add-localization/design.md (D3, D4, D5, D9).');
  process.exit(1);
}
console.log(`Localization check passed. Catalogs: ${summary || 'none'}. Languages: ${SOURCE.code} + ${Object.keys(LANGUAGES).join(', ')}.`);
