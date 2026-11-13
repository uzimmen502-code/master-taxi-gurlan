/**
 * Ulgurji: SOTUVCHI QABULI / RADI (ega qarori 2026-11-13) — demand codebase (FakeFirestore).
 *
 *   node functions_demand/test/wholesale_accept.test.js
 *
 * Qulflanadi:
 *   - muddat: 2 ish kuni (Du–Ju, Asia/Tashkent UTC+5), dam olish kunida — Du 00:00 dan; UTC kun chegarasi
 *   - acceptWholesaleOrder: faqat sotuvchi, placed + pending + muddat ichida; idempotent; raddan keyin — kod
 *   - rejectWholesaleOrder: sabab 3..300; placed → cancelled (seller, seller_rejected, refundStatus pending,
 *     history) — pul yo'li xaridor bekor qilgandagi bilan bitta (`refundStatus: pending`, default trigger)
 *   - onCreate: pending + acceptDeadlineAt + sotuvchiga xabar; jo'natma YO'Q; qabuldan keyin — bor
 *   - ESKI (belgisiz) placed buyurtma — avvalgidek avtomatik jo'natma (reconcile)
 *   - sweeper: faqat muddati o'tgan pending; idempotent; tranzaksiyada qayta tekshiradi
 */
const assert = require('assert');
const WO = require('../core/wholesale_orders');
const W = require('../api/wholesale_orders');
const E = require('../api/wholesale_events');
const N = require('../notify/wholesale_notify');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const {
  NOW, ctx, makeDb, seed, deps,
} = require('./helpers/logistics_harness');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998905556677';
const SELLER = '998901234567';
const STRANGER = '998907770007';
const ORDER_ID = 'wo1';
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

const ORIGIN = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, geohash: 'tp5my0b', addressText: 'Gurlan, Markaz 1',
};
const DEST = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, geohash: 'tp5my2c', addressText: 'Gurlan, Bog\'cha 5',
};

/** Toshkent mahalliy vaqti → UTC ms. */
const T = (localIso) => Date.parse(`${localIso}+05:00`);
const localIso = (ms) => new Date(ms + 5 * HOUR).toISOString().slice(0, 16);

function seedW(extra = {}) {
  config.clearCache();
  tariffCore.clearCache();
  return seed({
    [`users/${BUYER}`]: { name: 'Bobur' },
    [`users/${SELLER}`]: { name: 'Sotuvchi' },
    ...extra,
  });
}

/** Default codebase `placeWholesaleOrder` yozadigan buyurtma shakli (wholesale_shipment.test.js bilan bir xil). */
function orderDoc(db, extra = {}) {
  const t = db.docs.get('module_tariffs/logistics_v7');
  const snap = tariffCore.quoteParcel(t, { actualWeightG: 800, declaredValue: 140000 }, ORIGIN, DEST, { dimsOptional: true });
  const fee = snap.customerPrice;
  return {
    buyerId: BUYER,
    buyerWalletUid: BUYER,
    sellerId: SELLER,
    productId: 'rice',
    productTitle: 'Guruch',
    packId: 'p1',
    packLabel: '1 kg',
    qty: 10,
    unitPrice: 14000,
    goodsTotal: 140000,
    deliveryFee: fee,
    total: 140000 + fee,
    currency: 'UZS',
    delivery: {
      tariffVersion: snap.tariffVersion, zone: snap.zone, actualWeightG: 800, chargeableWeightG: snap.chargeableWeightG, dims: null, priceSnapshot: snap,
    },
    origin: ORIGIN,
    destination: DEST,
    quoteId: 'q1',
    status: 'placed',
    historySeq: 1,
    payment: { status: 'held', amount: 140000 + fee },
    shipment: null,
    refundStatus: null,
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  };
}

const DEADLINE = new Date(WO.acceptDeadlineFor(NOW.getTime()));
/** Qaror kutayotgan (onCreate belgilagan) buyurtma. */
const pendingExtra = (extra = {}) => ({
  sellerDecision: 'pending', acceptDeadlineAt: DEADLINE, historySeq: 2, ...extra,
});

async function put(db, extra = {}, id = ORDER_ID) {
  await db.collection('wholesale_orders').doc(id).set(orderDoc(db, extra));
  return id;
}
const orderOf = (db, id = ORDER_ID) => db.docs.get(`wholesale_orders/${id}`);
const historyOf = (db, id = ORDER_ID) => db.dump(`wholesale_orders/${id}/history`);
const at = (ms) => () => new Date(NOW.getTime() + ms);
const accept = (db, now = () => NOW) => W.makeAcceptWholesaleOrder({ db, now });
const reject = (db, now = () => NOW) => W.makeRejectWholesaleOrder({ db, now });
const newsKeys = (db) => Object.values(db.dump('admin_news')).map((n) => `${n.targetUserId}:${n.dataType}`).sort();

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

