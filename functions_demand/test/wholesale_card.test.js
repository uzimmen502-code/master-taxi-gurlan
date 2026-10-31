/**
 * Ulgurji 3b — «yetkazilganda karta orqali» (demand codebase, FakeFirestore):
 *
 *   node functions_demand/test/wholesale_card.test.js
 *
 * Qulflanadi:
 *   - karta raqami (16 raqam, Luhn chegarasi), egasi ismi (≤60), setWholesaleSellerCard
 *     (auth, sotuvchi emas, tasdiqlanmagan, server-only private/payout, ommaviy last4, idempotent, log maska)
 *   - kvota: to'lov usuli muhri; mavjudlik matritsasi (kartasi yo'q / qarz / xaridor 1↔2 rad /
 *     balans hold−1 ↔ hold); karta mavjud emas → card_unavailable, kvota yozilmaydi
 *   - getWholesaleCardPaymentInfo, submitWholesaleCardReceipt (yo'l tekshiruvi), confirmWholesaleCardPayment
 *     (faqat sotuvchi, awaiting|receipt_submitted, idempotent, nizoda rad)
 *   - nizo sweeper: 29:59 → yo'q, 30:00 → payment_dispute, takror — AYNAN bir marta
 *   - adminResolveWholesaleCardDispute: qat'iy admin, confirm/reject, audit, idempotent, already_resolved
 *   - xabarlar: o'tishlar matritsasi, 3 til, {minutes}=30, takror trigger — bitta xabar/push
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const WO = require('../core/wholesale_orders');
const api = require('../api/wholesale_orders');
const C = require('../api/wholesale_card');
const E = require('../api/wholesale_events');
const N = require('../notify/wholesale_notify');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const BUYER = '998901110001';
const SELLER = '998901234567';
const SELLER2 = '998903330003';
const STRANGER = '998907770007';
const ADMIN = '998909990000';
const SUPER = '998906660000';
const DISP = '998908880000';
const NOW = new Date('2026-10-31T12:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const CARD = '4111111111111111';
const CARD2 = '5555555555554444';

const TARIFF = {
  module: 'logistics',
  version: 3,
  status: 'active',
  currency: 'UZS',
  volumetricDivisor: 6000,
  zones: tariffCore.ZONES,
  matrix: { regions: { xorazm: { xorazm: 'ZONE_1', toshkent_shahri: 'ZONE_4' } } },
  weightBrackets: [1000, 5000, 20000],
  prices: {
    ZONE_1: { brackets: [10000, 15000, 25000], extraPerKg: null },
    ZONE_4: { brackets: [30000, 40000, 60000], extraPerKg: 2000 },
  },
  declaredValue: { feeBps: 0, maxValue: 50000000 },
  limits: {},
  internal: { platformMarginBps: 2000, legShareBps: { first_mile: 3000, line_haul: 4000, last_mile: 3000 } },
};
const RICE = {
  sellerId: SELLER,
  title: 'Гуруч',
  status: 'active',
  market: 'wholesale',
  packs: [{
    id: 'p1', label: '1 кг', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000,
  }],
};
const DEST = { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5-kvartal' };
// 10 × 14 000 = 140 000; yetkazish 60 000 (10 kg, ZONE_4); AVA 250 bps = 3 500 → sotuvchi ushlanmasi 63 500.
const HOLD = 63500;

function makeDb(seed = {}) {
  tariffCore.clearCache();
  config.clearCache();
  const db = new FakeFirestore({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': TARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public' },
    'settings/wholesale_orders': { avaFeeBps: 250, feeVersion: 3 },
    [`wholesale_sellers/${SELLER}`]: {
      phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved', regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1',
    },
    [`wholesale_sellers/${SELLER2}`]: { phone: SELLER2, companyName: 'Kutilmoqda', approvalStatus: 'pending' },
    'wholesale_products/rice': RICE,
    'wholesale_stock/rice': { packs: { p1: 100 }, version: 1 },
    [`users/${ADMIN}`]: { role: 'admin', fcmToken: 'tokAdmin' },
    [`users/${SUPER}`]: { role: 'superadmin', appLang: 'ru' },
    [`users/${DISP}`]: { role: 'dispatcher' },
    [`users/${BUYER}`]: { role: 'user', fcmToken: 'tokBuyer', appLang: 'uz_Latn' },
    [`users/${SELLER}`]: { role: 'user', fcmToken: 'tokSeller' },
    ...seed,
  });
  db.runTransaction = async (fn) => {
    const tx = {
      get: (ref) => {
        if (tx._ops.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
        return ref.get();
      },
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}
const withCard = (extra = {}) => ({
  [`wholesale_sellers/${SELLER}/private/payout`]: { cardNumber: CARD, holderName: 'ALI VALIYEV', last4: '1111', version: 1 },
  [`ledger_accounts/passenger_credit:${SELLER}`]: { balance: HOLD },
  ...extra,
});

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
const origLog = console.log;
const origErr = console.error;
let captured = [];
const quiet = () => { captured = []; console.log = (...a) => captured.push(a.join(' ')); console.error = (...a) => captured.push(a.join(' ')); };
const loud = () => { console.log = origLog; console.error = origErr; };
async function q(fn) { quiet(); try { return await fn(); } finally { loud(); } }

const quote = (db) => api.makeQuoteWholesaleOrder({ db, now: () => NOW });
const qreq = (extra = {}) => ({ productId: 'rice', packId: 'p1', qty: 10, destination: DEST, ...extra });

const ORDER_CARD = {
  buyerId: BUYER, sellerId: SELLER, status: 'in_delivery', paymentMethod: 'card_on_delivery',
  cardPayment: { status: 'awaiting', confirmedAt: null }, goodsTotal: 140000, deliveryFee: 60000, total: 200000,
  productTitle: 'Гуруч', qty: 10, historySeq: 3, refundStatus: null,
};
const ORDER_WALLET = { ...ORDER_CARD, paymentMethod: 'wallet', cardPayment: undefined };
delete ORDER_WALLET.cardPayment;
const order = (db, id = 'o1') => db.docs.get(`wholesale_orders/${id}`);
/** Soxta Storage bucket (Admin SDK `bucket.file(p).exists/getMetadata/setMetadata` shakli). */
function fakeBucket(files) {
  const b = {
    name: 'demo-ulgcard.firebasestorage.app',
    files,
    setCalls: [],
    file(p) {
      return {
        exists: async () => [Object.prototype.hasOwnProperty.call(b.files, p)],
        getMetadata: async () => [b.files[p]],
        setMetadata: async (m) => {
          b.setCalls.push(p);
          b.files[p] = { ...b.files[p], metadata: { ...((b.files[p] || {}).metadata || {}), ...(m.metadata || {}) } };
          return [b.files[p]];
        },
      };
    },
  };
  return b;
}
const fakeMessaging = () => {
  const sent = [];
  return { sent, sendEach: async (msgs) => { sent.push(...msgs); return { responses: msgs.map(() => ({ success: true })) }; } };
};

