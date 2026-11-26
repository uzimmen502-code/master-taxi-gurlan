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

check('ega qiymatlari: 60 daqiqa / 14 kun (ega 2026-11-27; avval 7)', () => {
  assert.strictEqual(pre.MIN_LEAD_MIN, 60);
  assert.strictEqual(pre.MAX_DAYS, 14);
  assert.strictEqual(pre.MAX_LEAD_DAYS, 14);
});

check('parseScheduled: yo\'q/bo\'sh — oddiy; butun musbat son — ok; satr, kasr, 0, manfiy, NaN, bool — xato', () => {
  for (const raw of [undefined, null, '']) assert.deepStrictEqual(pre.parseScheduled(raw), { ms: null });
  assert.deepStrictEqual(pre.parseScheduled(T), { ms: T });
  for (const raw of ['1800000000000', 1.5, 0, -5, Number.NaN, true, {}, [], Infinity]) {
    assert.deepStrictEqual(pre.parseScheduled(raw), { error: 'PREORDER_TIME_INVALID' }, String(raw));
  }
});

check('checkWindow chegaralari: 59:59 — erta; 60:00 — ok; 7 va 14 kun — ok; 14 kun + 1 ms — uzoq', () => {
  assert.strictEqual(pre.checkWindow(T, T + 60 * MIN - 1), 'PREORDER_TOO_SOON');
  assert.strictEqual(pre.checkWindow(T, T + 60 * MIN), null);
  assert.strictEqual(pre.checkWindow(T, T + 7 * 24 * 60 * MIN), null);
  assert.strictEqual(pre.checkWindow(T, T + 7 * 24 * 60 * MIN + 1), null);
  assert.strictEqual(pre.checkWindow(T, T + 14 * 24 * 60 * MIN), null);
  assert.strictEqual(pre.checkWindow(T, T + 14 * 24 * 60 * MIN + 1), 'PREORDER_TOO_FAR');
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
  for (let lead = 60; lead <= 14 * 24 * 60; lead += 37) {
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

check('dishPreorderProblem (ega 2026-11-27): eski taom — cheklovsiz; preorderable=false — oldindan yo\'q; leadDays chegaralari; noto\'g\'ri — xavfsiz rad', () => {
  const D = 24 * 60 * MIN;
  // eski taom (maydonsiz) — oddiy ham, oldindan ham
  assert.strictEqual(pre.dishPreorderProblem({ price: 1000 }, T, null), null);
  assert.strictEqual(pre.dishPreorderProblem({ price: 1000 }, T, T + 3 * D), null);
  assert.strictEqual(pre.dishPreorderProblem(undefined, T, null), null);
  // preorderable
  assert.strictEqual(pre.dishPreorderProblem({ preorderable: true }, T, T + D), null);
  assert.strictEqual(pre.dishPreorderProblem({ preorderable: false }, T, null), null, 'oddiy buyurtmada mumkin');
  assert.deepStrictEqual(pre.dishPreorderProblem({ preorderable: false }, T, T + D), { code: 'PREORDER_ITEM_NOT_ALLOWED' });
  // leadDays: 0 — cheklov yo'q; N — faqat oldindan, >= hozir + N kun (chegara kiradi)
  assert.strictEqual(pre.dishPreorderProblem({ preorderLeadDays: 0 }, T, null), null);
  assert.strictEqual(pre.dishPreorderProblem({ preorderLeadDays: 0 }, T, T + 60 * MIN), null);
  assert.deepStrictEqual(pre.dishPreorderProblem({ preorderable: true, preorderLeadDays: 2 }, T, null), { code: 'PREORDER_ITEM_REQUIRED', leadDays: 2 });
  assert.deepStrictEqual(pre.dishPreorderProblem({ preorderLeadDays: 2 }, T, T + 2 * D - 1), { code: 'PREORDER_ITEM_LEAD_TOO_SHORT', leadDays: 2 });
  assert.strictEqual(pre.dishPreorderProblem({ preorderLeadDays: 2 }, T, T + 2 * D), null);
  assert.strictEqual(pre.dishPreorderProblem({ preorderLeadDays: 14 }, T, T + 14 * D), null);
  assert.deepStrictEqual(pre.dishPreorderProblem({ preorderable: false, preorderLeadDays: 1 }, T, T + 2 * D), { code: 'PREORDER_ITEM_NOT_ALLOWED' });
  for (const bad of [{ preorderLeadDays: 15 }, { preorderLeadDays: -1 }, { preorderLeadDays: 1.5 }, { preorderLeadDays: '2' }, { preorderLeadDays: null },
    { preorderable: 'true' }, { preorderable: null }, { preorderable: 1 }]) {
    assert.deepStrictEqual(pre.dishPreorderProblem(bad, T, T + 3 * D), { code: 'MENU_ITEM_PREORDER_INVALID' }, JSON.stringify(bad));
  }
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
