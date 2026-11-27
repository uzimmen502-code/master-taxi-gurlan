/**
 * Kuryer vazifa haqi (gilam / agro / yig'ib olish) — SOF funksiyalar (D5, ega qarori 2026-10-16).
 *   node functions/test/courier_task_payout_pure.test.js
 *
 * Qoida: haq = FOIZ (bps), BUTUN so'm, floor (platforma ulushi ceil, ijrochi haqi
 * floor - splitInternal bilan bir xil); standart foiz YO'Q (sozlanmagan = null).
 */
'use strict';
const assert = require('assert');
const p = require('../courier_task_payout');

let pass = 0;
let failCount = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log(`PASS - ${name}`); } catch (e) {
    failCount += 1; console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

check('modul kalitlari: carpet | agro | collection', () => {
  assert.deepStrictEqual([...p.MODULE_KEYS], ['carpet', 'agro', 'collection']);
});

check('computePayout: 40 000 × 1 500 bps = 6 000; 0 bps = 0; 10 000 bps = to\'liq', () => {
  assert.strictEqual(p.computePayout(40000, 1500), 6000);
  assert.strictEqual(p.computePayout(40000, 0), 0);
  assert.strictEqual(p.computePayout(40000, 10000), 40000);
});
check('computePayout: floor — 33 333 × 15 % = 4 999 (4 999.95 emas 5 000)', () => {
  assert.strictEqual(p.computePayout(33333, 1500), 4999);
  assert.strictEqual(p.computePayout(1, 1), 0);
  assert.strictEqual(p.computePayout(9999, 1), 0);
  assert.strictEqual(p.computePayout(10000, 1), 1);
});
check('computePayout: noto\'g\'ri kirish → null (float/satr/0/manfiy/NaN/chegaradan tashqari)', () => {
  for (const base of [0, -5, 1.5, '40000', NaN, null, undefined]) assert.strictEqual(p.computePayout(base, 1500), null, String(base));
  for (const bps of [-1, 10001, 1.5, '1500', NaN, null, undefined]) assert.strictEqual(p.computePayout(40000, bps), null, String(bps));
});

const doc = { version: 7, modules: { carpet: { bps: 1500 }, agro: { bps: 0 }, collection: { bps: 'x' } } };
check('resolveRate: sozlangan → {bps, version}; yo\'q hujjat / modul / noma\'lum kalit → null (standart YO\'Q)', () => {
  assert.deepStrictEqual(p.resolveRate(doc, 'carpet'), { bps: 1500, version: 7 });
  assert.deepStrictEqual(p.resolveRate(doc, 'agro'), { bps: 0, version: 7 }, '0 % — sozlangan (haq yo\'q), "sozlanmagan" emas');
  assert.strictEqual(p.resolveRate(doc, 'collection'), null, 'noto\'g\'ri bps');
  assert.strictEqual(p.resolveRate(null, 'carpet'), null);
  assert.strictEqual(p.resolveRate({}, 'carpet'), null);
  assert.strictEqual(p.resolveRate(doc, 'bread'), null);
  assert.strictEqual(p.resolveRate(doc, '__proto__'), null);
});

check('buildPayout: sozlangan -> payout + bps + version + base + kuryer + modul/vazifa (vazifa hujjatiga EMAS, alohida hujjatga)', () => {
  const f = p.buildPayout('carpet', 't1', 40000, doc, '998901110001');
  assert.deepStrictEqual(f, {
    module: 'carpet', taskId: 't1', courierId: '998901110001',
    payout: 6000, bps: 1500, version: 7, base: 40000, reason: null,
  });
});
check('buildPayout: natijada courierPayout* nomli maydon YO\'Q (vazifa hujjatiga oqib ketmasin)', () => {
  const f = p.buildPayout('carpet', 't1', 40000, doc, 'c1');
  assert.deepStrictEqual(Object.keys(f).filter((k) => /^courierPayout/.test(k)), []);
  assert.strictEqual(p.buildFields, undefined, 'eski buildFields olib tashlangan');
});
check('buildPayout: foiz sozlanmagan -> payout null, sabab not_configured (versiya hujjatniki)', () => {
  const f = p.buildPayout('carpet', 't1', 40000, null, 'c1');
  assert.deepStrictEqual(f, {
    module: 'carpet', taskId: 't1', courierId: 'c1',
    payout: null, bps: null, version: 0, base: 40000, reason: 'not_configured',
  });
  assert.strictEqual(p.buildPayout('carpet', 't1', 40000, { version: 4, modules: {} }, 'c1').version, 4);
});
check('buildPayout: narx noma\'lum (0 / yo\'q / float / satr) -> null, sabab price_unknown, foiz saqlanadi', () => {
  for (const base of [0, undefined, null, 12.5, '40000', -3]) {
    const f = p.buildPayout('carpet', 't1', base, doc, 'c1');
    assert.strictEqual(f.payout, null, String(base));
    assert.strictEqual(f.reason, 'price_unknown', String(base));
    assert.strictEqual(f.bps, 1500, 'foiz keyin qayta hisoblash uchun');
    assert.strictEqual(f.base, null);
  }
});
check('buildPayout: 0 % sozlangan -> payout 0 (null emas), sabab yo\'q', () => {
  const f = p.buildPayout('agro', 't1', 20000, doc, 'c1');
  assert.strictEqual(f.payout, 0);
  assert.strictEqual(f.reason, null);
});

check('payoutDocId: {modul}_{vazifaId}; noma\'lum modul / bo\'sh yoki "/" li id -> xato', () => {
  assert.strictEqual(p.PAYOUT_COLLECTION, 'courier_task_payouts');
  assert.strictEqual(p.payoutDocId('carpet', 'abc'), 'carpet_abc');
  assert.strictEqual(p.payoutDocId('collection', 'X1'), 'collection_X1');
  assert.throws(() => p.payoutDocId('bread', 'abc'));
  assert.throws(() => p.payoutDocId('carpet', ''));
  assert.throws(() => p.payoutDocId('carpet', 'a/b'));
  assert.throws(() => p.payoutDocId('carpet', undefined));
});
check('validatePctInput: modul va bps tekshiruvi; null = sozlamani olib tashlash', () => {
  assert.deepStrictEqual(p.validatePctInput({ module: 'carpet', bps: 1500 }), { module: 'carpet', bps: 1500 });
  assert.deepStrictEqual(p.validatePctInput({ module: 'agro', bps: null }), { module: 'agro', bps: null });
  assert.throws(() => p.validatePctInput({ module: 'bread', bps: 1 }), (e) => e.code === 'MODULE_INVALID');
  assert.throws(() => p.validatePctInput({ bps: 1 }), (e) => e.code === 'MODULE_INVALID');
  for (const bad of [-1, 10001, 1.5, '1500', true, undefined]) {
    assert.throws(() => p.validatePctInput({ module: 'carpet', bps: bad }), (e) => e.code === 'COURIER_PAYOUT_BPS_INVALID', String(bad));
  }
});

console.log(`\n${pass} passed, ${failCount} failed`);
process.exit(failCount ? 1 : 0);