// ─── karta raqami / ism ──────────────────────────────────────────────
ok('Luhn + 16 raqam: haqiqiy test kartalari o\'tadi; 15/17 raqam, harf, Luhn−1, satr emas — RAD', () => {
  assert.strictEqual(C.parseCardNumber('4111 1111 1111 1111'), CARD);
  assert.strictEqual(C.parseCardNumber('5555-5555-5555-4444'), CARD2);
  const bad = (v, check) => assert.throws(() => C.parseCardNumber(v), (e) => e.details.reason === 'card_number_invalid' && e.details.check === check);
  bad('411111111111111', 'format'); // 15
  bad('41111111111111111', 'format'); // 17
  bad('4111a11111111111', 'format');
  bad(4111111111111111, 'format');
  bad('4111111111111112', 'luhn'); // chegara: oxirgi raqam +1
  bad('4111111111111110', 'luhn');
  assert.strictEqual(C.luhnOk('0000000000000000'), true);
});

ok('karta egasi: 2 va 60 belgi o\'tadi; 1, 61, raqam bilan boshlanish — RAD; bo\'sh joylar siqiladi', () => {
  assert.strictEqual(C.parseHolderName('  Ali   Valiyev '), 'Ali Valiyev');
  assert.strictEqual(C.parseHolderName('Ab'), 'Ab');
  assert.strictEqual(C.parseHolderName('A'.repeat(60)).length, 60);
  assert.strictEqual(C.parseHolderName('Алишер Валиев'), 'Алишер Валиев');
  for (const v of ['A', 'A'.repeat(61), '1Ali', '', null, 'Ali<script>']) {
    assert.throws(() => C.parseHolderName(v), (e) => e.details.reason === 'holder_name_invalid', String(v));
  }
});

ok('setWholesaleSellerCard: auth; sotuvchi emas; tasdiqlanmagan — RAD, hech narsa yozilmaydi', async () => {
  const db = makeDb();
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW });
  await q(async () => {
    await rejects(set({ cardNumber: CARD, holderName: 'Ali' }, {}), 'unauthenticated');
    await rejects(set({ cardNumber: CARD, holderName: 'Ali' }, ctx(STRANGER)), 'permission-denied', 'not_wholesale_seller');
    await rejects(set({ cardNumber: CARD, holderName: 'Ali' }, ctx(SELLER2)), 'failed-precondition', 'seller_not_approved');
    await rejects(set({ cardNumber: '4111111111111112', holderName: 'Ali' }, ctx(SELLER)), 'invalid-argument', 'card_number_invalid');
    await rejects(set({ cardNumber: CARD, holderName: 'A' }, ctx(SELLER)), 'invalid-argument', 'holder_name_invalid');
  });
  assert.strictEqual(db.docs.get(`wholesale_sellers/${SELLER}/private/payout`), undefined);
  assert.strictEqual(db.docs.get(`wholesale_sellers/${SELLER}`).hasPayoutCard, undefined);
});

