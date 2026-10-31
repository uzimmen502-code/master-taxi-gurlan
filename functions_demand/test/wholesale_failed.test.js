/**
 * Ulgurji «Етказилмади» харидор тасдиғи билан (ega, 2026-11-01) — FakeFirestore + HAQIQIY relay
 * callable'lari (jo'natma, LEG, custody):
 *
 *   node functions_demand/test/wholesale_failed.test.js
 *
 * Qulflanadi (musbat / manfiy / chegara / idempotentlik):
 *   - kuryer xabari: holat va pul O'ZGARMAYDI, so'rov + muddat (failedTimeoutMin 1..240, standart 15),
 *     sabab kodi / eski APK matni, takror — idempotent, xabarlar har urinishga bitta
 *   - hamyon buyurtmasi — so'rov YO'Q (not_card_order); chek yuborilgan / tasdiqlangan — RAD
 *   - xaridor: confirm → mavjud rad natijasi; reject → davom (keyin yangi urinish seq 2); begona — RAD
 *   - rad yaroqsiz bo'lib qolsa (chek yuborildi) — superseded, rad YO'Q, hisoblagich o'zgarmaydi
 *   - hisoblagich faqat xaridor sababli (customer_absent | customer_refused)
 *   - sotuvchi/admin: muddatdan OLDIN — decision_not_yet (−1 ms), aynan muddatda — ruxsat; dispatcher/begona — RAD;
 *     audit; birinchi qaror yutadi, takror — idempotent
 *   - sweeper: muddatdan oldin — yo'q, muddatda — eskalatsiya (bir marta), xabar sotuvchi+admin
 *   - eskirgan belgi (boshqa yo'l bilan yetkazildi) — ro'yxat/sweeper tozalaydi
 *   - ro'yxat (faqat admin, telefonsiz), kuryer holati (faqat oxirgi LEG kuryeri)
 */
'use strict';
const assert = require('assert');
const C = require('../api/wholesale_card');
const F = require('../api/wholesale_failed');
const N = require('../notify/wholesale_notify');
const { makeDb } = require('./helpers/logistics_harness');
const {
  BUYER, SELLER, STRANGER, ADMIN, SUPER, DISP, ORDER_ID, K1, NOW, ctx, seedW, flow, quiet: q,
} = require('./helpers/wholesale_flow');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const MIN = 60 * 1000;
const at = (ms) => () => new Date(NOW.getTime() + ms);
const report = (db, data = {}, who = K1, now = at(0)) => q(() => C.makeMarkWholesaleBuyerRefused({ db, now })({ orderId: ORDER_ID, ...data }, ctx(who)));
const respond = (db, decision, who = BUYER, now = at(0)) => q(() => F.makeRespondWholesaleDeliveryFailed({ db, now })({ orderId: ORDER_ID, decision }, ctx(who)));
const resolve = (db, decision, who, now) => q(() => F.makeResolveWholesaleDeliveryFailed({ db, now })({ orderId: ORDER_ID, decision }, ctx(who)));
const sweep = (db, now) => q(() => F.runWholesaleDeliveryFailedSweep({ db, now }));
const orderOf = (db) => db.docs.get(`wholesale_orders/${ORDER_ID}`);
const news = (db) => Object.keys(db.dump('admin_news')).sort();
const audits = (db) => Object.values(db.dump('admin_audit')).filter((a) => a.kind === 'wholesale_delivery_failed_decision');

async function rejects(promise, code, reason) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`«${code}/${reason || ''}» xatosi kutilgan edi`);
}

async function setup(opts = {}) {
  const db = makeDb(seedW(opts.seed || {}));
  const f = await flow(db, opts);
  return { db, ...f };
}

// ═══════════════════════════════════════════════════════════════════════
ok('sof: normalizeTimeout chegaralari (0, 1, 240, 241, satr, kasr) va sabab tahlili', () => {
  assert.deepStrictEqual([0, 1, 15, 240, 241, '20', 1.5, null].map(F.normalizeTimeout), [15, 1, 15, 240, 15, 15, 15, 15]);
  assert.deepStrictEqual(F.parseReason({ reasonCode: 'courier_problem', reason: ' izoh ' }), { reasonCode: 'courier_problem', note: 'izoh', legacy: false });
  assert.deepStrictEqual(F.parseReason({ reason: 'pul yo\'q' }), { reasonCode: 'customer_refused', note: 'pul yo\'q', legacy: true });
  assert.strictEqual(F.parseReason({ reason: 'x'.repeat(400) }).note.length, 300);
  assert.throws(() => F.parseReason({ reasonCode: 'cancel_all' }), (e) => e.details.reason === 'reason_invalid');
  assert.deepStrictEqual([...F.REASONS], ['customer_absent', 'customer_refused', 'courier_problem', 'other']);
});

