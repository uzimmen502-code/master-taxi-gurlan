/**
 * Oldindan buyurtma — sof qoidalar (S4b). Emulator kerak emas: node functions/test/restaurant_preorder.test.js
 * Buyurtma zanjirida ishlatilishi — restaurant_orders_cf.test.js (PO1…).
 */
'use strict';
const assert = require('assert');
const pre = require('../restaurant_preorder');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};
const MIN = 60 * 1000;
const T = 1_800_000_000_000;

check('ega qiymatlari: 60 daqiqa / 7 kun', () => {
  assert.strictEqual(pre.MIN_LEAD_MIN, 60);
  assert.strictEqual(pre.MAX_DAYS, 7);
});

check('parseScheduled: yo\'q/bo\'sh — oddiy; butun musbat son — ok; satr, kasr, 0, manfiy, NaN, bool — xato', () => {
  for (const raw of [undefined, null, '']) assert.deepStrictEqual(pre.parseScheduled(raw), { ms: null });
  assert.deepStrictEqual(pre.parseScheduled(T), { ms: T });
  for (const raw of ['1800000000000', 1.5, 0, -5, Number.NaN, true, {}, [], Infinity]) {
    assert.deepStrictEqual(pre.parseScheduled(raw), { error: 'PREORDER_TIME_INVALID' }, String(raw));
  }
});

check('checkWindow chegaralari: 59:59 — erta; 60:00 — ok; 7 kun — ok; 7 kun + 1 ms — uzoq', () => {
  assert.strictEqual(pre.checkWindow(T, T + 60 * MIN - 1), 'PREORDER_TOO_SOON');
  assert.strictEqual(pre.checkWindow(T, T + 60 * MIN), null);
  assert.strictEqual(pre.checkWindow(T, T + 7 * 24 * 60 * MIN), null);
  assert.strictEqual(pre.checkWindow(T, T + 7 * 24 * 60 * MIN + 1), 'PREORDER_TOO_FAR');
  assert.strictEqual(pre.checkWindow(T, T - MIN), 'PREORDER_TOO_SOON', 'o\'tmish');
  assert.strictEqual(pre.checkWindow(T, T), 'PREORDER_TOO_SOON');
});

check('acceptDeadlineMs: 2 soat YOKI bajarilishdan 30 daqiqa oldin — qaysi biri avval', () => {
  assert.strictEqual(pre.acceptDeadlineMs(T, T + 3 * 24 * 60 * MIN), T + 120 * MIN, 'uzoq buyurtma — 2 soat');
  assert.strictEqual(pre.acceptDeadlineMs(T, T + 60 * MIN), T + 30 * MIN, 'minimal oldindan (60) — 30 daqiqa qoladi');
  assert.strictEqual(pre.acceptDeadlineMs(T, T + 150 * MIN), T + 120 * MIN);
  assert.strictEqual(pre.acceptDeadlineMs(T, T + 151 * MIN), T + 120 * MIN);
  assert.strictEqual(pre.acceptDeadlineMs(T, T + 120 * MIN), T + 90 * MIN);
  // har qanday ruxsat etilgan buyurtmada muddat hozirdan KEYIN va bajarilishdan OLDIN
  for (let lead = 60; lead <= 7 * 24 * 60; lead += 37) {
    const d = pre.acceptDeadlineMs(T, T + lead * MIN);
    assert.ok(d > T && d <= T + lead * MIN - 30 * MIN, `lead ${lead}`);
  }
});

check('courierWindowOpen: bajarilishdan 90 daqiqa oldin ochiladi (chegara kiradi)', () => {
  const s = T + 5 * 24 * 60 * MIN;
  assert.strictEqual(pre.courierWindowOpen(T, s), false);
  assert.strictEqual(pre.courierWindowOpen(s - 90 * MIN - 1, s), false);
  assert.strictEqual(pre.courierWindowOpen(s - 90 * MIN, s), true);
  assert.strictEqual(pre.courierWindowOpen(s, s), true);
  assert.strictEqual(pre.courierWindowOpen(s + 5 * MIN, s), true, 'kechiksa ham ochiq');
});

check('scheduledMsOf: Timestamp → ms; yo\'q/noto\'g\'ri — null', () => {
  assert.strictEqual(pre.scheduledMsOf({ scheduledFor: { toMillis: () => 123 } }), 123);
  for (const od of [null, undefined, {}, { scheduledFor: null }, { scheduledFor: 5 }, { scheduledFor: {} }]) {
    assert.strictEqual(pre.scheduledMsOf(od), null);
  }
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
