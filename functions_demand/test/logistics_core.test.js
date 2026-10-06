/**
 * AVA Logistics yadro modeli — status mashinalari, tracking, sirlar.
 *
 *   node functions_demand/test/logistics_core.test.js
 */
const assert = require('assert');
const L = require('../core/logistics');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

// ── SHIPMENT mashinasi ───────────────────────────────────────────────
ok('shipment: awaiting_payment → ready → in_transit → delivered → closed', () => {
  const S = L.SHIPMENT_STATUS;
  assert.strictEqual(L.assertShipmentTransition(S.AWAITING_PAYMENT, S.READY), S.READY);
  assert.strictEqual(L.assertShipmentTransition(S.READY, S.IN_TRANSIT), S.IN_TRANSIT);
  assert.strictEqual(L.assertShipmentTransition(S.IN_TRANSIT, S.DELIVERED), S.DELIVERED);
  assert.strictEqual(L.assertShipmentTransition(S.DELIVERED, S.CLOSED), S.CLOSED);
});
ok('shipment: in_transit\'dan bekor qilib BO\'LMAYDI (custody zanjiri uzilmasin); yo\'lda — disputed/lost', () => {
  const S = L.SHIPMENT_STATUS;
  assert.strictEqual(L.canTransitionShipment(S.IN_TRANSIT, S.CANCELLED), false);
  assert.strictEqual(L.isShipmentCancellable(S.READY), true);
  assert.strictEqual(L.isShipmentCancellable(S.IN_TRANSIT), false);
  assert.throws(() => L.assertShipmentTransition(S.CLOSED, S.READY),
    (e) => e.code === 'failed-precondition' && e.details.reason === 'shipment_transition_denied');
  assert.strictEqual(L.canTransitionShipment(S.IN_TRANSIT, S.DISPUTED), true);
  assert.strictEqual(L.canTransitionShipment(S.DELIVERED, S.DISPUTED), true, 'yetkazilgandan keyin ham nizo mumkin');
});
ok('shipment: awaiting_payment dan to\'g\'ridan-to\'g\'ri in_transit YO\'Q (D-TAXI-13 analogi: to\'lovsiz ish yo\'q)', () => {
  assert.strictEqual(L.canTransitionShipment(L.SHIPMENT_STATUS.AWAITING_PAYMENT, L.SHIPMENT_STATUS.IN_TRANSIT), false);
});

// ── TO'LOV mashinasi (7.6) ───────────────────────────────────────────
ok('to\'lov: pending → escrow_funded → release_approved → settled', () => {
  const P = L.PAYMENT_STATUS;
  assert.strictEqual(L.assertPaymentTransition(P.PENDING, P.ESCROW_FUNDED), P.ESCROW_FUNDED);
  assert.strictEqual(L.assertPaymentTransition(P.ESCROW_FUNDED, P.RELEASE_APPROVED), P.RELEASE_APPROVED);
  assert.strictEqual(L.assertPaymentTransition(P.RELEASE_APPROVED, P.SETTLED), P.SETTLED);
});
ok('to\'lov: muzlatilgan eskroudan settled\'ga TO\'G\'RIDAN-TO\'G\'RI yo\'q; refund yo\'li bor', () => {
  const P = L.PAYMENT_STATUS;
  assert.strictEqual(L.canTransitionPayment(P.ESCROW_FROZEN, P.SETTLED), false);
  assert.strictEqual(L.canTransitionPayment(P.ESCROW_FROZEN, P.REFUND_PENDING), true);
  assert.strictEqual(L.canTransitionPayment(P.REFUND_PENDING, P.REFUNDED), true);
  assert.strictEqual(L.canTransitionPayment(P.SETTLED, P.REFUNDED), false, 'to\'langan pul refund qilinmaydi');
});

// ── ORDER derived ────────────────────────────────────────────────────
ok('order statusi hisoblanadi (7.2): bitta holat, mijoz uchun', () => {
  const S = L.SHIPMENT_STATUS;
  assert.strictEqual(L.deriveOrderStatus([]), 'empty');
  assert.strictEqual(L.deriveOrderStatus([S.AWAITING_PAYMENT, S.READY]), 'awaiting_payment');
  assert.strictEqual(L.deriveOrderStatus([S.READY, S.READY]), 'ready');
  assert.strictEqual(L.deriveOrderStatus([S.READY, S.IN_TRANSIT]), 'in_transit');
  assert.strictEqual(L.deriveOrderStatus([S.DELIVERED, S.IN_TRANSIT]), 'in_transit');
  assert.strictEqual(L.deriveOrderStatus([S.DELIVERED, S.CANCELLED]), 'delivered');
  assert.strictEqual(L.deriveOrderStatus([S.CLOSED, S.CANCELLED]), 'closed');
  assert.strictEqual(L.deriveOrderStatus([S.CANCELLED]), 'cancelled');
  assert.strictEqual(L.deriveOrderStatus([S.DISPUTED, S.DELIVERED]), 'disputed');
  assert.strictEqual(L.deriveOrderStatus([S.LOST, S.DELIVERED]), 'problem');
});

