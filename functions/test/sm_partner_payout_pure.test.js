/**
 * «AVA Супермаркет» ҳамкорга тўлов — тоза функциялар (эга 2026-11-28).
 *   node test/sm_partner_payout_pure.test.js
 */
'use strict';
const assert = require('assert');
const m = require('../sm_partner_payout');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
const K1 = 'aaaaaaaaaaaaaaaa';
const K2 = 'bbbbbbbbbbbbbbbb';

check('P1 parseSettings: йўқ → off/null; stage нотўғри → off; bp чегаралари; нотўғри bp → valid:false', () => {
  assert.deepStrictEqual(m.parseSettings(null), { stage: 'off', commissionBp: null, version: 0, valid: true, configured: false });
  assert.deepStrictEqual(m.parseSettings({ stage: 'public', version: 3 }), { stage: 'public', commissionBp: null, version: 3, valid: true, configured: true });
  assert.strictEqual(m.parseSettings({ stage: 'beta' }).stage, 'off');
  assert.strictEqual(m.parseSettings({ commissionBp: 0 }).commissionBp, 0);
  assert.strictEqual(m.parseSettings({ commissionBp: 10000 }).commissionBp, 10000);
  for (const bad of [10001, -1, 1.5, '100', NaN]) assert.strictEqual(m.parseSettings({ commissionBp: bad }).valid, false, String(bad));
});

check('P2 commissionOf: ceil, бутун; 0/1/10000 bp; нотўғри кирим — хато', () => {
  assert.strictEqual(m.commissionOf(35400, 1000), 3540);
  assert.strictEqual(m.commissionOf(35401, 1000), 3541, '3540.1 → 3541 (AVA улуши юқорига)');
  assert.strictEqual(m.commissionOf(9999, 1), 1, '0.9999 → 1');
  assert.strictEqual(m.commissionOf(10000, 1), 1);
  assert.strictEqual(m.commissionOf(5000, 0), 0);
  assert.strictEqual(m.commissionOf(0, 1000), 0);
  assert.strictEqual(m.commissionOf(12345, 10000), 12345);
  for (const [a, b] of [[-1, 10], [1.5, 10], [100, 10001], [100, -1], [100, 2.5], ['100', 10]]) assert.throws(() => m.commissionOf(a, b), undefined, `${a}/${b}`);
});

check('P3 lineBasis: олинган — 0; тортилган — finalTotal; тортилмаган — total + weighPending; оддий — total', () => {
  assert.deepStrictEqual(m.lineBasis({ total: 1000, removed: { reason: 'x' } }), { basis: 0, weighPending: false });
  assert.deepStrictEqual(m.lineBasis({ total: 12000, weighed: true, actualQty: 1.9, finalTotal: 11400 }), { basis: 11400, weighPending: false });
  assert.deepStrictEqual(m.lineBasis({ total: 12000, weighed: true }), { basis: 12000, weighPending: true });
  assert.deepStrictEqual(m.lineBasis({ total: 24000, weighed: false }), { basis: 24000, weighPending: false });
  assert.deepStrictEqual(m.lineBasis({ total: 1.5 }), { basis: 0, weighPending: false }, 'float total — 0 (бузуқ маълумот пул бўлмайди)');
});

const S = (bp, version = 1) => ({ stage: 'internal', commissionBp: bp, version, valid: true, configured: true });
const items = [
  { productId: 'p1a', price: 6000, qty: 2, total: 12000, weighed: true, actualQty: 1.9, finalTotal: 11400 },
  { productId: 'p1b', price: 12000, qty: 2, total: 24000 },
  { productId: 'p2a', price: 80000, qty: 1.5, total: 120000, weighed: true, actualQty: 1.4, finalTotal: 112000 },
  { productId: 'ava', price: 4500, qty: 1, total: 4500 },
  { productId: 'p1c', price: 9000, qty: 1, total: 9000, removed: { reason: 'shortage' } },
];
const partnerOf = { p1a: { partnerKey: K1, sellerId: '998913000001' }, p1b: { partnerKey: K1, sellerId: null }, p2a: { partnerKey: K2, sellerId: '998913000002' }, ava: null, p1c: { partnerKey: K1, sellerId: '998913000001' } };

check('P4 planOrder: ҳамкорлар бўйича, AVA қатори алоҳида, олинган қатор ҳисобга кирмайди, 10 % комиссия', () => {
  const r = m.planOrder({ items, partnerOf, settings: S(1000) });
  assert.deepStrictEqual([r.avaGoods, r.avaLines, r.partners.length], [4500, 1, 2]);
  const [a, b] = r.partners;
  assert.deepStrictEqual([a.partnerKey, a.sellerId, a.goodsBasis, a.commission, a.amount, a.status, a.lines.length], [K1, '998913000001', 35400, 3540, 31860, 'accrue', 2]);
  assert.deepStrictEqual([b.partnerKey, b.goodsBasis, b.commission, b.amount, b.status, b.settingsVersion], [K2, 112000, 11200, 100800, 'accrue', 1]);
});