ok('kuryer xabari: holat/pul/hisoblagich O\'ZGARMAYDI; so\'rov seq 1, muddat +15 daq (standart); tarix; xabar xaridor+kuryer; takror — idempotent', async () => {
  const { db, legId, shipmentId } = await setup();
  const before = orderOf(db);
  const r = await report(db, { reasonCode: 'customer_absent', reason: 'eshik yopiq' });
  assert.deepStrictEqual([r.status, r.awaitingBuyer, r.stage, r.idempotent, r.escalateAtMs], ['in_delivery', true, 'awaiting_buyer', false, NOW.getTime() + 15 * MIN]);
  const o = orderOf(db);
  assert.strictEqual(o.status, 'in_delivery');
  assert.deepStrictEqual(o.payment, before.payment, 'pul maydonlari tegilmagan');
  assert.deepStrictEqual(o.cardPayment, before.cardPayment);
  const df = o.deliveryFailed;
  assert.deepStrictEqual([df.seq, df.open, df.stage, df.courierId, df.shipmentId, df.legId, df.reasonCode, df.note, df.timeoutMin, df.resolution],
    [1, true, 'awaiting_buyer', K1, shipmentId, legId, 'customer_absent', 'eshik yopiq', 15, null]);
  assert.strictEqual(o.deliveryFailedOpen, true);
  assert.strictEqual(o.deliveryFailedDueAt.getTime(), NOW.getTime() + 15 * MIN);
  const h = db.docs.get(`wholesale_orders/${ORDER_ID}/history/4`);
  assert.deepStrictEqual([h.event, h.from, h.to, h.actor, h.actorId, h.meta.reasonCode], ['delivery_failed_requested', 'in_delivery', 'in_delivery', 'courier', K1, 'customer_absent']);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`), undefined);
  assert.deepStrictEqual(news(db), [
    `wholesale_${ORDER_ID}_ws_df_buyer_confirm_${BUYER}_df1`,
    `wholesale_${ORDER_ID}_ws_df_courier_wait_${K1}_df1`,
  ].sort());
  const nb = db.docs.get(`admin_news/wholesale_${ORDER_ID}_ws_df_buyer_confirm_${BUYER}_df1`);
  assert.ok(nb.body.includes('15') && !/\{\w+\}/.test(nb.title + nb.body), 'uz_Latn, {timeout}=15');
  // Takror (masalan tarmoq qayta urinishi) — yangi so'rov/tarix/xabar YO'Q.
  const r2 = await report(db, { reasonCode: 'other' });
  assert.deepStrictEqual([r2.idempotent, r2.awaitingBuyer], [true, true]);
  assert.strictEqual(orderOf(db).historySeq, 4);
  assert.strictEqual(orderOf(db).deliveryFailed.reasonCode, 'customer_absent', 'birinchi so\'rov saqlanadi');
  assert.strictEqual(news(db).length, 2);
});

ok('muddat sozlamasi: server_config/customer_confirm.failedTimeoutMin 1 / 240 — o\'zi; 0 / 241 — 15', async () => {
  for (const [v, want] of [[1, 1], [240, 240], [0, 15], [241, 15]]) {
    const { db } = await setup({ seed: { 'server_config/customer_confirm': { failedTimeoutMin: v } } });
    const r = await report(db, { reasonCode: 'other' });
    assert.strictEqual(r.escalateAtMs, NOW.getTime() + want * MIN, `failedTimeoutMin=${v}`);
    assert.strictEqual(orderOf(db).deliveryFailed.timeoutMin, want);
  }
});

ok('kuryer: sabab kodi noto\'g\'ri — reason_invalid; eski APK matni → customer_refused + izoh; begona/sotuvchi/xaridor — not_last_leg_courier; posilka olinmagan — parcel_not_in_hand', async () => {
  let { db } = await setup();
  await rejects(report(db, { reasonCode: 'bogus' }), 'invalid-argument', 'reason_invalid');
  for (const who of [STRANGER, SELLER, BUYER]) await rejects(report(db, {}, who), 'permission-denied', 'not_last_leg_courier');
  await rejects(q(() => C.makeMarkWholesaleBuyerRefused({ db })({ orderId: ORDER_ID }, {})), 'unauthenticated');
  await report(db, { reason: 'pul yo\'q dedi' });
  assert.deepStrictEqual([orderOf(db).deliveryFailed.reasonCode, orderOf(db).deliveryFailed.note, orderOf(db).deliveryFailed.legacyClient], ['customer_refused', 'pul yo\'q dedi', true]);
  ({ db } = await setup({ scan: false }));
  await rejects(report(db), 'failed-precondition', 'parcel_not_in_hand');
  assert.strictEqual(orderOf(db).deliveryFailed, undefined);
});

ok('to\'lov usullari: HAMYON — so\'rov YO\'Q (not_card_order, pul qoidasi kodda yo\'q); chek yuborilgan — receipt_submitted; tasdiqlangan — card_payment_confirmed; nizo — invalid_transition', async () => {
  let { db } = await setup({ extraOrder: { paymentMethod: 'wallet', cardPayment: null, payment: { status: 'held' } } });
  await rejects(report(db), 'failed-precondition', 'not_card_order');
  assert.strictEqual(orderOf(db).deliveryFailed, undefined);
  ({ db } = await setup({ extraOrder: { cardPayment: { status: 'receipt_submitted', receiptPath: 'p', submittedAt: NOW } } }));
  await rejects(report(db), 'failed-precondition', 'receipt_submitted');
  ({ db } = await setup({ extraOrder: { cardPayment: { status: 'confirmed' } } }));
  await rejects(report(db), 'failed-precondition', 'card_payment_confirmed');
  ({ db } = await setup({ extraOrder: { cardPayment: { status: 'disputed' } } }));
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'payment_dispute' });
  await rejects(report(db), 'failed-precondition', 'invalid_transition');
});

ok('xaridor «Олмоқчиман»: davom (holat in_delivery, belgi yopiq, kuryerga xabar); takror reject — idempotent; confirm endi — df_not_pending; YANGI xabar → seq 2, yangi xabarlar', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_absent' });
  const r = await respond(db, 'reject');
  assert.deepStrictEqual([r.status, r.decision, r.idempotent], ['in_delivery', 'continue', false]);
  let o = orderOf(db);
  assert.deepStrictEqual([o.status, o.deliveryFailed.open, o.deliveryFailed.resolution.by, o.deliveryFailed.resolution.decision, o.deliveryFailedOpen, o.deliveryFailedDueAt],
    ['in_delivery', false, 'buyer', 'continue', false, null]);
  assert.strictEqual(db.docs.get(`wholesale_orders/${ORDER_ID}/history/5`).event, 'delivery_failed_continue');
  assert.ok(news(db).includes(`wholesale_${ORDER_ID}_ws_df_courier_continue_${K1}_df1`));
  assert.strictEqual((await respond(db, 'reject')).idempotent, true);
  await rejects(respond(db, 'confirm'), 'failed-precondition', 'df_not_pending');
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`), undefined);
  const r2 = await report(db, { reasonCode: 'customer_refused' });
  assert.strictEqual(r2.idempotent, false);
  o = orderOf(db);
  assert.deepStrictEqual([o.deliveryFailed.seq, o.deliveryFailed.open, o.deliveryFailed.reasonCode], [2, true, 'customer_refused']);
  assert.ok(news(db).includes(`wholesale_${ORDER_ID}_ws_df_buyer_confirm_${BUYER}_df2`));
});