ok('setWholesaleSellerCard: private/payout (to\'liq) + ommaviy last4; takror — unchanged; almashtirish — v2 + tarix; log maskali', async () => {
  const db = makeDb();
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW });
  const r1 = await q(() => set({ cardNumber: '4111 1111 1111 1111', holderName: 'Ali Valiyev' }, ctx(SELLER)));
  assert.deepStrictEqual([r1.ok, r1.last4, r1.unchanged], [true, '1111', false]);
  assert.ok(captured.every((l) => !l.includes(CARD)), 'logda to\'liq raqam yo\'q');
  const p = db.docs.get(`wholesale_sellers/${SELLER}/private/payout`);
  assert.deepStrictEqual([p.cardNumber, p.holderName, p.last4, p.version, p.updatedBy], [CARD, 'Ali Valiyev', '1111', 1, SELLER]);
  const pub = db.docs.get(`wholesale_sellers/${SELLER}`);
  assert.deepStrictEqual([pub.hasPayoutCard, pub.cardLast4, pub.companyName], [true, '1111', 'Guruch savdo']);
  assert.ok(!JSON.stringify(pub).includes(CARD), 'ommaviy hujjatda to\'liq raqam yo\'q');
  const r2 = await q(() => set({ cardNumber: CARD, holderName: 'Ali Valiyev' }, ctx(SELLER)));
  assert.strictEqual(r2.unchanged, true);
  assert.strictEqual(db.docs.get(`wholesale_sellers/${SELLER}/private/payout`).version, 1);
  const r3 = await q(() => set({ cardNumber: CARD2, holderName: 'Ali Valiyev' }, ctx(SELLER)));
  assert.strictEqual(r3.last4, '4444');
  const h2 = db.docs.get(`wholesale_sellers/${SELLER}/private/payout/history/v2`);
  assert.deepStrictEqual([h2.last4, h2.prevLast4, h2.version], ['4444', '1111', 2]);
  assert.ok(!JSON.stringify(h2).includes(CARD2), 'tarixda faqat last4');
  assert.strictEqual(db.docs.get(`wholesale_sellers/${SELLER}`).cardLast4, '4444');
});

// ─── kvota: muhr va mavjudlik matritsasi ─────────────────────────────
ok('kvota (hamyon, standart): paymentMethods javobda; karta yo\'q → seller_no_card; muhr paymentMethod=wallet', async () => {
  const db = makeDb();
  const r = await q(() => quote(db)(qreq(), ctx(BUYER)));
  assert.strictEqual(r.paymentMethod, 'wallet');
  assert.deepStrictEqual(r.paymentMethods, { wallet: true, card_on_delivery: false });
  assert.strictEqual(r.cardUnavailableReason, 'seller_no_card');
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.strictEqual(qd.paymentMethod, 'wallet');
  assert.strictEqual(qd.cardHold, undefined);
  for (const k of ['cardHold', 'avaFee', 'sellerPayout']) assert.ok(!(k in r), `${k} xaridorga ko'rinmaydi`);
});

ok('kvota mavjudlik matritsasi: qarz → seller_debt; rad 1 → ochiq, 2 → buyer_limited; balans hold−1 → seller_balance, hold → ochiq', async () => {
  const cases = [
    [withCard({ [`wholesale_seller_stats/${SELLER}`]: { cardBlocked: true } }), false, 'seller_debt'],
    [withCard({ [`wholesale_buyer_stats/${BUYER}`]: { cardRefusals: 1 } }), true, null],
    [withCard({ [`wholesale_buyer_stats/${BUYER}`]: { cardRefusals: 2 } }), false, 'buyer_limited'],
    [withCard({ [`ledger_accounts/passenger_credit:${SELLER}`]: { balance: HOLD - 1 } }), false, 'seller_balance'],
    [withCard(), true, null],
    [withCard({ [`ledger_accounts/passenger_credit:${SELLER}`]: undefined }), false, 'seller_balance'],
    [withCard({ [`wholesale_seller_stats/${SELLER}`]: { cardBlocked: false } }), true, null],
  ];
  for (const [seed, avail, reason] of cases) {
    const db = makeDb(seed);
    for (const [k, v] of Object.entries(seed)) if (v === undefined) db.docs.delete(k);
    const r = await q(() => quote(db)(qreq(), ctx(BUYER)));
    assert.deepStrictEqual([r.paymentMethods.card_on_delivery, r.cardUnavailableReason], [avail, reason], JSON.stringify(seed));
  }
});

ok('kvota card_on_delivery: ochiq → muhr paymentMethod + cardHold = deliveryFee+avaFee; yopiq → card_unavailable, kvota YOZILMAYDI; noto\'g\'ri usul RAD', async () => {
  let db = makeDb(withCard());
  const r = await q(() => quote(db)(qreq({ paymentMethod: 'card_on_delivery' }), ctx(BUYER)));
  assert.strictEqual(r.paymentMethod, 'card_on_delivery');
  assert.strictEqual(r.total, 200000, 'eshik oldida: tovar + yetkazish');
  const qd = db.dump('wholesale_quotes')[r.quoteId];
  assert.deepStrictEqual([qd.paymentMethod, qd.cardHold, qd.deliveryFee + qd.avaFee], ['card_on_delivery', HOLD, HOLD]);
  db = makeDb(withCard({ [`wholesale_buyer_stats/${BUYER}`]: { cardRefusals: 2 } }));
  const e = await q(() => rejects(quote(db)(qreq({ paymentMethod: 'card_on_delivery' }), ctx(BUYER)), 'failed-precondition', 'card_unavailable'));
  assert.strictEqual(e.details.cardUnavailableReason, 'buyer_limited');
  assert.strictEqual(Object.keys(db.dump('wholesale_quotes')).length, 0);
  await q(() => rejects(quote(db)(qreq({ paymentMethod: 'cash' }), ctx(BUYER)), 'invalid-argument', 'payment_method_invalid'));
  assert.strictEqual(api.parseQuoteRequest(qreq({ paymentMethod: '' })).paymentMethod, 'wallet');
});