const realError = console.error;
const realLog = console.log;
function quiet() { console.error = () => {}; console.log = () => {}; }
function loud() { console.error = realError; console.log = realLog; }
async function q(fn) { quiet(); try { return await fn(); } finally { loud(); } }

// ═══════════════════════════════════════════════════════════════════════
// MUDDAT (sof funksiya)
// ═══════════════════════════════════════════════════════════════════════

ok('muddat: kalendar tekshiruvi — 2026-11-16 Dushanba, 2026-11-21 Shanba', () => {
  assert.strictEqual(new Date(T('2026-11-16T12:00')).getUTCDay(), 1);
  assert.strictEqual(new Date(T('2026-11-21T12:00')).getUTCDay(), 6);
});

ok('muddat: ish kunida yaratilgan — o\'sha mahalliy soat, 2 ish kunidan keyin', () => {
  const cases = [
    ['2026-11-16T10:00', '2026-11-18T10:00'], // Du → Ch
    ['2026-11-17T08:30', '2026-11-19T08:30'], // Se → Pa
    ['2026-11-18T17:45', '2026-11-20T17:45'], // Ch → Ju
    ['2026-11-19T15:00', '2026-11-23T15:00'], // Pa → Du
    ['2026-11-20T23:59', '2026-11-24T23:59'], // Ju 23:59 → Se 23:59
    ['2026-11-20T00:00', '2026-11-24T00:00'], // Ju 00:00 → Se 00:00
    ['2026-11-16T00:00', '2026-11-18T00:00'], // Du 00:00 (chegara) → Ch 00:00
  ];
  for (const [from, to] of cases) {
    assert.strictEqual(localIso(WO.acceptDeadlineFor(T(from))), to, `${from} → ${to}`);
  }
});

ok('muddat: Shanba/Yakshanba — hisob Du 00:00 dan → Chorshanba 00:00 (2 to\'liq ish kuni)', () => {
  for (const from of ['2026-11-21T00:00', '2026-11-21T12:00', '2026-11-22T00:00', '2026-11-22T23:59']) {
    assert.strictEqual(localIso(WO.acceptDeadlineFor(T(from))), '2026-11-25T00:00', from);
  }
  // Yakshanba 23:59:59.999 — hali dam olish kuni.
  assert.strictEqual(WO.acceptDeadlineFor(T('2026-11-23T00:00') - 1), T('2026-11-25T00:00'));
});

ok('muddat: UTC kun chegarasi (Toshkent = UTC+5)', () => {
  // Ju 18:59Z = Ju 23:59 mahalliy → Se 23:59 mahalliy = Se 18:59Z.
  assert.strictEqual(WO.acceptDeadlineFor(Date.parse('2026-11-20T18:59:00Z')), Date.parse('2026-11-24T18:59:00Z'));
  // Ju 19:30Z — UTC bo'yicha Juma, lekin mahalliy Shanba 00:30 → Ch 00:00 mahalliy = Se 19:00Z.
  assert.strictEqual(WO.acceptDeadlineFor(Date.parse('2026-11-20T19:30:00Z')), Date.parse('2026-11-24T19:00:00Z'));
  // Ya 19:00Z — UTC bo'yicha Yakshanba, mahalliy Du 00:00 (ish kuni) → Ch 00:00 = Se 19:00Z.
  assert.strictEqual(WO.acceptDeadlineFor(Date.parse('2026-11-22T19:00:00Z')), Date.parse('2026-11-24T19:00:00Z'));
  // Ya 18:59:59.999Z — mahalliy Ya 23:59 → Ch 00:00 mahalliy.
  assert.strictEqual(WO.acceptDeadlineFor(Date.parse('2026-11-22T19:00:00Z') - 1), Date.parse('2026-11-24T19:00:00Z'));
  // Du 20:00Z = Se 01:00 mahalliy → Pa 01:00 mahalliy.
  assert.strictEqual(WO.acceptDeadlineFor(Date.parse('2026-11-16T20:00:00Z')), Date.parse('2026-11-18T20:00:00Z'));
});

/** Ikki payt orasidagi ISH vaqti (ms): mahalliy Du–Ju qismlari yig'indisi (mustaqil hisob). */
function businessMsBetween(a, b) {
  let t = a + 5 * HOUR;
  const end = b + 5 * HOUR;
  let sum = 0;
  while (t < end) {
    const dayEnd = t - (t % DAY) + DAY;
    const segEnd = Math.min(dayEnd, end);
    const dow = new Date(t).getUTCDay();
    if (dow !== 0 && dow !== 6) sum += segEnd - t;
    t = segEnd;
  }
  return sum;
}

