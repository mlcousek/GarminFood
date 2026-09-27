// shape.ts -- small helpers for reading Garmin / Open Food Facts JSON.
//
// Why it exists: both APIs are undocumented or loosely typed (fields go
// missing, numbers arrive as strings or "", a day with nothing logged
// omits whole objects -- see docs/garmin-routes.json and
// docs/openfoodfacts-product-route.md). Tools read responses through these
// lenient accessors so an absent field becomes null in the answer instead
// of a crash, while a wrong top-level shape is still reported by the tool.
// Plus the date helpers every dated tool shares.

import { z } from 'zod';

export type Json = Record<string, unknown>;

export function obj(value: unknown): Json | null {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Json) : null;
}

export function arr(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function str(value: unknown): string | null {
  if (typeof value === 'string') return value.length ? value : null;
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return null;
}

export function num(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export function round(value: number | null, digits = 1): number | null {
  if (value === null) return null;
  const f = 10 ** digits;
  return Math.round(value * f) / f;
}

/** Grams (Garmin's weight unit) to kilograms, 2 decimals. */
export function gramsToKg(value: unknown): number | null {
  const g = num(value);
  return g === null ? null : round(g / 1000, 2);
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function isValidDate(value: string): boolean {
  if (!DATE_RE.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

export const dateSchema = z
  .string()
  .refine(isValidDate, { message: 'must be a calendar date written YYYY-MM-DD' });

/** yyyy-MM-dd of `date` in this PC's local time zone. */
export function localDate(date: Date = new Date()): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** Whole days from `start` to `end` (both yyyy-MM-dd); negative when end < start. */
export function daysBetween(start: string, end: string): number {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000);
}

export function checkRange(start: string, end: string, maxDays: number): void {
  const span = daysBetween(start, end);
  if (span < 0) throw new Error(`endDate (${end}) is before startDate (${start}).`);
  if (span + 1 > maxDays) throw new Error(`The range ${start}..${end} is ${span + 1} days; at most ${maxDays} days per call.`);
}