// ─── xaridor: to'lov ma'lumoti, chek ─────────────────────────────────
ok('getWholesaleCardPaymentInfo: xaridor — summa/karta/egasi/sotuvchi; begona, hamyon, holat, kartasiz — RAD', async () => {
  const db = makeDb(withCard({
    'wholesale_orders/o1': ORDER_CARD,
    'wholesale_orders/w1': ORDER_WALLET,
    'wholesale_orders/p1': { ...ORDER_CARD, status: 'placed' },
  }));
  const info = C.makeGetWholesaleCardPaymentInfo({ db });
  const r = await q(() => info({ orderId: 'o1' }, ctx(BUYER)));
  assert.deepStrictEqual(r, { amount: 200000, cardNumber: CARD, holderName: 'ALI VALIYEV', sellerName: 'Guruch savdo' });
  assert.ok(captured.every((l) => !l.includes(CARD)));
  await q(async () => {
    await rejects(info({ orderId: 'o1' }, ctx(SELLER)), 'permission-denied', 'not_order_party');
    await rejects(info({ orderId: 'o1' }, {}), 'unauthenticated');
    await rejects(info({ orderId: 'w1' }, ctx(BUYER)), 'failed-precondition', 'not_card_order');
    await rejects(info({ orderId: 'p1' }, ctx(BUYER)), 'failed-precondition', 'order_not_in_delivery');
    db.docs.delete(`wholesale_sellers/${SELLER}/private/payout`);
    await rejects(info({ orderId: 'o1' }, ctx(BUYER)), 'failed-precondition', 'seller_no_card');
  });
});

ok('submitWholesaleCardReceipt: yo\'l tekshiruvi (prefiks, boshqa tel, boshqa buyurtma, .., fayl nomi); 9 xonali tel o\'tadi', () => {
  const okPath = `wholesale_receipts/${BUYER}/o1/chek1.jpg`;
  assert.strictEqual(C.parseReceiptPath(okPath, BUYER, 'o1'), okPath);
  assert.ok(C.parseReceiptPath(`wholesale_receipts/${BUYER.slice(3)}/o1/a.png`, BUYER, 'o1'));
  for (const p of [
    `receipts/${BUYER}/o1/a.jpg`, `wholesale_receipts/${STRANGER}/o1/a.jpg`, `wholesale_receipts/${BUYER}/o2/a.jpg`,
    `wholesale_receipts/${BUYER}/o1/../x.jpg`, `wholesale_receipts/${BUYER}/o1/.hidden`, `wholesale_receipts/${BUYER}/o1/a b.jpg`,
    `/wholesale_receipts/${BUYER}/o1/a.jpg`, `wholesale_receipts/${BUYER}/o1/x/a.jpg`, '', null,
  ]) {
    assert.throws(() => C.parseReceiptPath(p, BUYER, 'o1'), (e) => e.details.reason === 'receipt_path_invalid', String(p));
  }
});

ok('submitWholesaleCardReceipt: xaridor → receipt_submitted (+submittedAt, history); o\'sha yo\'l — idempotent; boshqa yo\'l / sotuvchi / tasdiqlangan — RAD', async () => {
  const db = makeDb({
    'wholesale_orders/o1': ORDER_CARD,
    'wholesale_orders/c1': { ...ORDER_CARD, cardPayment: { status: 'confirmed' } },
    'wholesale_orders/w1': ORDER_WALLET,
  });
  const path = `wholesale_receipts/${BUYER}/o1/chek.jpg`;
  const bucket = fakeBucket({});
  const sub = C.makeSubmitWholesaleCardReceipt({ db, now: () => NOW, getBucket: () => bucket });
  // Fayl Storage'da yo'q — receipt_not_found, buyurtma o'zgarmaydi.
  await q(() => rejects(sub({ orderId: 'o1', receiptPath: path }, ctx(BUYER)), 'failed-precondition', 'receipt_not_found'));
  assert.strictEqual(order(db).cardPayment.status, 'awaiting');
  bucket.files[path] = { contentType: 'image/jpeg', metadata: {} };
  const r1 = await q(() => sub({ orderId: 'o1', receiptPath: path }, ctx(BUYER)));
  assert.deepStrictEqual([r1.cardPaymentStatus, r1.idempotent], ['receipt_submitted', false]);
  const o = order(db);
  assert.deepStrictEqual([o.cardPayment.status, o.cardPayment.receiptPath, o.cardPayment.submittedAt.getTime()], ['receipt_submitted', path, NOW.getTime()]);
  // Token yo'q edi — tasodifiy token yozildi; havola standart Firebase token shaklida (sotuvchi shuni ko'radi).
  const tok = bucket.files[path].metadata.firebaseStorageDownloadTokens;
  assert.ok(/^[0-9a-f-]{36}$/.test(tok), tok);
  assert.strictEqual(o.cardPayment.receiptUrl,
    `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${tok}`);
  assert.deepStrictEqual(bucket.setCalls, [path]);
  assert.strictEqual(o.status, 'in_delivery');
  assert.strictEqual(db.docs.get('wholesale_orders/o1/history/4').event, 'card_receipt_submitted');
  assert.strictEqual((await q(() => sub({ orderId: 'o1', receiptPath: path }, ctx(BUYER)))).idempotent, true);
  assert.strictEqual(order(db).historySeq, 4);
  assert.deepStrictEqual(bucket.setCalls, [path], 'takror — Storage\'ga qayta yozilmaydi');
  await q(async () => {
    await rejects(sub({ orderId: 'o1', receiptPath: `wholesale_receipts/${BUYER}/o1/b.jpg` }, ctx(BUYER)), 'failed-precondition', 'receipt_already_submitted');
    await rejects(sub({ orderId: 'o1', receiptPath: path }, ctx(SELLER)), 'permission-denied', 'not_order_party');
    await rejects(sub({ orderId: 'c1', receiptPath: `wholesale_receipts/${BUYER}/c1/a.jpg` }, ctx(BUYER)), 'failed-precondition', 'card_payment_confirmed');
    await rejects(sub({ orderId: 'w1', receiptPath: `wholesale_receipts/${BUYER}/w1/a.jpg` }, ctx(BUYER)), 'failed-precondition', 'not_card_order');
    await rejects(sub({ orderId: 'o1', receiptPath: `wholesale_receipts/${STRANGER}/o1/a.jpg` }, ctx(BUYER)), 'invalid-argument', 'receipt_path_invalid');
  });
});