ok('xaridor confirm → MAVJUD rad natijasi (refused, refundStatus pending, returnStatus pending_shipment, hisoblagich +1, refusal.by = kuryer); takror — idempotent; begona/sotuvchi — not_order_party; noto\'g\'ri javob — decision_invalid', async () => {
  const { db, legId } = await setup();
  await report(db, { reasonCode: 'customer_refused', reason: 'olmadi' });
  await rejects(respond(db, 'confirm', SELLER), 'permission-denied', 'not_order_party');
  await rejects(respond(db, 'confirm', STRANGER), 'permission-denied', 'not_order_party');
  await rejects(respond(db, 'yes'), 'invalid-argument', 'decision_invalid');
  const r = await respond(db, 'confirm');
  assert.deepStrictEqual([r.status, r.idempotent], ['refused', false]);
  const o = orderOf(db);
  assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.refusal.by, o.refusal.via, o.refusal.legId, o.refusal.reason, o.refusal.confirmedBy],
    ['refused', 'pending', 'pending_shipment', K1, 'courier', legId, 'olmadi', 'buyer']);
  assert.deepStrictEqual([o.deliveryFailed.open, o.deliveryFailed.resolution.decision, o.deliveryFailedOpen], [false, 'failed', false]);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 1);
  assert.strictEqual(o.historySeq, 5, 'so\'rov (4) + rad (5)');
  assert.strictEqual((await respond(db, 'confirm')).idempotent, true);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 1, 'takror — +1 emas');
  // Eski kuryer APK qayta bossa — eski idempotent javob (refused).
  const again = await report(db);
  assert.deepStrictEqual([again.status, again.idempotent], ['refused', true]);
});