ok('muddat (xususiyat): 3 hafta, har 37 daqiqada — natija ish kunida, aynan 48 soat ish vaqti, butun ms', () => {
  const start = T('2026-11-14T00:00');
  for (let t = start; t < start + 21 * DAY; t += 37 * 60 * 1000) {
    const d = WO.acceptDeadlineFor(t);
    assert.ok(Number.isSafeInteger(d) && d > t, `${localIso(t)}`);
    const dow = new Date(d + 5 * HOUR).getUTCDay();
    assert.ok(dow >= 1 && dow <= 5, `ish kunida emas: ${localIso(t)} → ${localIso(d)}`);
    assert.strictEqual(businessMsBetween(t, d), 2 * DAY, `${localIso(t)} → ${localIso(d)}`);
    // Eng birinchi shunday payt: bir daqiqa oldin hali 48 soat bo'lmagan.
    assert.ok(businessMsBetween(t, d - 60000) < 2 * DAY, `eng erta emas: ${localIso(t)}`);
  }
});

ok('muddat: noto\'g\'ri kirish — xato; 0 ish kuni — ish kunida o\'zi', () => {
  assert.throws(() => WO.acceptDeadlineFor(NaN));
  assert.throws(() => WO.acceptDeadlineFor('2026-11-16'));
  assert.throws(() => WO.acceptDeadlineFor(1.5));
  assert.strictEqual(WO.acceptDeadlineFor(T('2026-11-16T10:00'), 0), T('2026-11-16T10:00'));
  assert.strictEqual(WO.ACCEPT_BUSINESS_DAYS, 2);
});

ok('shipmentAllowed: belgisiz (eski) — ha; accepted+acceptedAt — ha; qolgani — yo\'q', () => {
  assert.strictEqual(WO.shipmentAllowed({}), true);
  assert.strictEqual(WO.shipmentAllowed({ sellerDecision: null }), true);
  assert.strictEqual(WO.shipmentAllowed({ sellerDecision: 'accepted', acceptedAt: NOW }), true);
  assert.strictEqual(WO.shipmentAllowed({ sellerDecision: 'accepted' }), false, 'acceptedAt yo\'q');
  for (const d of ['pending', 'rejected', 'timeout', 'weird', '']) {
    assert.strictEqual(WO.shipmentAllowed({ sellerDecision: d, acceptedAt: NOW }), false, d);
  }
});

// ═══════════════════════════════════════════════════════════════════════
// QABUL
// ═══════════════════════════════════════════════════════════════════════

ok('qabul: sotuvchi — accepted + acceptedAt + history; holat placed; pul maydonlari tegilmaydi', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra());
  const r = await q(() => accept(db, at(HOUR))({ orderId: ORDER_ID }, ctx(SELLER)));
  assert.deepStrictEqual([r.ok, r.status, r.sellerDecision, r.idempotent], [true, 'placed', 'accepted', false]);
  const o = orderOf(db);
  assert.strictEqual(o.status, 'placed');
  assert.strictEqual(o.sellerDecision, 'accepted');
  assert.strictEqual(o.acceptedAt.getTime(), NOW.getTime() + HOUR);
  assert.strictEqual(o.sellerDecisionAt.getTime(), NOW.getTime() + HOUR);
  assert.strictEqual(o.acceptedBy, SELLER);
  assert.strictEqual(o.historySeq, 3);
  assert.strictEqual(o.refundStatus, null);
  assert.deepStrictEqual(o.payment, orderDoc(db).payment);
  const h = historyOf(db)['3'];
  assert.deepStrictEqual([h.event, h.actor, h.actorId, h.from, h.to], ['seller_accepted', 'seller', SELLER, 'placed', 'placed']);
});

ok('qabul: 9 xonali sotuvchi ID ham tan olinadi; takror — idempotent, ikkinchi yozuv yo\'q', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra({ sellerId: SELLER.slice(3) }));
  await q(() => accept(db)({ orderId: ORDER_ID }, ctx(SELLER)));
  const writes = db.writes;
  const r2 = await q(() => accept(db, at(2 * HOUR))({ orderId: ORDER_ID }, ctx(SELLER)));
  assert.strictEqual(r2.idempotent, true);
  assert.strictEqual(db.writes, writes, 'takrorda yozuv yo\'q');
  assert.strictEqual(orderOf(db).acceptedAt.getTime(), NOW.getTime(), 'birinchi qabul vaqti saqlanadi');
  assert.strictEqual(Object.keys(historyOf(db)).length, 1);
});