ok('receiptDownloadUrl: mavjud token qayta ishlatiladi (setMetadata yo\'q); rasm emas — receipt_not_image; bucket berilmagan — storage_unavailable', async () => {
  const p = `wholesale_receipts/${BUYER}/o1/a b+c.jpg`;
  const b = fakeBucket({ [p]: { contentType: 'image/png', metadata: { firebaseStorageDownloadTokens: 'tok1,tok2' } } });
  const url = await C.receiptDownloadUrl(() => b, p);
  assert.strictEqual(url, `https://firebasestorage.googleapis.com/v0/b/${b.name}/o/wholesale_receipts%2F${BUYER}%2Fo1%2Fa%20b%2Bc.jpg?alt=media&token=tok1`);
  assert.deepStrictEqual(b.setCalls, []);
  b.files.x = { contentType: 'application/pdf' };
  await rejects(C.receiptDownloadUrl(() => b, 'x'), 'invalid-argument', 'receipt_not_image');
  await rejects(C.receiptDownloadUrl(undefined, p), 'internal', 'storage_unavailable');
});

// ─── sotuvchi: «Pul tushdi» ──────────────────────────────────────────
ok('confirmWholesaleCardPayment: faqat sotuvchi; awaiting va receipt_submitted dan o\'tadi; takror idempotent; nizo/holat/hamyon — RAD', async () => {
  const db = makeDb({
    'wholesale_orders/o1': ORDER_CARD,
    'wholesale_orders/o2': { ...ORDER_CARD, cardPayment: { status: 'receipt_submitted', receiptPath: 'x', submittedAt: NOW } },
    'wholesale_orders/d1': { ...ORDER_CARD, status: 'payment_dispute', cardPayment: { status: 'disputed' } },
    'wholesale_orders/p1': { ...ORDER_CARD, status: 'placed' },
    'wholesale_orders/w1': ORDER_WALLET,
  });
  const confirm = C.makeConfirmWholesaleCardPayment({ db, now: () => NOW });
  await q(async () => {
    await rejects(confirm({ orderId: 'o1' }, ctx(BUYER)), 'permission-denied', 'not_order_party');
    await rejects(confirm({ orderId: 'o1' }, ctx(STRANGER)), 'permission-denied', 'not_order_party');
    await rejects(confirm({ orderId: 'o1' }, {}), 'unauthenticated');
  });
  const r1 = await q(() => confirm({ orderId: 'o1' }, ctx(SELLER)));
  assert.deepStrictEqual([r1.cardPaymentStatus, r1.idempotent], ['confirmed', false]);
  const o = order(db);
  assert.deepStrictEqual([o.cardPayment.status, o.cardPayment.confirmedBy, o.cardPayment.confirmedVia], ['confirmed', SELLER, 'seller']);
  assert.strictEqual(o.status, 'in_delivery', 'holat o\'zgarmaydi — faqat to\'lov belgisi');
  assert.strictEqual(db.docs.get('wholesale_orders/o1/history/4').event, 'card_payment_confirmed');
  assert.strictEqual((await q(() => confirm({ orderId: 'o1' }, ctx(SELLER)))).idempotent, true);
  assert.strictEqual(order(db).historySeq, 4);
  assert.strictEqual((await q(() => confirm({ orderId: 'o2' }, ctx(SELLER)))).cardPaymentStatus, 'confirmed');
  await q(async () => {
    await rejects(confirm({ orderId: 'd1' }, ctx(SELLER)), 'failed-precondition', 'payment_disputed');
    await rejects(confirm({ orderId: 'p1' }, ctx(SELLER)), 'failed-precondition', 'order_not_in_delivery');
    await rejects(confirm({ orderId: 'w1' }, ctx(SELLER)), 'failed-precondition', 'not_card_order');
  });
});

// ─── nizo: 30 daqiqa ─────────────────────────────────────────────────
ok('nizo muddati YAGONA konstanta: 30 daqiqa; xabar matnida ham 30', () => {
  assert.strictEqual(WO.RECEIPT_TIMEOUT_MS, 30 * 60 * 1000);
  assert.strictEqual(WO.RECEIPT_TIMEOUT_MINUTES, 30);
  for (const lang of N.LANGS) assert.ok(N.render('ws_card_receipt', lang, { product: 'X', amount: 1 }).body.includes('30'), lang);
  assert.ok(N.render('ws_dispute_admin', 'ru', { orderId: 'o1' }).body.includes('30 минут'));
});