ok('hisoblagich faqat xaridor sababli: courier_problem / other — refused, LEKIN cardRefusals o\'zgarmaydi; customer_absent — +1', async () => {
  for (const [code, want] of [['courier_problem', undefined], ['other', undefined], ['customer_absent', 1]]) {
    const { db } = await setup();
    await report(db, { reasonCode: code });
    await respond(db, 'confirm');
    assert.strictEqual(orderOf(db).status, 'refused', code);
    const st = db.docs.get(`wholesale_buyer_stats/${BUYER}`);
    assert.strictEqual(st ? st.cardRefusals : undefined, want, code);
  }
});

ok('eskirgan so\'rov: kutish paytida xaridor chek yubordi → confirm — df_state_changed, rad YO\'Q, belgi superseded, hisoblagich yo\'q', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_refused' });
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ 'cardPayment.status': 'receipt_submitted', 'cardPayment.submittedAt': NOW });
  await rejects(respond(db, 'confirm'), 'failed-precondition', 'df_state_changed');
  const o = orderOf(db);
  assert.deepStrictEqual([o.status, o.deliveryFailed.open, o.deliveryFailed.resolution.decision, o.deliveryFailed.supersededWhy, o.deliveryFailedOpen],
    ['in_delivery', false, 'superseded', 'card_payment_progressed', false]);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`), undefined);
  assert.strictEqual(db.docs.get(`wholesale_orders/${ORDER_ID}/history/5`).event, 'delivery_failed_superseded');
});

ok('sotuvchi/admin qarori: muddatdan 1 ms OLDIN — decision_not_yet; AYNAN muddatda — ruxsat; begona/dispatcher/xaridor — not_decider; sotuvchi «Етказилсин» → davom + audit', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_absent' });
  await rejects(resolve(db, 'deliver', SELLER, at(15 * MIN - 1)), 'failed-precondition', 'decision_not_yet');
  await rejects(resolve(db, 'failed', ADMIN, at(15 * MIN - 1)), 'failed-precondition', 'decision_not_yet');
  for (const who of [STRANGER, DISP, BUYER, K1]) await rejects(resolve(db, 'failed', who, at(15 * MIN)), 'permission-denied', 'not_decider');
  await rejects(resolve(db, 'cancel', SELLER, at(15 * MIN)), 'invalid-argument', 'decision_invalid');
  const r = await resolve(db, 'deliver', SELLER, at(15 * MIN));
  assert.deepStrictEqual([r.status, r.by, r.decision, r.idempotent], ['in_delivery', 'seller', 'deliver', false]);
  const o = orderOf(db);
  assert.deepStrictEqual([o.status, o.deliveryFailed.resolution.by, o.deliveryFailed.resolution.decision], ['in_delivery', 'seller', 'continue']);
  const a = audits(db);
  assert.strictEqual(a.length, 1);
  assert.deepStrictEqual([a[0].actor, a[0].actorRole, a[0].from, a[0].to, a[0].reason, a[0].target], [SELLER, 'seller', 'in_delivery', 'in_delivery', 'continue', `wholesale_orders/${ORDER_ID}`]);
  assert.ok(news(db).includes(`wholesale_${ORDER_ID}_ws_df_courier_continue_${K1}_df1`));
  assert.ok(news(db).includes(`wholesale_${ORDER_ID}_ws_df_buyer_continue_${BUYER}_df1`));
  // Takror — idempotent; admin boshqa qaror — df_not_pending (birinchi qaror yutdi).
  assert.strictEqual((await resolve(db, 'deliver', SELLER, at(16 * MIN))).idempotent, true);
  await rejects(resolve(db, 'failed', ADMIN, at(16 * MIN)), 'failed-precondition', 'df_not_pending');
  await rejects(respond(db, 'confirm'), 'failed-precondition', 'df_not_pending');
  assert.strictEqual(audits(db).length, 1);
});

ok('admin (superadmin) «Етказилмади» → rad (mavjud natija) + audit; eskalatsiyadan keyin xaridor kech javob bersa — df_not_pending', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_refused' });
  await sweep(db, at(15 * MIN));
  const r = await resolve(db, 'failed', SUPER, at(15 * MIN + 1));
  assert.deepStrictEqual([r.status, r.by], ['refused', 'admin']);
  const o = orderOf(db);
  assert.deepStrictEqual([o.status, o.refusal.by, o.refusal.confirmedBy, o.refusal.confirmedById, o.returnStatus], ['refused', K1, 'admin', SUPER, 'pending_shipment']);
  const a = audits(db);
  assert.deepStrictEqual([a.length, a[0].actorRole, a[0].to, a[0].reason], [1, 'admin', 'refused', 'failed']);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 1);
  await rejects(respond(db, 'reject'), 'failed-precondition', 'df_not_pending');
});

ok('xaridor eskalatsiyadan KEYIN ham javob bera oladi (so\'rov ochiq ekan) — birinchi javob yutadi', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_absent' });
  await sweep(db, at(20 * MIN));
  assert.strictEqual(orderOf(db).deliveryFailed.stage, 'awaiting_decision');
  const r = await respond(db, 'reject', BUYER, at(21 * MIN));
  assert.strictEqual(r.status, 'in_delivery');
  await rejects(resolve(db, 'failed', SELLER, at(22 * MIN)), 'failed-precondition', 'df_not_pending');
});

ok('sweeper: muddatdan oldin — hech narsa; muddatda — eskalatsiya (stage, dueAt null, tarix, xabar sotuvchi + adminlar); qayta — AYNAN bir marta', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'other' });
  let s = await sweep(db, at(15 * MIN - 1));
  assert.strictEqual(s.escalated, 0);
  s = await sweep(db, at(15 * MIN));
  assert.strictEqual(s.escalated, 1);
  const o = orderOf(db);
  assert.deepStrictEqual([o.deliveryFailed.stage, o.deliveryFailed.open, o.deliveryFailedDueAt, o.deliveryFailedOpen], ['awaiting_decision', true, null, true]);
  assert.ok(o.deliveryFailed.escalatedAt);
  assert.strictEqual(db.docs.get(`wholesale_orders/${ORDER_ID}/history/5`).event, 'delivery_failed_escalated');
  const n = news(db);
  assert.ok(n.includes(`wholesale_${ORDER_ID}_ws_df_decide_seller_${SELLER}_df1`));
  assert.ok(n.includes(`wholesale_${ORDER_ID}_ws_df_decide_admin_${ADMIN}_df1`));
  assert.ok(n.includes(`wholesale_${ORDER_ID}_ws_df_decide_admin_${SUPER}_df1`));
  assert.ok(!n.some((k) => k.includes(DISP)), 'dispatcher EMAS');
  s = await sweep(db, at(30 * MIN));
  assert.strictEqual(s.escalated, 0);
  assert.strictEqual(orderOf(db).historySeq, 5);
  // Eskalatsiyadan keyin sotuvchi qaror qila oladi (muddat maydoni o'chgan bo'lsa ham).
  assert.strictEqual((await resolve(db, 'failed', SELLER, at(31 * MIN))).status, 'refused');
});

ok('eskirgan belgi: kutish paytida buyurtma boshqa yo\'l bilan yetkazildi — sweeper/ro\'yxat tozalaydi, qaror — df_not_pending', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'other' });
  await db.collection('wholesale_orders').doc(ORDER_ID).update({ status: 'delivered' });
  const l = await q(() => F.makeListWholesaleDeliveryFailedPending({ db, now: at(MIN) })({}, ctx(ADMIN)));
  assert.deepStrictEqual(l.items, []);
  let o = orderOf(db);
  assert.deepStrictEqual([o.deliveryFailed.open, o.deliveryFailed.resolution.decision, o.deliveryFailedOpen, o.deliveryFailedDueAt], [false, 'superseded', false, null]);
  await rejects(resolve(db, 'failed', SELLER, at(20 * MIN)), 'failed-precondition', 'df_not_pending');
  const s = await sweep(db, at(20 * MIN));
  assert.strictEqual(s.escalated, 0);
  o = orderOf(db);
  assert.strictEqual(o.status, 'delivered');
});

ok('ro\'yxat: faqat qat\'iy admin (dispatcher/sotuvchi/kuryer RAD); element — oxirgi 4 raqam, to\'liq telefon YO\'Q; canDecide muddat bo\'yicha', async () => {
  const { db } = await setup();
  await report(db, { reasonCode: 'customer_absent' });
  const list = F.makeListWholesaleDeliveryFailedPending;
  for (const who of [DISP, SELLER, K1, BUYER]) await rejects(q(() => list({ db, now: at(0) })({}, ctx(who))), 'permission-denied');
  let r = await q(() => list({ db, now: at(MIN) })({}, ctx(ADMIN)));
  assert.strictEqual(r.items.length, 1);
  const it = r.items[0];
  assert.deepStrictEqual([it.orderId, it.stage, it.reasonCode, it.canDecide, it.buyerTail, it.sellerTail, it.courierTail],
    [ORDER_ID, 'awaiting_buyer', 'customer_absent', false, BUYER.slice(-4), SELLER.slice(-4), K1.slice(-4)]);
  const s = JSON.stringify(r);
  for (const p of [BUYER, SELLER, K1]) assert.ok(!s.includes(p), 'to\'liq telefon yo\'q');
  r = await q(() => list({ db, now: at(15 * MIN) })({}, ctx(SUPER)));
  assert.strictEqual(r.items[0].canDecide, true);
});

ok('kuryer holati: oxirgi LEG kuryeri — pending/stage/muddat/qaror; begona/xaridor — RAD', async () => {
  const { db } = await setup();
  const get = (who) => q(() => F.makeGetWholesaleDeliveryFailedState({ db })({ orderId: ORDER_ID }, ctx(who)));
  let st = await get(K1);
  assert.deepStrictEqual([st.pending, st.resolution], [false, null]);
  await report(db, { reasonCode: 'customer_absent' });
  st = await get(K1);
  assert.deepStrictEqual([st.pending, st.stage, st.seq, st.reasonCode, st.escalateAtMs], [true, 'awaiting_buyer', 1, 'customer_absent', NOW.getTime() + 15 * MIN]);
  await respond(db, 'reject');
  st = await get(K1);
  assert.deepStrictEqual([st.pending, st.resolution], [false, { by: 'buyer', decision: 'continue' }]);
  for (const who of [STRANGER, BUYER, SELLER]) await rejects(get(who), 'permission-denied', 'not_last_leg_courier');
});

ok('xabar matnlari: 6 yangi kalit × 3 til — bo\'sh emas, o\'rinbosar qolmaydi; {timeout} ishlatiladi ({minutes}=30 EMAS)', () => {
  const keys = ['ws_df_buyer_confirm', 'ws_df_courier_wait', 'ws_df_courier_continue', 'ws_df_buyer_continue', 'ws_df_decide_seller', 'ws_df_decide_admin'];
  for (const k of keys) {
    for (const lang of N.LANGS) {
      const m = N.render(k, lang, { product: 'Гуруч', qty: 10, orderId: 'o1', timeout: 15 });
      assert.ok(m.title && m.body && !/\{\w+\}/.test(m.title + m.body), `${k}/${lang}`);
      assert.ok(!m.body.includes(' 30 '), `${k}/${lang}: chek muddati emas`);
    }
  }
  assert.ok(N.render('ws_df_buyer_confirm', 'ru', { timeout: 15 }).body.includes('15'));
  assert.ok(!/Недоставк|Принял/.test(keys.map((k) => N.render(k, 'ru', { timeout: 15 }).body).join(' ')));
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
