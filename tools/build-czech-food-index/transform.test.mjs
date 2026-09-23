// Tests for the offline index transform. Run: node --test tools/build-czech-food-index/transform.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildIndex, kcalPer100g, pickNames, toRecord } from './transform.mjs';

const tvaroh = {
  code: '8594001234567',
  lang: 'cs',
  product_name: 'Jihočeský tvaroh měkký',
  product_name_en: 'Soft quark',
  brands: ['Madeta'],
  quantity: '250 g',
  nutriments: {
    'energy-kcal_100g': 102, carbohydrates_100g: 3.5, proteins_100g: 17, fat_100g: 0.5,
    sugars_100g: 3.5, salt_100g: 0.1234,
  },
};

test('maps a Czech product to the compact record, omitting unknown values', () => {
  assert.deepEqual(toRecord(tvaroh), {
    c: '8594001234567', n: 'Jihočeský tvaroh měkký', e: 'Soft quark', b: 'Madeta', q: '250 g',
    k: 102, cb: 3.5, p: 17, f: 0.5, s: 3.5, sa: 0.1,
  });
});

test('prefers product_name_cs, and only trusts product_name as Czech when lang is cs', () => {
  assert.deepEqual(pickNames({ lang: 'de', product_name: 'Quark', product_name_cs: 'Tvaroh' }), { display: 'Tvaroh', alternate: 'Quark' });
  assert.deepEqual(pickNames({ lang: 'de', product_name: 'Quark', generic_name_cs: 'Tvaroh' }), { display: 'Tvaroh', alternate: 'Quark' });
  assert.equal(pickNames({ lang: 'cs', product_name: '  ' }), null);
});

test('drops products without a usable code, name or kcal', () => {
  assert.equal(toRecord({ ...tvaroh, code: '' }), null);
  assert.equal(toRecord({ ...tvaroh, code: 'abc' }), null);
  assert.equal(toRecord({ ...tvaroh, product_name: '', product_name_en: '' }), null);
  assert.equal(toRecord({ ...tvaroh, nutriments: { proteins_100g: 17 } }), null);
});

test('derives kcal from kJ when the kcal field is missing', () => {
  assert.equal(Math.round(kcalPer100g({ 'energy-kj_100g': 418.4 })), 100);
  assert.equal(kcalPer100g({ 'energy-kcal_100g': '55,5' }), 55.5);
});

test('joins brand arrays and legacy comma strings alike', () => {
  assert.equal(toRecord({ ...tvaroh, brands: ['Madeta', 'Jihočeský'] }).b, 'Madeta, Jihočeský');
  assert.equal(toRecord({ ...tvaroh, brands: 'Madeta' }).b, 'Madeta');
});

test('index is deduped by code and sorted, so output is deterministic', () => {
  const a = { ...tvaroh, code: '200' + '00000' };
  const b = { ...tvaroh, code: '100' + '00000' };
  const index = buildIndex([a, b, { ...a, product_name: 'Duplicate' }]);
  assert.equal(index.schema, 1);
  assert.deepEqual(index.products.map((r) => r.c), ['10000000', '20000000']);
  assert.equal(index.products[1].n, 'Jihočeský tvaroh měkký');
  assert.deepEqual(buildIndex([b, a]), buildIndex([a, b]));
});

test('--drop-optional removes fiber, sugar and salt', () => {
  const [record] = buildIndex([tvaroh], { dropOptional: true }).products;
  assert.equal(record.s, undefined);
  assert.equal(record.sa, undefined);
  assert.equal(record.cb, 3.5);
});