ok('qabul: begona / xaridor / kirmagan / yo\'q buyurtma / noto\'g\'ri ID — rad, yozuv yo\'q', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra());
  await q(async () => {
    await rejects(accept(db)({ orderId: ORDER_ID }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(accept(db)({ orderId: ORDER_ID }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(accept(db)({ orderId: ORDER_ID }, {}), 'unauthenticated');
    await rejects(accept(db)({ orderId: 'nope' }, ctx(SELLER)), 'not-found', 'order_not_found');
    await rejects(accept(db)({ orderId: 'a/b' }, ctx(SELLER)), 'invalid-argument', 'order_required');
    await rejects(accept(db)({}, ctx(SELLER)), 'invalid-argument', 'order_required');
  });
  assert.strictEqual(orderOf(db).sellerDecision, 'pending');
  assert.deepStrictEqual(historyOf(db), {});
});

ok('qabul: muddat chegarasi — aynan muddatda o\'tadi, 1 ms keyin — accept_deadline_passed', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra(), 'a');
  await put(db, pendingExtra(), 'b');
  const atDeadline = () => new Date(DEADLINE.getTime());
  const after = () => new Date(DEADLINE.getTime() + 1);
  const r = await q(() => accept(db, atDeadline)({ orderId: 'a' }, ctx(SELLER)));
  assert.strictEqual(r.idempotent, false);
  await q(() => rejects(accept(db, after)({ orderId: 'b' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_passed'));
  assert.strictEqual(orderOf(db, 'b').sellerDecision, 'pending');
});

ok('qabul: noto\'g\'ri holat — eski buyurtma, xaridor bekor qilgan, rad etilgan, muddat o\'tgan, muddat yo\'q', async () => {
  const db = makeDb(seedW());
  await put(db, {}, 'legacy');
  await put(db, pendingExtra({ status: 'cancelled', refundStatus: 'pending', cancelledBy: 'buyer' }), 'bc');
  await put(db, pendingExtra({ status: 'cancelled', sellerDecision: 'rejected' }), 'rej');
  await put(db, pendingExtra({ status: 'cancelled', sellerDecision: 'timeout' }), 'tmo');
  await put(db, pendingExtra({ acceptDeadlineAt: null }), 'nodl');
  await put(db, pendingExtra({ status: 'in_delivery' }), 'inv');
  await q(async () => {
    await rejects(accept(db)({ orderId: 'legacy' }, ctx(SELLER)), 'failed-precondition', 'seller_decision_not_required');
    await rejects(accept(db)({ orderId: 'bc' }, ctx(SELLER)), 'failed-precondition', 'order_not_placed');
    await rejects(accept(db)({ orderId: 'rej' }, ctx(SELLER)), 'failed-precondition', 'seller_already_rejected');
    await rejects(accept(db)({ orderId: 'tmo' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_passed');
    await rejects(accept(db)({ orderId: 'nodl' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_missing');
    await rejects(accept(db)({ orderId: 'inv' }, ctx(SELLER)), 'failed-precondition', 'order_not_placed');
  });
  assert.strictEqual(orderOf(db, 'legacy').sellerDecision, undefined);
  assert.strictEqual(orderOf(db, 'bc').sellerDecision, 'pending');
});

// ═══════════════════════════════════════════════════════════════════════
// RAD
// ═══════════════════════════════════════════════════════════════════════

ok('rad: placed → cancelled (seller), cancelReason/sellerRejectReason, refundStatus pending, history — xaridor bekor qilgandek', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra());
  const r = await q(() => reject(db, at(HOUR))({ orderId: ORDER_ID, reason: '  Omborda qolmadi  ' }, ctx(SELLER)));
  assert.deepStrictEqual([r.ok, r.status, r.sellerDecision, r.idempotent], [true, 'cancelled', 'rejected', false]);
  const o = orderOf(db);
  const t1 = NOW.getTime() + HOUR;
  assert.strictEqual(o.status, 'cancelled');
  assert.strictEqual(o.cancelledBy, 'seller');
  assert.strictEqual(o.cancelReason, 'seller_rejected');
  assert.strictEqual(o.sellerRejectReason, 'Omborda qolmadi');
  assert.strictEqual(o.sellerDecision, 'rejected');
  assert.strictEqual(o.refundStatus, 'pending', 'pul — default trigger (xaridor bekor qilgandagi bilan bitta yo\'l)');
  assert.strictEqual(o.cancelledAt.getTime(), t1);
  assert.strictEqual(o.statusUpdatedAt.getTime(), t1);
  assert.strictEqual(o.historySeq, 3);
  assert.strictEqual(o.acceptedAt, undefined);
  // Pul/qoldiq bu yerda YOZILMAYDI.
  assert.deepStrictEqual(o.payment, orderDoc(db).payment);
  assert.strictEqual(db.dump('wholesale_stock').rice, undefined);
  const h = historyOf(db)['3'];
  assert.deepStrictEqual([h.from, h.to, h.actor, h.actorId, h.event, h.reason], ['placed', 'cancelled', 'seller', SELLER, 'seller_rejected', 'Omborda qolmadi']);
  // Xaridor bekor qilishi bilan bir xil to'lov maydonlari (default `refundOrder` sharti: cancelled + pending).
  const db2 = makeDb(seedW());
  await put(db2, pendingExtra());
  await q(() => W.makeCancelWholesaleOrder({ db: db2, now: at(HOUR) })({ orderId: ORDER_ID }, ctx(BUYER)));
  const b = orderOf(db2);
  for (const k of ['status', 'refundStatus', 'payment']) assert.deepStrictEqual(o[k], b[k], k);
});

ok('rad: takror — idempotent (yozuv yo\'q); qabuldan keyin rad — seller_already_accepted; raddan keyin qabul — seller_already_rejected', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra(), 'r1');
  await put(db, pendingExtra(), 'a1');
  await q(() => reject(db)({ orderId: 'r1', reason: 'Narx o\'zgardi' }, ctx(SELLER)));
  const writes = db.writes;
  const again = await q(() => reject(db)({ orderId: 'r1', reason: 'boshqa sabab' }, ctx(SELLER)));
  assert.strictEqual(again.idempotent, true);
  assert.strictEqual(db.writes, writes);
  assert.strictEqual(orderOf(db, 'r1').sellerRejectReason, 'Narx o\'zgardi');
  await q(() => rejects(accept(db)({ orderId: 'r1' }, ctx(SELLER)), 'failed-precondition', 'seller_already_rejected'));
  await q(() => accept(db)({ orderId: 'a1' }, ctx(SELLER)));
  await q(() => rejects(reject(db)({ orderId: 'a1', reason: 'kech qoldim' }, ctx(SELLER)), 'failed-precondition', 'seller_already_accepted'));
  const a1 = orderOf(db, 'a1');
  assert.deepStrictEqual([a1.status, a1.sellerDecision, a1.refundStatus], ['placed', 'accepted', null]);
});

ok('rad: sabab chegaralari — 2 belgi / bo\'sh / 301 / satr emas RAD; 3 va 300 o\'tadi', async () => {
  const db = makeDb(seedW());
  for (const id of ['x', 'min', 'max']) await put(db, pendingExtra(), id);
  await q(async () => {
    for (const bad of ['ab', '   ab   ', '', undefined, null, 123, 'a'.repeat(301)]) {
      const e = await rejects(reject(db)({ orderId: 'x', reason: bad }, ctx(SELLER)), 'invalid-argument', 'reason_invalid');
      assert.deepStrictEqual([e.details.min, e.details.max], [3, 300]);
    }
  });
  assert.strictEqual(orderOf(db, 'x').status, 'placed');
  await q(() => reject(db)({ orderId: 'min', reason: 'abc' }, ctx(SELLER)));
  await q(() => reject(db)({ orderId: 'max', reason: 'z'.repeat(300) }, ctx(SELLER)));
  assert.strictEqual(orderOf(db, 'max').sellerRejectReason.length, 300);
  assert.strictEqual(orderOf(db, 'min').status, 'cancelled');
});

ok('rad: xaridor/begona — permission-denied; muddat o\'tgan — accept_deadline_passed; eski buyurtma — not_required', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra());
  await put(db, {}, 'legacy');
  const after = () => new Date(DEADLINE.getTime() + 1);
  await q(async () => {
    await rejects(reject(db)({ orderId: ORDER_ID, reason: 'sabab' }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(reject(db)({ orderId: ORDER_ID, reason: 'sabab' }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(reject(db)({ orderId: ORDER_ID, reason: 'sabab' }, {}), 'unauthenticated');
    await rejects(reject(db, after)({ orderId: ORDER_ID, reason: 'sabab' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_passed');
    await rejects(reject(db)({ orderId: 'legacy', reason: 'sabab' }, ctx(SELLER)), 'failed-precondition', 'seller_decision_not_required');
  });
  assert.strictEqual(orderOf(db).status, 'placed');
  assert.strictEqual(orderOf(db, 'legacy').status, 'placed');
});

// ═══════════════════════════════════════════════════════════════════════
// TRIGGER + JO'NATMA DARVOZASI
// ═══════════════════════════════════════════════════════════════════════

ok('onCreate: pending + acceptDeadlineAt (createdAt + 2 ish kuni) + history + sotuvchiga xabar; jo\'natma YO\'Q; takror — jim', async () => {
  const db = makeDb(seedW());
  await put(db);
  const r = await q(() => W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID));
  assert.strictEqual(r.marked, true);
  const o = orderOf(db);
  assert.strictEqual(o.status, 'placed');
  assert.strictEqual(o.sellerDecision, 'pending');
  assert.strictEqual(o.acceptDeadlineAt.getTime(), WO.acceptDeadlineFor(NOW.getTime()));
  assert.strictEqual(o.shipment, null);
  assert.strictEqual(o.historySeq, 2);
  const h = historyOf(db)['2'];
  assert.deepStrictEqual([h.event, h.actor, h.from, h.to], ['seller_decision_requested', 'system', 'placed', 'placed']);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0, 'qabulgacha jo\'natma yo\'q');
  assert.deepStrictEqual(newsKeys(db), [`${SELLER}:ws_seller_decide`]);
  const news = Object.values(db.dump('admin_news'))[0];
  assert.ok(news.body.includes(E.deadlineText(o.acceptDeadlineAt)), news.body);
  assert.ok(!/\{\w+\}/.test(news.body), 'o\'rinbosar qolmagan');
  const again = await q(() => W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID));
  assert.strictEqual(again.skipped, 'already_marked');
  assert.strictEqual(orderOf(db).historySeq, 2);
  assert.strictEqual(Object.keys(db.dump('admin_news')).length, 1);
});

ok('onCreate: holat placed emas / jo\'natma bor — belgi yozilmaydi', async () => {
  const db = makeDb(seedW());
  await put(db, { status: 'cancelled' }, 'c');
  await put(db, { shipment: { shipmentId: 's1' } }, 's');
  assert.strictEqual((await q(() => W.onWholesaleOrderCreated(deps(db), orderOf(db, 'c'), 'c'))).skipped, 'not_placed');
  assert.strictEqual((await q(() => W.onWholesaleOrderCreated(deps(db), orderOf(db, 's'), 's'))).skipped, 'already_linked');
  assert.strictEqual(orderOf(db, 'c').sellerDecision, undefined);
  assert.strictEqual(orderOf(db, 's').sellerDecision, undefined);
});

ok('jo\'natma: pending — ochilmaydi (ensure + reconcile); qabul → onUpdate jo\'natmani ochadi, xaridorga xabar', async () => {
  const db = makeDb(seedW());
  await put(db);
  await q(() => W.onWholesaleOrderCreated(deps(db), orderOf(db), ORDER_ID));
  const e1 = await q(() => W.ensureWholesaleShipment(deps(db), ORDER_ID));
  assert.strictEqual(e1.skipped, 'seller_decision_pending');
  const rc = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(DAY) }));
  assert.deepStrictEqual([rc.awaitingSeller, rc.checked, rc.linked], [1, 0, 0]);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 0);

  const before = orderOf(db);
  await q(() => accept(db, at(HOUR))({ orderId: ORDER_ID }, ctx(SELLER)));
  const after = orderOf(db);
  const u = await q(() => E.onWholesaleOrderUpdated(deps(db, new Date(NOW.getTime() + HOUR)), before, after, ORDER_ID));
  assert.strictEqual(u.shipment.linked, true);
  const o = orderOf(db);
  assert.strictEqual(o.shipment.shipmentId, u.shipment.shipmentId);
  assert.strictEqual(o.status, 'placed', 'in_delivery — eskrou tushganda (default codebase)');
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
  assert.strictEqual(db.dump('shipments')[o.shipment.shipmentId].wholesaleOrderId, ORDER_ID);
  assert.ok(newsKeys(db).includes(`${BUYER}:ws_seller_accepted_buyer`));
  assert.ok(!newsKeys(db).includes(`${SELLER}:ws_card_new_order`), 'hamyon buyurtmasi — karta xabari yo\'q');
  // Takror trigger / reconcile — ikkinchi jo'natma yo'q.
  const u2 = await q(() => E.onWholesaleOrderUpdated(deps(db), before, after, ORDER_ID));
  assert.strictEqual(u2.shipment.skipped, 'already_linked');
  const rc2 = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(DAY) }));
  assert.strictEqual(rc2.linked, 0);
  assert.strictEqual(Object.keys(db.dump('shipments')).length, 1);
});

ok('jo\'natma: qabuldan keyin yaratish yiqildi → shipmentError; trigger aylanmaydi; reconcile (accepted so\'rovi) bog\'laydi', async () => {
  const db = makeDb(seedW());
  const t7 = db.docs.get('module_tariffs/logistics_v7');
  await put(db, pendingExtra());
  db.docs.delete('module_tariffs/logistics_v7');
  const before = orderOf(db);
  await q(() => accept(db)({ orderId: ORDER_ID }, ctx(SELLER)));
  const u = await q(() => E.onWholesaleOrderUpdated(deps(db), before, orderOf(db), ORDER_ID));
  assert.strictEqual(u.shipment.failed, true);
  // Xato belgisi yozuvi triggerni yana chaqiradi — endi jo'natma urinilmaydi.
  const withErr = orderOf(db);
  const u2 = await q(() => E.onWholesaleOrderUpdated(deps(db), withErr, withErr, ORDER_ID));
  assert.strictEqual(u2.shipment, undefined);
  db.docs.set('module_tariffs/logistics_v7', t7);
  const young = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(60 * 1000) }));
  assert.strictEqual(young.young, 1, 'qabuldan 2 daqiqa o\'tmagan');
  const rc = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(3 * 60 * 1000) }));
  assert.deepStrictEqual([rc.checked, rc.linked], [1, 1]);
  assert.ok(orderOf(db).shipment.shipmentId);
});

