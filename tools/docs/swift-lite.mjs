// swift-lite.mjs
//
// A deliberately tiny, dependency-free reader for the handful of Swift
// shapes the GarminFood catalogs are written in: balanced call expressions
// (`BingoTask(id: "...", title: String(localized: "..."), ...)`), labelled
// and positional arguments, string literals with `\(...)` interpolation,
// array literals, `static let` constants and `.strings` / `.stringsdict` /
// `.xcstrings` tables. It is NOT a Swift parser -- it only has to be good
// enough for the literal tables extract-guide-data.mjs reads, and every
// catalog that is built by code instead of literals is mirrored there
// explicitly (and marked so in the output).
//
// Used by: tools/docs/extract-guide-data.mjs.

import { readFileSync } from 'node:fs';

export function read(path) {
  let text = readFileSync(path, 'utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  return text.replace(/\r\n/g, '\n');
}

/** Index just past the matching close bracket for the open bracket at `open`. */
export function matchBracket(src, open) {
  const pairs = { '(': ')', '[': ']', '{': '}' };
  const stack = [];
  let i = open;
  while (i < src.length) {
    const c = src[i];
    if (c === '"') { i = skipString(src, i); continue; }
    if (c === '/' && src[i + 1] === '/') { const e = src.indexOf('\n', i); i = e < 0 ? src.length : e; continue; }
    if (c === '/' && src[i + 1] === '*') { const e = src.indexOf('*/', i + 2); i = e < 0 ? src.length : e + 2; continue; }
    if (pairs[c]) stack.push(pairs[c]);
    else if (c === ')' || c === ']' || c === '}') {
      if (stack.pop() !== c) throw new Error(`bracket mismatch at ${i}: ${src.slice(Math.max(0, i - 80), i + 20)}`);
      if (stack.length === 0) return i + 1;
    }
    i++;
  }
  throw new Error('unbalanced bracket from ' + open);
}

/** Index just past the string literal starting at `start` (a `"`). */
export function skipString(src, start) {
  if (src.startsWith('"""', start)) {
    const e = src.indexOf('"""', start + 3);
    return e + 3;
  }
  let i = start + 1;
  while (i < src.length) {
    const c = src[i];
    if (c === '\\') {
      if (src[i + 1] === '(') { i = matchBracket(src, i + 1); continue; }
      i += 2; continue;
    }
    if (c === '"') return i + 1;
    i++;
  }
  throw new Error('unterminated string at ' + start);
}

/** Every call `Name(` ... `)` in `src` (optionally from `from` to `to`), as {start, end, inner}. */
export function findCalls(src, name, from = 0, to = src.length) {
  const out = [];
  const re = new RegExp(`(?<![\\w.])${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\(`, 'g');
  re.lastIndex = from;
  let m;
  while ((m = re.exec(src)) && m.index < to) {
    const open = m.index + m[0].length - 1;
    const end = matchBracket(src, open);
    out.push({ start: m.index, end, inner: src.slice(open + 1, end - 1) });
    re.lastIndex = end;
  }
  return out;
}

/** Splits an argument list at top-level commas. */
export function splitTop(inner) {
  const parts = [];
  let depth = 0, i = 0, last = 0;
  while (i < inner.length) {
    const c = inner[i];
    if (c === '"') { i = skipString(inner, i); continue; }
    if (c === '/' && inner[i + 1] === '/') { const e = inner.indexOf('\n', i); i = e < 0 ? inner.length : e; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (c === ',' && depth === 0) { parts.push(inner.slice(last, i)); last = i + 1; }
    i++;
  }
  const tail = inner.slice(last);
  if (tail.trim()) parts.push(tail);
  return parts.map((p) => p.replace(/\/\/[^\n]*$/gm, '').trim()).filter(Boolean);
}

/** [{label, value}] for a call's inner text. */
export function args(inner) {
  return splitTop(inner).map((p) => {
    const m = /^([A-Za-z_]\w*)\s*:\s*([\s\S]*)$/.exec(p);
    // Guard against `.x ? a : b` style values: a label never starts with '.' or '"'.
    if (m && !p.startsWith('.') && !p.startsWith('"')) return { label: m[1], value: m[2].trim() };
    return { label: null, value: p.trim() };
  });
}

export function argMap(inner) {
  const list = args(inner);
  const map = {};
  list.forEach((a, i) => { map[a.label ?? `#${i}`] = a.value; });
  return map;
}

/** Decodes one Swift string literal (value text starting with `"`), keeping interpolations as `\(expr)`. */
export function stringLiteral(text) {
  text = text.trim();
  if (!text.startsWith('"')) return null;
  const end = skipString(text, 0);
  const body = text.slice(1, end - 1);
  let out = '';
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c !== '\\') { out += c; continue; }
    const n = body[i + 1];
    if (n === '(') { const e = matchBracket(body, i + 1); out += '\\(' + body.slice(i + 2, e - 1) + ')'; i = e - 1; continue; }
    if (n === 'u' && body[i + 2] === '{') { const e = body.indexOf('}', i); out += String.fromCodePoint(parseInt(body.slice(i + 3, e), 16)); i = e; continue; }
    out += { n: '\n', t: '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0' }[n] ?? n;
    i++;
  }
  return out;
}