ok('nizo sweeper: 29:59 → yo\'q; 30:00 → payment_dispute (system, history); takror — AYNAN bir marta; tasdiqlangan/boshqa holat tegilmaydi', async () => {
  const T = NOW.getTime();
  const sub = (ms) => ({ ...ORDER_CARD, cardPayment: { status: 'receipt_submitted', receiptPath: 'p', submittedAt: new Date(T - ms) } });
  const db = makeDb({
    'wholesale_orders/o1': sub(0),
    'wholesale_orders/o2': { ...sub(0), status: 'delivered' },
    'wholesale_orders/o3': { ...ORDER_CARD, cardPayment: { status: 'confirmed', submittedAt: new Date(T) } },
  });
  const at = (ms) => () => new Date(T + ms);
  let r = await q(() => C.runWholesaleCardDisputeSweep({ db, now: at(30 * 60 * 1000 - 1000) }));
  assert.deepStrictEqual([r.disputed, r.young], [0, 1]);
  assert.strictEqual(order(db).status, 'in_delivery');
  r = await q(() => C.runWholesaleCardDisputeSweep({ db, now: at(30 * 60 * 1000) }));
  assert.strictEqual(r.disputed, 1);
  const o = order(db);
  assert.deepStrictEqual([o.status, o.cardPayment.status, o.dispute.reason], ['payment_dispute', 'disputed', 'receipt_timeout']);
  const h = db.docs.get('wholesale_orders/o1/history/4');
  assert.deepStrictEqual([h.from, h.to, h.actor, h.event], ['in_delivery', 'payment_dispute', 'system', 'card_payment_timeout']);
  r = await q(() => C.runWholesaleCardDisputeSweep({ db, now: at(60 * 60 * 1000) }));
  assert.strictEqual(r.disputed, 0);
  assert.strictEqual(order(db).historySeq, 4);
  assert.strictEqual(order(db, 'o2').status, 'delivered');
  assert.strictEqual(order(db, 'o3').status, 'in_delivery');
});

ok('kuryer chek yuborilgan buyurtmani refused qila olmaydi — holatlar jadvali: courier faqat in_delivery → refused', () => {
  assert.ok(WO.canActorTransition('courier', 'in_delivery', 'refused'));
  assert.ok(!WO.canActorTransition('courier', 'payment_dispute', 'refused'));
  assert.ok(WO.canActorTransition('admin', 'payment_dispute', 'refused'));
  assert.ok(WO.canActorTransition('admin', 'payment_dispute', 'in_delivery'));
  assert.ok(WO.canActorTransition('system', 'in_delivery', 'payment_dispute'));
  assert.ok(WO.canActorTransition('system', 'refused', 'returning'));
  assert.ok(WO.canActorTransition('system', 'returning', 'returned'));
  assert.ok(!WO.canTransition('refused', 'returned'), 'qaytish to\'lanmasdan returned yo\'q');
  assert.ok(!WO.canTransition('refused', 'in_delivery'));
  assert.ok(WO.isTerminal('returned'));
  assert.ok(!WO.canActorTransition('buyer', 'in_delivery', 'refused'));
});

ok('yo\'qolish: faqat system, faqat in_delivery | payment_dispute → lost; lost — oxirgi holat; boshqa aktyor/holat — yo\'q', () => {
  assert.strictEqual(WO.STATUS.LOST, 'lost');
  assert.deepStrictEqual([...WO.LOST_FROM_STATUSES], ['in_delivery', 'payment_dispute']);
  for (const from of WO.LOST_FROM_STATUSES) assert.ok(WO.canActorTransition('system', from, 'lost'), from);
  for (const actor of ['buyer', 'admin', 'courier', 'seller']) {
    for (const from of WO.LOST_FROM_STATUSES) assert.ok(!WO.canActorTransition(actor, from, 'lost'), `${actor}:${from}`);
  }
  const into = Object.keys(WO.ALLOWED).filter((s) => WO.ALLOWED[s].includes('lost')).sort();
  assert.deepStrictEqual(into, ['in_delivery', 'payment_dispute']);
  for (const from of ['placed', 'cancelled', 'delivered', 'refused', 'returning', 'returned']) {
    assert.ok(!WO.canTransition(from, 'lost'), from);
  }
  assert.ok(WO.isTerminal('lost'));
  assert.ok(!WO.needsRefund('lost'), 'lost — REFUND_STATUSES oqimi emas (settleLost alohida)');
  assert.deepStrictEqual({ ...WO.LOST_PAYMENT }, { REFUNDED: 'refunded_lost', REVIEW: 'lost_review' });
});