ok('ESKI buyurtma (belgisiz placed): reconcile avvalgidek avtomatik jo\'natma ochadi', async () => {
  const db = makeDb(seedW());
  await put(db, {}, 'legacy');
  await put(db, pendingExtra(), 'pend');
  const rc = await q(() => W.reconcileWholesaleShipments({ ...deps(db), now: at(3 * 60 * 1000) }));
  assert.deepStrictEqual([rc.checked, rc.linked, rc.awaitingSeller], [1, 1, 1]);
  assert.ok(orderOf(db, 'legacy').shipment.shipmentId);
  assert.strictEqual(orderOf(db, 'legacy').sellerDecision, undefined, 'eski buyurtmaga belgi yozilmaydi');
  assert.strictEqual(orderOf(db, 'pend').shipment, null);
  const e = await q(() => W.ensureWholesaleShipment(deps(db), 'pend'));
  assert.strictEqual(e.skipped, 'seller_decision_pending');
});

ok('xabarlar: rad → xaridorga; muddat → xaridor + sotuvchi; karta qabul → sotuvchiga karta xabari; xaridor bekor — yangi xabar yo\'q', () => {
  const placed = { status: 'placed', sellerDecision: 'pending' };
  const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`).sort();
  assert.deepStrictEqual(keys(placed, { status: 'cancelled', cancelReason: 'seller_rejected', sellerDecision: 'rejected' }),
    ['buyer:ws_seller_rejected_buyer']);
  assert.deepStrictEqual(keys(placed, { status: 'cancelled', cancelReason: 'seller_timeout', sellerDecision: 'timeout' }),
    ['buyer:ws_seller_timeout_buyer', 'seller:ws_seller_timeout_seller']);
  assert.deepStrictEqual(keys(placed, { status: 'placed', sellerDecision: 'accepted' }), ['buyer:ws_seller_accepted_buyer']);
  assert.deepStrictEqual(keys({ ...placed, paymentMethod: 'card_on_delivery' }, { status: 'placed', sellerDecision: 'accepted', paymentMethod: 'card_on_delivery' }),
    ['buyer:ws_seller_accepted_buyer', 'seller:ws_card_new_order']);
  assert.deepStrictEqual(keys(placed, { status: 'cancelled', cancelledBy: 'buyer', sellerDecision: 'pending' }), []);
  // Qabul takror yozuvi (accepted → accepted) — xabar yo'q.
  assert.deepStrictEqual(keys({ status: 'placed', sellerDecision: 'accepted' }, { status: 'placed', sellerDecision: 'accepted', shipment: { shipmentId: 's' } }), []);
});

ok('xabar matnlari: 5 yangi kalit × 3 til, o\'rinbosarlar to\'ldiriladi', () => {
  const params = { product: 'Guruch', qty: 10, amount: 150000, deadline: '18.11 10:00' };
  for (const key of ['ws_seller_decide', 'ws_seller_accepted_buyer', 'ws_seller_rejected_buyer', 'ws_seller_timeout_buyer', 'ws_seller_timeout_seller']) {
    for (const lang of N.LANGS) {
      assert.ok(N.MESSAGES[key][lang], `${key}/${lang}`);
      const t = N.render(key, lang, params);
      assert.ok(t.title && t.body, `${key}/${lang}`);
      assert.ok(!/\{\w+\}/.test(t.title + t.body), `${key}/${lang}: ${t.body}`);
    }
  }
  assert.ok(N.render('ws_seller_decide', 'ru', params).body.includes('18.11 10:00'));
  assert.strictEqual(E.deadlineText(new Date(T('2026-11-18T10:05'))), '18.11 10:05');
  assert.strictEqual(E.deadlineText(null), '');
});

// ═══════════════════════════════════════════════════════════════════════
// SWEEPER
// ═══════════════════════════════════════════════════════════════════════

ok('sweeper: faqat muddati o\'tgan pending → cancelled (system, seller_timeout, refundStatus pending); takror — hech narsa', async () => {
  const db = makeDb(seedW());
  const past = new Date(NOW.getTime() - 1);
  await put(db, pendingExtra({ acceptDeadlineAt: past }), 'exp');
  await put(db, pendingExtra({ acceptDeadlineAt: new Date(NOW.getTime()) }), 'edge'); // aynan hozir — o'tgan (<=)
  await put(db, pendingExtra({ acceptDeadlineAt: new Date(NOW.getTime() + 1) }), 'fresh');
  await put(db, pendingExtra({ acceptDeadlineAt: past, sellerDecision: 'accepted', acceptedAt: NOW }), 'acc');
  await put(db, pendingExtra({ acceptDeadlineAt: past, status: 'cancelled', cancelledBy: 'buyer' }), 'bc');
  await put(db, {}, 'legacy');
  const before = orderOf(db, 'exp');
  const r = await q(() => W.runWholesaleSellerDecisionSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r.checked, r.cancelled, r.failed], [2, 2, 0]);
  const o = orderOf(db, 'exp');
  assert.strictEqual(o.status, 'cancelled');
  assert.strictEqual(o.cancelledBy, 'system');
  assert.strictEqual(o.cancelReason, 'seller_timeout');
  assert.strictEqual(o.sellerDecision, 'timeout');
  assert.strictEqual(o.refundStatus, 'pending');
  assert.strictEqual(o.historySeq, 3);
  const h = historyOf(db, 'exp')['3'];
  assert.deepStrictEqual([h.from, h.to, h.actor, h.actorId, h.event], ['placed', 'cancelled', 'system', null, 'seller_timeout']);
  assert.strictEqual(orderOf(db, 'edge').status, 'cancelled');
  for (const id of ['fresh', 'acc', 'legacy']) assert.strictEqual(orderOf(db, id).status, 'placed', id);
  assert.strictEqual(orderOf(db, 'bc').cancelledBy, 'buyer');
  // Takror — so'rovdan chiqqan, ikkinchi yozuv yo'q.
  const writes = db.writes;
  const r2 = await q(() => W.runWholesaleSellerDecisionSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r2.checked, r2.cancelled], [0, 0]);
  assert.strictEqual(db.writes, writes);
  // Bekor qilingach — xaridor va sotuvchiga xabar (onUpdate).
  await q(() => E.onWholesaleOrderUpdated(deps(db), before, o, 'exp'));
  assert.deepStrictEqual(newsKeys(db), [`${BUYER}:ws_seller_timeout_buyer`, `${SELLER}:ws_seller_timeout_seller`].sort());
  // Muddat o'tgach sotuvchi qabul ham, rad ham qila olmaydi.
  await q(() => rejects(accept(db)({ orderId: 'exp' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_passed'));
  await q(() => rejects(reject(db)({ orderId: 'exp', reason: 'kech' }, ctx(SELLER)), 'failed-precondition', 'accept_deadline_passed'));
});

ok('sweeper: so\'rov va tranzaksiya orasida sotuvchi qabul qilsa — bekor QILINMAYDI (tranzaksiyada qayta tekshiruv)', async () => {
  const db = makeDb(seedW());
  await put(db, pendingExtra({ acceptDeadlineAt: new Date(NOW.getTime() - 1) }), 'race');
  const realTx = db.runTransaction;
  let first = true;
  db.runTransaction = async (fn) => {
    if (first) {
      first = false;
      // Parallel qabul (muddat chegarasidagi so'nggi lahza) — so'rovdan KEYIN, tranzaksiyadan OLDIN.
      await db.collection('wholesale_orders').doc('race').update({ sellerDecision: 'accepted', acceptedAt: NOW });
    }
    return realTx(fn);
  };
  const r = await q(() => W.runWholesaleSellerDecisionSweep({ db, now: () => NOW }));
  assert.deepStrictEqual([r.checked, r.cancelled, r.skipped], [1, 0, 1]);
  const o = orderOf(db, 'race');
  assert.deepStrictEqual([o.status, o.sellerDecision, o.refundStatus], ['placed', 'accepted', null]);
});

ok('sweeper: limit — bir chaqiruvda ko\'pi bilan N ta, qolgani keyingisida', async () => {
  const db = makeDb(seedW());
  for (let i = 0; i < 5; i += 1) await put(db, pendingExtra({ acceptDeadlineAt: new Date(NOW.getTime() - 1) }), `o${i}`);
  const r1 = await q(() => W.runWholesaleSellerDecisionSweep({ db, now: () => NOW }, { limit: 3 }));
  const r2 = await q(() => W.runWholesaleSellerDecisionSweep({ db, now: () => NOW }, { limit: 3 }));
  assert.deepStrictEqual([r1.cancelled, r2.cancelled], [3, 2]);
  assert.strictEqual(W.SELLER_DECISION_SWEEP_LIMIT, 200);
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      loud();
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