/** An array literal's string / number elements. */
export function arrayLiteral(text) {
  text = text.trim();
  if (!text.startsWith('[')) return null;
  const inner = text.slice(1, matchBracket(text, 0) - 1);
  return splitTop(inner).map(literalValue);
}

export function literalValue(v) {
  v = v.trim();
  if (v.startsWith('"')) return stringLiteral(v);
  if (/^-?[\d_]+(\.\d+)?$/.test(v)) return Number(v.replace(/_/g, ''));
  if (v.startsWith('[')) return arrayLiteral(v);
  return v;
}

/** `static let name[: T] = value` constants (single-line values). */
export function staticLets(src) {
  const map = {};
  for (const m of src.matchAll(/static\s+let\s+(\w+)\s*(?::\s*[^=\n]+)?=\s*([^\n]+)/g)) {
    const raw = m[2].trim();
    let value = raw;
    if (raw.startsWith('"')) value = stringLiteral(raw);
    else if (/^-?[\d_]+(\.\d+)?$/.test(raw)) value = Number(raw.replace(/_/g, ''));
    else if (raw.startsWith('[') && raw.endsWith(']')) { try { value = arrayLiteral(raw); } catch { value = raw; } }
    map[m[1]] = value;
  }
  return map;
}

/** The text of a declaration block `static let/var <name>` up to its matching brace/bracket/paren end. */
export function declBlock(src, name) {
  const re = new RegExp(`static\\s+(?:let|var)\\s+${name}\\b[^=\\{]*(=|\\{)`);
  const m = re.exec(src);
  if (!m) throw new Error('declaration not found: ' + name);
  let i = m.index + m[0].length;
  if (m[1] === '{') return src.slice(i - 1, matchBracket(src, i - 1));
  while (/\s/.test(src[i])) i++;
  // `= [ ... ]`, `= { ... }()`, `= Foo(...)`, `= a + b` (until newline at depth 0)
  if ('[{('.includes(src[i])) return src.slice(i, matchBracket(src, i));
  const call = /^[\w.]+\(/.exec(src.slice(i));
  if (call) return src.slice(i, matchBracket(src, i + call[0].length - 1));
  const e = src.indexOf('\n', i);
  return src.slice(i, e);
}

// ---------------------------------------------------------------- tables

export function parseStrings(text) {
  const map = new Map();
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  let i = 0;
  const skip = () => {
    for (;;) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (text.startsWith('/*', i)) { i = text.indexOf('*/', i + 2) + 2; continue; }
      if (text.startsWith('//', i)) { const e = text.indexOf('\n', i); i = e < 0 ? text.length : e + 1; continue; }
      return;
    }
  };
  const str = () => {
    let s = ''; i++;
    while (i < text.length && text[i] !== '"') {
      if (text[i] === '\\') { const n = text[i + 1]; s += { n: '\n', t: '\t', '"': '"', '\\': '\\', r: '\r' }[n] ?? n; i += 2; } else s += text[i++];
    }
    i++; return s;
  };
  for (;;) {
    skip(); if (i >= text.length) break;
    const k = str(); skip(); i++; /* = */ skip(); const v = str(); skip(); i++; /* ; */
    map.set(k, v);
  }
  return map;
}

/** `.stringsdict`: key -> {one, few, many, other} of its first variable (best effort). */
export function parseStringsDict(text) {
  const map = new Map();
  for (const m of text.matchAll(/<key>([^<]+)<\/key>\s*<dict>([\s\S]*?)<\/dict>\s*<\/dict>/g)) {
    const forms = {};
    for (const f of m[2].matchAll(/<key>(zero|one|two|few|many|other)<\/key>\s*<string>([^<]*)<\/string>/g)) forms[f[1]] = f[2];
    const fmt = /<key>NSStringLocalizedFormatKey<\/key>\s*<string>([^<]*)<\/string>/.exec(m[2]);
    if (Object.keys(forms).length) map.set(m[1], { format: fmt?.[1], ...forms });
  }
  return map;
}

/** `.xcstrings` (JSON): key -> { en, cs, state } */
export function parseXcstrings(text) {
  const json = JSON.parse(text);
  const map = new Map();
  for (const [key, entry] of Object.entries(json.strings ?? {})) {
    const loc = entry.localizations ?? {};
    const val = (lang) => loc[lang]?.stringUnit?.value ?? (loc[lang]?.variations ? JSON.stringify(loc[lang].variations) : undefined);
    map.set(key, { en: val('en') ?? key, cs: val('cs'), extractionState: entry.extractionState, shouldTranslate: entry.shouldTranslate });
  }
  return map;
}