// ── tracking ─────────────────────────────────────────────────────────
ok('tracking raqami AVA-YY-MMDD-NNNNNN, Toshkent kuni bo\'yicha', () => {
  // 2026-10-06 21:30 UTC = 2026-10-07 02:30 Toshkent.
  const now = new Date('2026-10-06T21:30:00Z');
  assert.strictEqual(L.trackingDayKey(now), '261007');
  const tn = L.formatTrackingNumber(now, 42);
  assert.strictEqual(tn, 'AVA-26-1007-000042');
  assert.ok(L.TRACKING_RE.test(tn));
});

// ── sirlar ───────────────────────────────────────────────────────────
ok('kodlar 6 xonali, deterministik, handover ≠ delivery, sirga bog\'liq', () => {
  const s = L.newQrSecret();
  assert.strictEqual(s.length, 32);
  const h = L.handoverCodeFor('shpA', s);
  const d = L.deliveryCodeFor('shpA', s);
  assert.ok(/^\d{6}$/.test(h) && /^\d{6}$/.test(d));
  assert.notStrictEqual(h, d);
  assert.strictEqual(L.handoverCodeFor('shpA', s), h, 'deterministik');
  assert.notStrictEqual(L.handoverCodeFor('shpA', L.newQrSecret()), h, 'boshqa sir — boshqa kod (ehtimoliy)');
});
ok('QR payload: AVA1|{shipmentId}|{token}; parse va tekshiruv', () => {
  const s = L.newQrSecret();
  const payload = L.qrPayloadFor('shpB', s);
  const parsed = L.parseQrPayload(payload);
  assert.strictEqual(parsed.shipmentId, 'shpB');
  assert.strictEqual(L.verifyHandoverProof('shpB', s, { qrPayload: payload }), true);
  assert.strictEqual(L.verifyHandoverProof('shpC', s, { qrPayload: payload }), false, 'boshqa jo\'natma');
  assert.strictEqual(L.verifyHandoverProof('shpB', L.newQrSecret(), { qrPayload: payload }), false, 'boshqa sir');
  assert.strictEqual(L.parseQrPayload('AVA0|x|y'), null);
  assert.strictEqual(L.parseQrPayload(''), null);
});
ok('qo\'lda kod bilan tekshiruv (kamera ruxsatisiz yo\'l, L13 kutilmoqda)', () => {
  const s = L.newQrSecret();
  const code = L.handoverCodeFor('shpD', s);
  assert.strictEqual(L.verifyHandoverProof('shpD', s, { code }), true);
  assert.strictEqual(L.verifyHandoverProof('shpD', s, { code: ` ${code} ` }), true, 'bo\'shliq kesiladi');
  assert.strictEqual(L.verifyHandoverProof('shpD', s, { code: '000000' }), code === '000000');
  assert.strictEqual(L.verifyHandoverProof('shpD', s, {}), false);
  assert.strictEqual(L.verifyDeliveryCode('shpD', s, L.deliveryCodeFor('shpD', s)), true);
  assert.strictEqual(L.verifyDeliveryCode('shpD', s, code), L.deliveryCodeFor('shpD', s) === code, 'handover kodi yetkazishga o\'tmaydi');
});

// ── LEG yordamchilari ────────────────────────────────────────────────
ok('handover tomonlari: birinchi LEG sender\'dan, oxirgisi recipient\'ga; HUB yo\'q', () => {
  assert.deepStrictEqual(L.handoverKindsFor(0, 1), { fromKind: 'sender', toKind: 'recipient' });
  assert.deepStrictEqual(L.handoverKindsFor(0, 3), { fromKind: 'sender', toKind: 'provider' });
  assert.deepStrictEqual(L.handoverKindsFor(1, 3), { fromKind: 'provider', toKind: 'provider' });
  assert.deepStrictEqual(L.handoverKindsFor(2, 3), { fromKind: 'provider', toKind: 'recipient' });
  assert.deepStrictEqual(Object.values(L.CUSTODIAN_KIND).sort(), ['provider', 'recipient', 'sender']);
});
ok('holat belgilari: faqat ro\'yxatdagilar, bo\'sh → intact', () => {
  assert.deepStrictEqual(L.normalizeConditionFlags(['wet', 'xayoliy', 'wet']), ['wet']);
  assert.deepStrictEqual(L.normalizeConditionFlags(undefined), ['intact']);
  assert.deepStrictEqual(L.normalizeConditionFlags([]), ['intact']);
});
ok('custody idempotentlik kaliti — jo\'natma+LEG+tur+clientRequestId', () => {
  assert.strictEqual(L.custodyIdempotencyKey('s1', 'l1', 'pickup', 'req-1'), 's1_l1_pickup_req-1');
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