// ─── admin: nizoni hal qilish ────────────────────────────────────────
ok('adminResolveWholesaleCardDispute: oddiy/dispatcher RAD; nizo yo\'q — not_in_dispute; confirm → in_delivery + confirmed + audit; takror idempotent; keyin reject — already_resolved', async () => {
  const db = makeDb({
    'wholesale_orders/d1': { ...ORDER_CARD, status: 'payment_dispute', cardPayment: { status: 'disputed' }, dispute: { reason: 'receipt_timeout', resolution: null } },
    'wholesale_orders/o1': ORDER_CARD,
  });
  const resolve = C.makeAdminResolveWholesaleCardDispute({ db, now: () => NOW });
  await q(async () => {
    await rejects(resolve({ orderId: 'd1', decision: 'confirm' }, ctx(SELLER)), 'permission-denied');
    await rejects(resolve({ orderId: 'd1', decision: 'confirm' }, ctx(DISP)), 'permission-denied');
    await rejects(resolve({ orderId: 'd1', decision: 'maybe' }, ctx(ADMIN)), 'invalid-argument', 'decision_invalid');
    await rejects(resolve({ orderId: 'o1', decision: 'confirm' }, ctx(ADMIN)), 'failed-precondition', 'not_in_dispute');
  });
  const r = await q(() => resolve({ orderId: 'd1', decision: 'confirm', reason: 'karta ko\'rildi' }, ctx(ADMIN)));
  assert.deepStrictEqual([r.status, r.idempotent], ['in_delivery', false]);
  const o = order(db, 'd1');
  assert.deepStrictEqual([o.status, o.cardPayment.status, o.cardPayment.confirmedVia, o.dispute.resolution, o.dispute.resolvedBy],
    ['in_delivery', 'confirmed', 'admin', 'confirm', ADMIN]);
  const audit = Object.values(db.dump('admin_audit'));
  assert.strictEqual(audit.length, 1);
  assert.deepStrictEqual([audit[0].kind, audit[0].actor, audit[0].from, audit[0].to, audit[0].detail.decision],
    ['wholesale_card_dispute', ADMIN, 'payment_dispute', 'in_delivery', 'confirm']);
  assert.strictEqual((await q(() => resolve({ orderId: 'd1', decision: 'confirm' }, ctx(SUPER)))).idempotent, true);
  await q(() => rejects(resolve({ orderId: 'd1', decision: 'reject', reason: 'boshqa' }, ctx(ADMIN)), 'failed-precondition', 'already_resolved'));
  assert.strictEqual(Object.keys(db.dump('admin_audit')).length, 1);
});

ok('admin reject: sabab majburiy; → refused (refundStatus pending, returnStatus pending_shipment, xaridor hisoblagichi +1) + audit; takror idempotent', async () => {
  const db = makeDb({
    'wholesale_orders/d1': {
      ...ORDER_CARD, status: 'payment_dispute', cardPayment: { status: 'disputed' }, dispute: { resolution: null }, shipment: { shipmentId: 'S1' },
    },
    [`wholesale_buyer_stats/${BUYER}`]: { cardRefusals: 1 },
  });
  const resolve = C.makeAdminResolveWholesaleCardDispute({ db, now: () => NOW });
  await q(() => rejects(resolve({ orderId: 'd1', decision: 'reject' }, ctx(ADMIN)), 'invalid-argument', 'reason_required'));
  const r = await q(() => resolve({ orderId: 'd1', decision: 'reject', reason: 'pul tushmagan' }, ctx(ADMIN)));
  assert.strictEqual(r.status, 'refused');
  const o = order(db, 'd1');
  assert.deepStrictEqual([o.status, o.refundStatus, o.returnStatus, o.refusal.via, o.refusal.by, o.dispute.resolution],
    ['refused', 'pending', 'pending_shipment', 'admin_dispute', ADMIN, 'reject']);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 2);
  assert.strictEqual((await q(() => resolve({ orderId: 'd1', decision: 'reject', reason: 'pul tushmagan' }, ctx(ADMIN)))).idempotent, true);
  assert.strictEqual(db.docs.get(`wholesale_buyer_stats/${BUYER}`).cardRefusals, 2, 'takror — hisoblagich o\'zgarmaydi');
  assert.strictEqual(Object.keys(db.dump('admin_audit')).length, 1);
});