check('P5 planOrder блоклар: қоида йўқ → RULE_NOT_SET; тортилмаган → WEIGH_PENDING; сотувчи номаълум → SELLER_UNKNOWN; 100 % → nothing_due', () => {
  const none = m.planOrder({ items, partnerOf, settings: S(null) });
  assert.deepStrictEqual(none.partners.map((p) => [p.status, p.blockReason, p.amount]), [['blocked', 'RULE_NOT_SET', null], ['blocked', 'RULE_NOT_SET', null]]);
  const invalid = m.planOrder({ items, partnerOf, settings: { ...S(1000), valid: false, commissionBp: null } });
  assert.strictEqual(invalid.partners[0].blockReason, 'RULE_NOT_SET');
  const pending = m.planOrder({ items: [{ productId: 'p2a', price: 80000, qty: 1, total: 80000, weighed: true }], partnerOf, settings: S(1000) });
  assert.deepStrictEqual([pending.partners[0].status, pending.partners[0].blockReason, pending.partners[0].goodsBasis], ['blocked', 'WEIGH_PENDING', 80000]);
  const unknown = m.planOrder({ items: [{ productId: 'x', price: 100, qty: 1, total: 100 }], partnerOf: { x: { partnerKey: K1, sellerId: null } }, settings: S(1000) });
  assert.strictEqual(unknown.partners[0].blockReason, 'SELLER_UNKNOWN');
  const all = m.planOrder({ items, partnerOf, settings: S(10000) });
  assert.deepStrictEqual(all.partners.map((p) => [p.status, p.amount]), [['nothing_due', 0], ['nothing_due', 0]]);
  const zero = m.planOrder({ items, partnerOf, settings: S(0) });
  assert.deepStrictEqual(zero.partners.map((p) => p.amount), [35400, 112000]);
  const empty = m.planOrder({ items: [], partnerOf: {}, settings: S(1000) });
  assert.deepStrictEqual([empty.partners.length, empty.avaGoods], [0, 0]);
});

check('P6 paymentProblem: нақд — баланс етарли бўлса; ортиқча — PAYMENT_EXCEEDS_BALANCE; offset — фақат очиқ clawback ичида', () => {
  assert.strictEqual(m.paymentProblem({ method: 'cash', balance: 31860, openAccrued: 31860, sum: 31860 }), '');
  assert.strictEqual(m.paymentProblem({ method: 'bank_transfer', balance: 31860, openAccrued: 31860, sum: 31861 }), 'PAYMENT_EXCEEDS_BALANCE');
  // clawback: тўланган 31860 қайтарилди (B = −31860), янги accrued 10800 (B = −21060, U = 10800).
  assert.strictEqual(m.paymentProblem({ method: 'cash', balance: -21060, openAccrued: 10800, sum: 10800 }), 'PAYMENT_EXCEEDS_BALANCE');
  assert.strictEqual(m.paymentProblem({ method: 'offset', balance: -21060, openAccrued: 10800, sum: 10800 }), '');
  // чегара: offset == U − B
  assert.strictEqual(m.paymentProblem({ method: 'offset', balance: 5000, openAccrued: 5000, sum: 1 }), 'OFFSET_EXCEEDS_CLAWBACK', 'clawback йўқ (B == U) — offset мумкин эмас');
  assert.strictEqual(m.paymentProblem({ method: 'offset', balance: 1000, openAccrued: 5000, sum: 4000 }), '');
  assert.strictEqual(m.paymentProblem({ method: 'offset', balance: 1000, openAccrued: 5000, sum: 4001 }), 'OFFSET_EXCEEDS_CLAWBACK');
  for (const bad of [{ method: 'card', balance: 1, openAccrued: 1, sum: 1 }, { method: 'cash', balance: 1, openAccrued: 1, sum: 0 }, { method: 'cash', balance: 1.5, openAccrued: 1, sum: 1 }]) {
    assert.strictEqual(m.paymentProblem(bad), 'INVALID_REQUEST');
  }
});

check('P7 калитлар ва ҳисоб: детерминистик; курьер supplier_payable:{телефон} билан тўқнашмайди; нотўғри калит — хато', () => {
  assert.strictEqual(m.partnerAccount(K1), `supplier_payable:smp_${K1}`);
  assert.throws(() => m.partnerAccount('998913000001'));
  assert.strictEqual(m.payableIdOf('ord1', K1), `ord1__${K1}`);
  assert.strictEqual(m.accrueKeyOf('ord1', K1), `smPartnerAccrue:ord1:${K1}`);
  assert.strictEqual(m.reverseKeyOf(`ord1__${K1}`), `smPartnerReverse:ord1__${K1}`);
  assert.strictEqual(m.paidKeyOf('998_req'), 'smPartnerPaid:998_req');
});

check('P8 якуний ҳолат: delivered | completed; бекор: rejected | cancelled | fs cancelled', () => {
  assert.strictEqual(m.isDelivered({ status: 'delivered' }), true);
  assert.strictEqual(m.isDelivered({ status: 'in_delivery', fulfillmentStatus: 'COMPLETED' }), true);
  assert.strictEqual(m.isDelivered({ status: 'ready' }), false);
  assert.strictEqual(m.isCancelled({ status: 'rejected' }), true);
  assert.strictEqual(m.isCancelled({ status: 'new', fulfillmentStatus: 'cancelled' }), true);
  assert.strictEqual(m.isCancelled({ status: 'delivered' }), false);
});

check('P9 хабарлар: ҳар код 3 тилда', () => {
  for (const code of ['PAYMENT_EXCEEDS_BALANCE', 'OFFSET_EXCEEDS_CLAWBACK', 'PAYABLE_NOT_PAYABLE', 'STAGE_OFF', 'UNKNOWN_X']) {
    const x = m.messagesOf(code);
    assert.ok(x.uz_Cyrl && x.uz_Latn && x.ru, code);
  }
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed} passed, ${results.length - passed} failed`);
process.exit(passed === results.length ? 0 : 1);