// ─── xabarlar ────────────────────────────────────────────────────────
ok('transitionNotifications: o\'tishlar matritsasi (chek, tasdiq, rad, nizo, qarz, kuryer, returning, returned); hech narsa o\'zgarmasa — bo\'sh', () => {
  const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`);
  const base = { ...ORDER_CARD };
  assert.deepStrictEqual(keys(base, base), []);
  assert.deepStrictEqual(keys(base, { ...base, cardPayment: { status: 'receipt_submitted' } }), ['seller:ws_card_receipt']);
  assert.deepStrictEqual(keys(base, { ...base, cardPayment: { status: 'confirmed' } }), ['buyer:ws_card_confirmed']);
  assert.deepStrictEqual(keys(base, { ...base, status: 'refused' }), ['buyer:ws_refused_buyer', 'seller:ws_refused_seller']);
  assert.deepStrictEqual(keys(base, { ...base, status: 'payment_dispute' }), ['admins:ws_dispute_admin']);
  const ref = { ...base, status: 'refused' };
  assert.deepStrictEqual(keys(ref, { ...ref, returnDebt: { amount: 1 } }), ['seller:ws_return_debt_seller', 'admins:ws_return_debt_admin']);
  assert.deepStrictEqual(keys(ref, { ...ref, returnShipment: { shipmentId: 'R', courierId: STRANGER } }), ['courier:ws_return_courier']);
  assert.deepStrictEqual(keys(ref, { ...ref, status: 'returning' }), ['seller:ws_returning_seller']);
  assert.deepStrictEqual(keys({ ...ref, status: 'returning' }, { ...ref, status: 'returned' }), ['seller:ws_returned_seller']);
  // Hamyon buyurtmasida karta xabarlari yo'q.
  assert.deepStrictEqual(keys(ORDER_WALLET, { ...ORDER_WALLET, cardPayment: { status: 'confirmed' } }), []);
});

ok('transitionNotifications (yo\'qolish): hamyon / karta / karta-review kalitlari; takror lost → lost — bo\'sh; {refund} matnda', () => {
  const keys = (b, a) => E.transitionNotifications(b, a).map((x) => `${x.to}:${x.key}`);
  const w = { ...ORDER_WALLET, status: 'in_delivery' };
  const wl = { ...w, status: 'lost', payment: { status: 'refunded_lost', lostRefund: 140000 } };
  assert.deepStrictEqual(keys(w, wl), ['buyer:ws_lost_buyer_wallet', 'seller:ws_lost_seller']);
  assert.deepStrictEqual(keys(wl, wl), []);
  const c = { ...ORDER_CARD, status: 'in_delivery' };
  assert.deepStrictEqual(keys(c, { ...c, status: 'lost', payment: { status: 'refunded_lost', lostRefund: 3500 } }),
    ['buyer:ws_lost_buyer_card', 'seller:ws_lost_seller']);
  const d = { ...ORDER_CARD, status: 'payment_dispute' };
  assert.deepStrictEqual(keys(d, { ...d, status: 'lost', payment: { status: 'lost_review', lostRefund: 0 } }),
    ['buyer:ws_lost_buyer_review', 'seller:ws_lost_seller', 'admins:ws_lost_review_admin']);
  for (const k of ['ws_lost_buyer_wallet', 'ws_lost_buyer_card', 'ws_lost_buyer_review', 'ws_lost_seller', 'ws_lost_review_admin']) {
    for (const lang of N.LANGS) {
      const m = N.render(k, lang, { product: 'Гуруч', qty: 10, refund: 140000, orderId: 'o1' });
      assert.ok(m.title && m.body && !/\{\w+\}/.test(m.title + m.body), `${k}/${lang}`);
    }
  }
  assert.ok(N.render('ws_lost_buyer_wallet', 'uz_Latn', { refund: 140000 }).body.includes('140000'));
});

ok('xabar yetkazish: inbox (3 til, foydalanuvchi tili) + push; takror trigger — bitta xabar, bitta push; adminlar (admin+superadmin, dispatcher EMAS)', async () => {
  const db = makeDb({ 'wholesale_orders/o1': ORDER_CARD });
  const messaging = fakeMessaging();
  const deps = { db, messaging, now: () => NOW };
  const before = ORDER_CARD;
  const after = { ...ORDER_CARD, cardPayment: { status: 'confirmed' } };
  await q(() => E.onWholesaleOrderUpdated(deps, before, after, 'o1'));
  await q(() => E.onWholesaleOrderUpdated(deps, before, after, 'o1'));
  const news = Object.values(db.dump('admin_news'));
  assert.strictEqual(news.length, 1);
  assert.deepStrictEqual([news[0].targetUserId, news[0].dataType, news[0].pushDirect, news[0].audience], [BUYER, 'ws_card_confirmed', true, 'user']);
  assert.strictEqual(news[0].title, N.render('ws_card_confirmed', 'uz_Latn', {}).title, 'xaridor tili uz_Latn');
  assert.ok(news[0].body.includes('200000'), JSON.stringify(news[0]));
  assert.strictEqual(messaging.sent.length, 1);
  assert.deepStrictEqual([messaging.sent[0].token, messaging.sent[0].data.orderId, messaging.sent[0].data.event], ['tokBuyer', 'o1', 'ws_card_confirmed']);
  // Nizo → adminlar.
  await q(() => E.onWholesaleOrderUpdated(deps, ORDER_CARD, { ...ORDER_CARD, status: 'payment_dispute' }, 'o1'));
  const adminNews = Object.values(db.dump('admin_news')).filter((n) => n.dataType === 'ws_dispute_admin');
  assert.deepStrictEqual(adminNews.map((n) => n.targetUserId).sort(), [ADMIN, SUPER].sort());
  assert.ok(adminNews.find((n) => n.targetUserId === SUPER).title.startsWith('Оптовый'), 'superadmin tili ru');
  assert.ok(adminNews.every((n) => !n.body.includes(BUYER) && !n.body.includes(SELLER)), 'matnda telefon yo\'q');
});

ok('onWholesaleOrderCreated: karta buyurtmasi — sotuvchiga «yangi buyurtma»; hamyon — xabar yo\'q', async () => {
  const db = makeDb();
  const messaging = fakeMessaging();
  await q(() => E.notifyNewCardOrder({ db, messaging, now: () => NOW }, { ...ORDER_CARD, status: 'placed' }, 'o9'));
  await q(() => E.notifyNewCardOrder({ db, messaging, now: () => NOW }, { ...ORDER_WALLET, status: 'placed' }, 'o8'));
  const news = Object.values(db.dump('admin_news'));
  assert.strictEqual(news.length, 1);
  assert.deepStrictEqual([news[0].targetUserId, news[0].dataType], [SELLER, 'ws_card_new_order']);
  assert.strictEqual(messaging.sent[0].token, 'tokSeller');
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
