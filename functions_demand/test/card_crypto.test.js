/**
 * Ulgurji sotuvchi kartasi — Cloud KMS shifrlash (ega, 2026-10-31). Soxta KMS (REST qatlami)
 * + FakeFirestore:
 *
 *   node functions_demand/test/card_crypto.test.js
 *
 * Qulflanadi:
 *   - core/card_crypto: round trip, `kms:v1:` shakli, URL/token/AAD so'rovi, 9↔12 xonali bir AAD,
 *     AAD mos kelmasa RAD (boshqa sotuvchi / boshqa maydon), shakl/kontekst/kalit xatolari,
 *     taymaut (HTTP va token), tarmoq/503/403/token xatolari — tiplangan; xato matnida sir yo'q
 *   - setWholesaleSellerCard: ochiq matn SAQLANMAYDI; unchanged (last4 farq → KMS yo'q; teng →
 *     dekript-solishtirish); KMS ishlamasa FAIL CLOSED (hech narsa yozilmaydi); eski ochiq hujjat →
 *     shifrlanganiga almashadi; parallel o'zgarish → card_concurrent_update
 *   - getWholesaleCardPaymentInfo: KMS dekript; eski ochiq yo'l (+ legacy_plaintext_card, PII'siz);
 *     dekript xatosi / ko'chirilgan ciphertext → unavailable card_decryption_unavailable
 *   - kvota KMS'siz ishlaydi (faqat shakl); default `payoutDocHasCard` ↔ demand paritet
 *   - tools/encrypt_seller_cards.js: dry-run hech narsa yozmaydi (faqat ****last4); write — ochiq
 *     maydonlar FAQAT tekshiruvdan keyin o'chadi + audit; takror — idempotent; tekshiruv xatosi /
 *     KMS ishlamasa — ochiq qoladi; yarim migratsiyadan davom; restore-plaintext
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const { makeFakeKms } = require('./helpers/fake_kms');
const CC = require('../core/card_crypto');
const C = require('../api/wholesale_card');
const api = require('../api/wholesale_orders');
const tariffCore = require('../core/tariff');
const config = require('../core/config');
const { runMigration } = require('../tools/encrypt_seller_cards');
const DEFAULT_WO = require('../../functions/wholesale_orders');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const SELLER = '998901234567';
const SELLER_B = '998905550005';
const SELLER9 = '907770007'; // eski 9 xonali hujjat ID
const BUYER = '998901110001';
const NOW = new Date('2026-10-31T12:00:00.000Z');
const CARD = '4111111111111111';
const CARD2 = '5555555555554444';
const CARD3 = '4012888888881881';
const HOLDER = 'Ali Valiyev';
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const PAYOUT = (id) => `wholesale_sellers/${id}/private/payout`;

function withTx(db) {
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

function makeDb(seed = {}) {
  return withTx(new FakeFirestore({
    [`wholesale_sellers/${SELLER}`]: { phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved' },
    [`wholesale_sellers/${SELLER_B}`]: { phone: SELLER_B, companyName: 'Un savdo', approvalStatus: 'approved' },
    ...seed,
  }));
}

function setup(opts = {}) {
  const kms = makeFakeKms();
  const cardCrypto = CC.createCardCrypto({ fetchImpl: kms.fetchImpl, getAccessToken: kms.getAccessToken, timeoutMs: opts.timeoutMs || 200 });
  return { kms, cardCrypto };
}

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
async function cryptoRejects(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.ok(CC.isCardCryptoError(e), `CardCryptoError kutilgan: ${e && e.stack}`);
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}`);
    return e;
  }
  throw new Error(`${code} kutilgan edi`);
}

const origLog = console.log;
const origErr = console.error;
const origWarn = console.warn;
let captured = [];
const quiet = () => {
  captured = [];
  const cap = (...a) => captured.push(a.join(' '));
  console.log = cap; console.error = cap; console.warn = cap;
};
const loud = () => { console.log = origLog; console.error = origErr; console.warn = origWarn; };
async function q(fn) { quiet(); try { return await fn(); } finally { loud(); } }
const noSecretsIn = (lines, secrets) => {
  for (const l of lines) for (const s of secrets) assert.ok(!l.includes(s), `logda sir bor: «${s}» ← ${l}`);
};

const ORDER_CARD = {
  buyerId: BUYER, sellerId: SELLER, status: 'in_delivery', paymentMethod: 'card_on_delivery',
  cardPayment: { status: 'awaiting' }, goodsTotal: 140000, deliveryFee: 60000, total: 200000, historySeq: 3,
};

// ═══ core/card_crypto ═══════════════════════════════════════════════
ok('round trip: kms:v1: shakli, ochiq matn ciphertextda yo\'q; URL = endpoint/kalit:op, Bearer token, AAD = sotuvchi+maydon (base64)', async () => {
  const { kms, cardCrypto } = setup();
  const stored = await cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' });
  assert.ok(stored.startsWith('kms:v1:'), stored);
  assert.ok(CC.isEncryptedValue(stored));
  assert.ok(!stored.includes(CARD) && !Buffer.from(stored.slice(7), 'base64').toString('latin1').includes(CARD));
  const call = kms.calls[0];
  assert.strictEqual(call.url, `https://cloudkms.googleapis.com/v1/${CC.DEFAULT_KEY_NAME}:encrypt`);
  assert.strictEqual(call.auth, 'Bearer test-token');
  assert.strictEqual(Buffer.from(call.body.plaintext, 'base64').toString('utf8'), CARD);
  assert.strictEqual(Buffer.from(call.body.additionalAuthenticatedData, 'base64').toString('utf8'), `wholesale_seller_card|v1|${SELLER}|cardNumber`);
  assert.strictEqual(await cardCrypto.decryptCard(stored, { sellerId: SELLER, field: 'cardNumber' }), CARD);
  assert.strictEqual(kms.calls[1].url, `https://cloudkms.googleapis.com/v1/${CC.DEFAULT_KEY_NAME}:decrypt`);
  // Unicode ism.
  const h = await cardCrypto.encryptCard('Алишер Валиев', { sellerId: SELLER, field: 'holderName' });
  assert.strictEqual(await cardCrypto.decryptCard(h, { sellerId: SELLER, field: 'holderName' }), 'Алишер Валиев');
  // Bir xil matn — har safar boshqa ciphertext (KMS kabi, tasodifiy IV).
  assert.notStrictEqual(await cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' }), stored);
});

ok('AAD: 9 va 12 xonali ID bir xil (kanon); boshqa sotuvchi yoki boshqa maydon — KMS_INVALID_ARGUMENT (ko\'chirilgan ciphertext RAD)', async () => {
  const { cardCrypto } = setup();
  const stored = await cardCrypto.encryptCard(CARD, { sellerId: `998${SELLER9}`, field: 'cardNumber' });
  assert.strictEqual(await cardCrypto.decryptCard(stored, { sellerId: SELLER9, field: 'cardNumber' }), CARD);
  const e1 = await cryptoRejects(cardCrypto.decryptCard(stored, { sellerId: SELLER_B, field: 'cardNumber' }), 'KMS_INVALID_ARGUMENT');
  assert.deepStrictEqual([e1.httpStatus, e1.kmsStatus, e1.transient], [400, 'INVALID_ARGUMENT', false]);
  await cryptoRejects(cardCrypto.decryptCard(stored, { sellerId: `998${SELLER9}`, field: 'holderName' }), 'KMS_INVALID_ARGUMENT');
  // Buzilgan ciphertext (bitta bayt).
  const raw = Buffer.from(stored.slice(7), 'base64');
  raw[raw.length - 1] ^= 1;
  await cryptoRejects(cardCrypto.decryptCard(`kms:v1:${raw.toString('base64')}`, { sellerId: SELLER9, field: 'cardNumber' }), 'KMS_INVALID_ARGUMENT');
});

ok('shakl/kontekst/kalit xatolari — KMS chaqirilmaydi; noto\'g\'ri env kaliti yuklanishda EMAS, chaqiruvda; env kaliti ishlatiladi', async () => {
  const { kms, cardCrypto } = setup();
  for (const bad of ['4111111111111111', 'kms:v1:', 'kms:v2:QUJD', 'kms:v1:not base64!', null, 42]) {
    await cryptoRejects(cardCrypto.decryptCard(bad, { sellerId: SELLER, field: 'cardNumber' }), 'CARD_CIPHERTEXT_FORMAT');
  }
  await cryptoRejects(cardCrypto.encryptCard(CARD, { sellerId: 'abc', field: 'cardNumber' }), 'CARD_CRYPTO_CONTEXT');
  await cryptoRejects(cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cvv' }), 'CARD_CRYPTO_CONTEXT');
  await cryptoRejects(cardCrypto.encryptCard(CARD, undefined), 'CARD_CRYPTO_CONTEXT');
  await cryptoRejects(cardCrypto.encryptCard('', { sellerId: SELLER, field: 'cardNumber' }), 'CARD_CRYPTO_INPUT');
  await cryptoRejects(cardCrypto.encryptCard('x'.repeat(257), { sellerId: SELLER, field: 'cardNumber' }), 'CARD_CRYPTO_INPUT');
  assert.strictEqual(kms.calls.length, 0);
  const prev = process.env[CC.KEY_ENV];
  try {
    process.env[CC.KEY_ENV] = 'not-a-key';
    const broken = CC.createCardCrypto({ fetchImpl: kms.fetchImpl, getAccessToken: kms.getAccessToken });
    assert.strictEqual(broken.keyName, null);
    await cryptoRejects(broken.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' }), 'KMS_KEY_NAME_INVALID');
    const other = 'projects/demo-proj/locations/europe-west1/keyRings/r1/cryptoKeys/k1';
    process.env[CC.KEY_ENV] = other;
    kms.keyName = other;
    const viaEnv = CC.createCardCrypto({ fetchImpl: kms.fetchImpl, getAccessToken: kms.getAccessToken });
    assert.strictEqual(viaEnv.keyName, other);
    await viaEnv.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' });
    assert.ok(kms.calls[kms.calls.length - 1].url.includes(`/${other}:encrypt`));
  } finally {
    if (prev === undefined) delete process.env[CC.KEY_ENV]; else process.env[CC.KEY_ENV] = prev;
  }
});

ok('KMS xatolari tiplangan: hang → KMS_TIMEOUT (abort), token hang → KMS_TIMEOUT, tarmoq → KMS_NETWORK, 503 → KMS_UNAVAILABLE, 403 → KMS_PERMISSION_DENIED, token → KMS_AUTH_FAILED; matnda sir yo\'q', async () => {
  const { kms, cardCrypto } = setup({ timeoutMs: 40 });
  const good = await cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' });
  const cases = [['hang', 'KMS_TIMEOUT', true], ['tokenHang', 'KMS_TIMEOUT', true], ['down', 'KMS_NETWORK', true],
    ['503', 'KMS_UNAVAILABLE', true], ['403', 'KMS_PERMISSION_DENIED', false], ['noauth', 'KMS_AUTH_FAILED', true]];
  for (const [mode, code, transient] of cases) {
    kms.mode = mode;
    const t0 = Date.now();
    const e1 = await cryptoRejects(cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' }), code);
    const e2 = await cryptoRejects(cardCrypto.decryptCard(good, { sellerId: SELLER, field: 'cardNumber' }), code);
    assert.ok(Date.now() - t0 < 2000, `${mode}: taymaut ishladi`);
    for (const e of [e1, e2]) {
      assert.strictEqual(e.transient, transient, mode);
      assert.ok(!e.message.includes(CARD) && !e.message.includes(good.slice(7, 30)), `${mode}: matnda sir yo'q`);
    }
  }
  kms.mode = 'ok';
  assert.strictEqual(await cardCrypto.decryptCard(good, { sellerId: SELLER, field: 'cardNumber' }), CARD, 'tiklangandan keyin ishlaydi');
});

// ═══ setWholesaleSellerCard ═══════════════════════════════════════════
ok('set: private/payout faqat *Enc + last4 + encVersion; ochiq matn hech qayerda yo\'q (hujjat, tarix, ommaviy, log); dekript — o\'sha karta', async () => {
  const { kms, cardCrypto } = setup();
  const db = makeDb();
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
  const r = await q(() => set({ cardNumber: '4111 1111 1111 1111', holderName: HOLDER }, ctx(SELLER)));
  assert.deepStrictEqual(r, { ok: true, last4: '1111', unchanged: false });
  const logs = captured;
  const p = db.docs.get(PAYOUT(SELLER));
  assert.deepStrictEqual(Object.keys(p).sort(),
    ['cardNumberEnc', 'createdAt', 'encVersion', 'holderNameEnc', 'last4', 'updatedAt', 'updatedBy', 'version'].sort());
  assert.deepStrictEqual([p.last4, p.encVersion, p.version, p.updatedBy], ['1111', 1, 1, SELLER]);
  assert.ok(p.cardNumberEnc.startsWith('kms:v1:') && p.holderNameEnc.startsWith('kms:v1:'));
  const all = JSON.stringify([...db.docs.entries()]);
  assert.ok(!all.includes(CARD) && !all.includes(HOLDER), 'Firestore\'da ochiq karta/ism yo\'q');
  noSecretsIn(logs, [CARD, HOLDER, p.cardNumberEnc.slice(7, 40), p.holderNameEnc.slice(7, 40), SELLER]);
  assert.strictEqual(kms.count('encrypt'), 2);
  assert.strictEqual(kms.count('decrypt'), 0, 'yangi hujjat — dekript yo\'q');
  assert.strictEqual(await cardCrypto.decryptCard(p.cardNumberEnc, { sellerId: SELLER, field: 'cardNumber' }), CARD);
  assert.strictEqual(await cardCrypto.decryptCard(p.holderNameEnc, { sellerId: SELLER, field: 'holderName' }), HOLDER);
  const h1 = db.docs.get(`${PAYOUT(SELLER)}/history/v1`);
  assert.deepStrictEqual([h1.last4, h1.prevLast4, h1.encVersion], ['1111', null, 1]);
  assert.deepStrictEqual([db.docs.get(`wholesale_sellers/${SELLER}`).hasPayoutCard, db.docs.get(`wholesale_sellers/${SELLER}`).cardLast4], [true, '1111']);
});

ok('set unchanged: bir xil → dekript-solishtirish (2 decrypt, 0 encrypt, 0 yozuv); last4 farq → dekript YO\'Q; last4 teng, ism boshqa → v2 (holderChanged)', async () => {
  const { kms, cardCrypto } = setup();
  const db = makeDb();
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
  await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  kms.reset();
  const w0 = db.writes;
  const before = JSON.stringify(db.docs.get(PAYOUT(SELLER)));
  const r2 = await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  assert.deepStrictEqual([r2.unchanged, kms.count('decrypt'), kms.count('encrypt'), db.writes - w0], [true, 2, 0, 0]);
  assert.strictEqual(JSON.stringify(db.docs.get(PAYOUT(SELLER))), before);
  kms.reset();
  const r3 = await q(() => set({ cardNumber: CARD2, holderName: HOLDER }, ctx(SELLER)));
  assert.deepStrictEqual([r3.unchanged, r3.last4, kms.count('decrypt'), kms.count('encrypt')], [false, '4444', 0, 2]);
  const h2 = db.docs.get(`${PAYOUT(SELLER)}/history/v2`);
  assert.deepStrictEqual([h2.last4, h2.prevLast4, h2.holderChanged], ['4444', '1111', null]);
  // Chegara: last4 bir xil (4444) lekin ism boshqa.
  kms.reset();
  const r4 = await q(() => set({ cardNumber: CARD2, holderName: 'Vali Aliyev' }, ctx(SELLER)));
  assert.deepStrictEqual([r4.unchanged, kms.count('decrypt'), kms.count('encrypt')], [false, 2, 2]);
  const p = db.docs.get(PAYOUT(SELLER));
  assert.strictEqual(p.version, 3);
  assert.strictEqual(db.docs.get(`${PAYOUT(SELLER)}/history/v3`).holderChanged, true);
  assert.strictEqual(await cardCrypto.decryptCard(p.holderNameEnc, { sellerId: SELLER, field: 'holderName' }), 'Vali Aliyev');
});

ok('set FAIL CLOSED: KMS ishlamasa (down/403/timeout) → failed-precondition card_encryption_unavailable; yangi va mavjud hujjat O\'ZGARMAYDI', async () => {
  for (const mode of ['down', '403', 'hang', 'noauth']) {
    const { kms, cardCrypto } = setup({ timeoutMs: 40 });
    const db = makeDb();
    const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
    kms.mode = mode;
    await q(() => rejects(set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)), 'failed-precondition', 'card_encryption_unavailable'));
    assert.ok(captured.some((l) => l.includes('CARD_ENCRYPTION_FAILED')), mode);
    noSecretsIn(captured, [CARD, HOLDER]);
    assert.strictEqual(db.docs.get(PAYOUT(SELLER)), undefined, `${mode}: hech narsa yozilmadi`);
    assert.strictEqual(db.docs.get(`wholesale_sellers/${SELLER}`).hasPayoutCard, undefined);
    // Mavjud karta bor — almashtirishga urinish ham hech narsani buzmaydi.
    kms.mode = 'ok';
    await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
    const snap = JSON.stringify([...db.docs.entries()]);
    kms.mode = mode;
    await q(() => rejects(set({ cardNumber: CARD2, holderName: HOLDER }, ctx(SELLER)), 'failed-precondition', 'card_encryption_unavailable'));
    // last4 teng → avval dekript (yiqiladi) → «o'zgargan» → shifrlash yiqiladi → fail closed.
    await q(() => rejects(set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)), 'failed-precondition', 'card_encryption_unavailable'));
    assert.strictEqual(JSON.stringify([...db.docs.entries()]), snap, `${mode}: mavjud hujjat o'zgarmadi`);
  }
});

ok('set: eski ochiq hujjat + bir xil karta → unchanged, lekin hujjat SHIFRLANGANIGA almashadi (versiya, tarix, ommaviy o\'zgarmaydi); boshqa karta → v2, ochiq maydonlar yo\'q', async () => {
  const { kms, cardCrypto } = setup();
  const legacy = {
    cardNumber: CARD, holderName: HOLDER, last4: '1111', version: 1, updatedAt: new Date('2026-10-30T00:00:00Z'), updatedBy: SELLER, createdAt: new Date('2026-10-30T00:00:00Z'),
  };
  const db = makeDb({ [PAYOUT(SELLER)]: legacy, [`wholesale_sellers/${SELLER}`]: { phone: SELLER, approvalStatus: 'approved', hasPayoutCard: true, cardLast4: '1111' } });
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
  const r = await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  assert.deepStrictEqual([r.unchanged, kms.count('decrypt'), kms.count('encrypt')], [true, 0, 2]);
  const p = db.docs.get(PAYOUT(SELLER));
  assert.ok(!('cardNumber' in p) && !('holderName' in p), 'ochiq maydonlar o\'chdi');
  assert.deepStrictEqual([p.version, p.last4, p.encVersion, p.updatedAt.getTime(), p.encryptedAt.getTime()], [1, '1111', 1, legacy.updatedAt.getTime(), NOW.getTime()]);
  assert.strictEqual(db.docs.get(`${PAYOUT(SELLER)}/history/v1`), undefined, 'tarix yozilmadi');
  // Endi oddiy kms unchanged.
  kms.reset();
  assert.strictEqual((await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)))).unchanged, true);
  assert.strictEqual(kms.count('encrypt'), 0);
  // Eski ochiq hujjat + BOSHQA karta.
  const db2 = makeDb({ [PAYOUT(SELLER)]: legacy });
  const set2 = C.makeSetWholesaleSellerCard({ db: db2, now: () => NOW, cardCrypto });
  const r2 = await q(() => set2({ cardNumber: CARD2, holderName: HOLDER }, ctx(SELLER)));
  const p2 = db2.docs.get(PAYOUT(SELLER));
  assert.deepStrictEqual([r2.unchanged, p2.version, 'cardNumber' in p2, 'holderName' in p2], [false, 2, false, false]);
  assert.deepStrictEqual([db2.docs.get(`${PAYOUT(SELLER)}/history/v2`).prevLast4, db2.docs.get(`${PAYOUT(SELLER)}/history/v2`).holderChanged], ['1111', false]);
});

ok('set: o\'qish va tranzaksiya orasida boshqa so\'rov kartani o\'zgartirsa → unavailable card_concurrent_update, bizniki YOZILMAYDI', async () => {
  const { cardCrypto } = setup();
  const db = makeDb();
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
  await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  const realTx = db.runTransaction;
  db.runTransaction = async (fn) => {
    // Raqib so'rov: v2 ni tranzaksiyamizdan oldin yozib qo'yadi.
    const cur = db.docs.get(PAYOUT(SELLER));
    db.docs.set(PAYOUT(SELLER), { ...cur, version: 2, last4: '1881' });
    return realTx(fn);
  };
  await q(() => rejects(set({ cardNumber: CARD2, holderName: HOLDER }, ctx(SELLER)), 'unavailable', 'card_concurrent_update'));
  assert.strictEqual(db.docs.get(PAYOUT(SELLER)).last4, '1881', 'raqib yozuvi saqlandi');
  assert.strictEqual(db.docs.get(`${PAYOUT(SELLER)}/history/v3`), undefined);
});

// ═══ getWholesaleCardPaymentInfo ══════════════════════════════════════
ok('paymentInfo: KMS hujjati dekript qilinadi; logda karta/ism/ciphertext yo\'q', async () => {
  const { kms, cardCrypto } = setup();
  const db = makeDb({ 'wholesale_orders/o1': ORDER_CARD });
  await q(() => C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto })({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  kms.reset();
  const info = C.makeGetWholesaleCardPaymentInfo({ db, cardCrypto });
  const r = await q(() => info({ orderId: 'o1' }, ctx(BUYER)));
  assert.deepStrictEqual(r, { amount: 200000, cardNumber: CARD, holderName: HOLDER, sellerName: 'Guruch savdo' });
  assert.strictEqual(kms.count('decrypt'), 2);
  const p = db.docs.get(PAYOUT(SELLER));
  noSecretsIn(captured, [CARD, HOLDER, p.cardNumberEnc.slice(7, 40), SELLER, BUYER]);
  assert.ok(!captured.some((l) => l.includes('legacy_plaintext_card')));
});

ok('paymentInfo: eski ochiq hujjat — qaytadi (KMS chaqirilmaydi) + legacy_plaintext_card ogohlantirishi PII\'siz', async () => {
  const { kms, cardCrypto } = setup();
  const db = makeDb({ 'wholesale_orders/o1': ORDER_CARD, [PAYOUT(SELLER)]: { cardNumber: CARD, holderName: 'ALI VALIYEV', last4: '1111', version: 1 } });
  kms.mode = 'down';
  const r = await q(() => C.makeGetWholesaleCardPaymentInfo({ db, cardCrypto })({ orderId: 'o1' }, ctx(BUYER)));
  assert.deepStrictEqual([r.cardNumber, r.holderName], [CARD, 'ALI VALIYEV']);
  assert.strictEqual(kms.calls.length, 0);
  const w = captured.find((l) => l.includes('legacy_plaintext_card'));
  assert.ok(w, 'ogohlantirish bor');
  const j = JSON.parse(w);
  assert.deepStrictEqual([j.action, j.orderId, j.errorCode], ['getCardPaymentInfo', 'o1', 'LEGACY_PLAINTEXT_CARD']);
  noSecretsIn(captured, [CARD, 'ALI VALIYEV', SELLER, BUYER]);
});

ok('paymentInfo: KMS ishlamasa / ciphertext boshqa sotuvchidan ko\'chirilgan → unavailable card_decryption_unavailable (umumiy matn), log kmsCode', async () => {
  const { kms, cardCrypto } = setup({ timeoutMs: 40 });
  const db = makeDb({ 'wholesale_orders/o1': ORDER_CARD });
  const set = C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto });
  await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER_B)));
  const info = C.makeGetWholesaleCardPaymentInfo({ db, cardCrypto });
  // B ning shifrlangan kartasi A hujjatiga ko'chirildi (AAD = A) → KMS rad etadi.
  db.docs.set(PAYOUT(SELLER), db.docs.get(PAYOUT(SELLER_B)));
  let e = await q(() => rejects(info({ orderId: 'o1' }, ctx(BUYER)), 'unavailable', 'card_decryption_unavailable'));
  assert.ok(!e.message.includes('KMS') && !e.message.includes(CARD));
  const line = captured.find((l) => l.includes('CARD_DECRYPTION_FAILED'));
  assert.strictEqual(JSON.parse(line).kmsCode, 'KMS_INVALID_ARGUMENT');
  // O'z kartasi, lekin KMS ishlamayapti.
  await q(() => set({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  for (const [mode, code] of [['down', 'KMS_NETWORK'], ['hang', 'KMS_TIMEOUT'], ['403', 'KMS_PERMISSION_DENIED']]) {
    kms.mode = mode;
    e = await q(() => rejects(info({ orderId: 'o1' }, ctx(BUYER)), 'unavailable', 'card_decryption_unavailable'));
    assert.strictEqual(JSON.parse(captured.find((l) => l.includes('CARD_DECRYPTION_FAILED'))).kmsCode, code);
  }
  // Dekript «muvaffaqiyatli», lekin natija karta emas → CARD_PLAINTEXT_INVALID.
  kms.mode = 'decryptWrong';
  await q(() => rejects(info({ orderId: 'o1' }, ctx(BUYER)), 'unavailable', 'card_decryption_unavailable'));
  assert.strictEqual(JSON.parse(captured.find((l) => l.includes('CARD_DECRYPTION_FAILED'))).kmsCode, 'CARD_PLAINTEXT_INVALID');
});

ok('kvota KMS\'siz: shifrlangan karta «bor» (dekript yo\'q); buzilgan *Enc / last4 yo\'q — «yo\'q»', async () => {
  const { kms, cardCrypto } = setup();
  const db = makeDb();
  await q(() => C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto })({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  kms.reset();
  kms.mode = 'down';
  const card = await C.readPayoutCard(db, SELLER);
  assert.deepStrictEqual([card.kind, card.last4, card.sellerDocId], ['kms', '1111', SELLER]);
  assert.strictEqual(kms.calls.length, 0);
  const p = db.docs.get(PAYOUT(SELLER));
  assert.strictEqual(C.payoutDocHasCard({ ...p, last4: undefined }), false);
  assert.strictEqual(C.payoutDocHasCard({ ...p, holderNameEnc: 'kms:v1:' }), false);
  assert.strictEqual(C.payoutDocHasCard({ ...p, cardNumberEnc: CARD }), false);
});

ok('kvota (quoteWholesaleOrder) shifrlangan karta bilan: card_on_delivery ochiq, KMS chaqirilmaydi', async () => {
  tariffCore.clearCache();
  config.clearCache();
  const { kms, cardCrypto } = setup();
  const TARIFF = {
    module: 'logistics', version: 3, status: 'active', currency: 'UZS', volumetricDivisor: 6000, zones: tariffCore.ZONES,
    matrix: { regions: { xorazm: { toshkent_shahri: 'ZONE_4' } } },
    weightBrackets: [1000, 5000, 20000], prices: { ZONE_4: { brackets: [30000, 40000, 60000], extraPerKg: 2000 } },
    declaredValue: { feeBps: 0, maxValue: 50000000 }, limits: {},
    internal: { platformMarginBps: 2000, legShareBps: { first_mile: 3000, line_haul: 4000, last_mile: 3000 } },
  };
  const db = makeDb({
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 3 },
    'module_tariffs/logistics_v3': TARIFF,
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public' },
    'settings/wholesale_orders': { avaFeeBps: 250, feeVersion: 3 },
    [`wholesale_sellers/${SELLER}`]: { phone: SELLER, companyName: 'Guruch savdo', approvalStatus: 'approved', regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 1' },
    'wholesale_products/rice': {
      sellerId: SELLER, title: 'Гуруч', status: 'active', market: 'wholesale',
      packs: [{ id: 'p1', label: '1 кг', priceTiers: [{ minQty: 1, price: 15000 }, { minQty: 10, price: 14000 }], unitWeightG: 1000 }],
    },
    'wholesale_stock/rice': { packs: { p1: 100 }, version: 1 },
    [`users/${BUYER}`]: { role: 'user' },
    [`users/${SELLER}`]: { role: 'user' },
    [`ledger_accounts/passenger_credit:${SELLER}`]: { balance: 63500 },
  });
  await q(() => C.makeSetWholesaleSellerCard({ db, now: () => NOW, cardCrypto })({ cardNumber: CARD, holderName: HOLDER }, ctx(SELLER)));
  kms.reset();
  kms.mode = 'down';
  const r = await q(() => api.makeQuoteWholesaleOrder({ db, now: () => NOW })({
    productId: 'rice', packId: 'p1', qty: 10, destination: { regionId: 'toshkent_shahri', districtId: 'chilonzor', addressText: 'Chilonzor 5' }, paymentMethod: 'card_on_delivery',
  }, ctx(BUYER)));
  assert.deepStrictEqual([r.paymentMethod, r.paymentMethods.card_on_delivery], ['card_on_delivery', true]);
  assert.strictEqual(kms.calls.length, 0);
});

ok('paritet: default placeWholesaleOrder payoutDocHasCard ≡ demand payoutDocHasCard (kms, eski ochiq, chegara holatlari)', async () => {
  const { cardCrypto } = setup();
  const enc = await cardCrypto.encryptCard(CARD, { sellerId: SELLER, field: 'cardNumber' });
  const encH = await cardCrypto.encryptCard(HOLDER, { sellerId: SELLER, field: 'holderName' });
  const samples = [
    {}, null, undefined,
    { cardNumber: CARD, holderName: HOLDER },
    { cardNumber: CARD, holderName: '' },
    { cardNumber: CARD },
    { cardNumber: '411111111111111', holderName: HOLDER },
    { cardNumber: 4111111111111111, holderName: HOLDER },
    { cardNumberEnc: enc, holderNameEnc: encH, last4: '1111' },
    { cardNumberEnc: enc, holderNameEnc: encH, last4: '111' },
    { cardNumberEnc: enc, holderNameEnc: encH },
    { cardNumberEnc: enc, last4: '1111' },
    { cardNumberEnc: 'kms:v1:', holderNameEnc: encH, last4: '1111' },
    { cardNumberEnc: 'kms:v2:QUJD', holderNameEnc: encH, last4: '1111' },
    { cardNumberEnc: `kms:v1:${'A'.repeat(5000)}`, holderNameEnc: encH, last4: '1111' },
    { cardNumberEnc: enc, holderNameEnc: encH, last4: '1111', cardNumber: CARD, holderName: HOLDER },
    { cardNumberEnc: 'kms:v1:bad!', holderNameEnc: encH, last4: '1111', cardNumber: CARD, holderName: HOLDER },
  ];
  const expected = [false, false, false, true, false, false, false, false, true, false, false, false, false, false, false, true, true];
  samples.forEach((s, i) => {
    assert.strictEqual(C.payoutDocHasCard(s), expected[i], `demand #${i}`);
    assert.strictEqual(DEFAULT_WO.payoutDocHasCard(s), expected[i], `default #${i}`);
  });
});

// ═══ tools/encrypt_seller_cards.js ════════════════════════════════════
async function migrationDb(cardCrypto) {
  const encOk = await cardCrypto.encryptCard(CARD3, { sellerId: '998903330003', field: 'cardNumber' });
  const encOkH = await cardCrypto.encryptCard('Kim Sen', { sellerId: '998903330003', field: 'holderName' });
  return makeDb({
    [`wholesale_sellers/${SELLER9}`]: { phone: SELLER9, approvalStatus: 'approved' },
    'wholesale_sellers/998903330003': { phone: '998903330003', approvalStatus: 'approved' },
    'wholesale_sellers/998904440004': { phone: '998904440004', approvalStatus: 'approved' },
    'wholesale_sellers/998906660006': { phone: '998906660006', approvalStatus: 'approved' },
    [PAYOUT(SELLER)]: { cardNumber: CARD, holderName: HOLDER, last4: '1111', version: 1, updatedBy: SELLER },
    [PAYOUT(SELLER9)]: { cardNumber: CARD2, holderName: 'ALI VALIYEV', last4: '4444', version: 3 },
    [PAYOUT('998903330003')]: { cardNumberEnc: encOk, holderNameEnc: encOkH, last4: '1881', encVersion: 1, version: 1 },
    [PAYOUT('998904440004')]: { cardNumber: '1234', holderName: 'X', version: 1 },
    // SELLER_B va 998906660006 — payout yo'q.
  });
}
const PLAIN_SECRETS = [CARD, CARD2, HOLDER, 'ALI VALIYEV', SELLER, SELLER9, '998903330003'];

ok('migratsiya dry-run: hisoblar to\'g\'ri, HECH NARSA yozilmaydi va KMS chaqirilmaydi; konsolda faqat ****last4 (tel/raqam/ism yo\'q)', async () => {
  const { kms, cardCrypto } = setup();
  const db = await migrationDb(cardCrypto);
  kms.reset();
  const snap = JSON.stringify([...db.docs.entries()]);
  const w0 = db.writes;
  const lines = [];
  const sum = await runMigration({ db, cardCrypto, print: (l) => lines.push(l), batchSize: 2 });
  assert.deepStrictEqual(
    [sum.write, sum.sellersScanned, sum.payoutDocs, sum.plaintext, sum.alreadyEncrypted, sum.invalid, sum.migrated, sum.failed],
    [false, 6, 4, 2, 1, 1, 0, 0],
  );
  assert.strictEqual(JSON.stringify([...db.docs.entries()]), snap);
  assert.strictEqual(db.writes, w0);
  assert.strictEqual(kms.calls.length, 0);
  assert.ok(lines.some((l) => l.includes('****1111')) && lines.some((l) => l.includes('****4444')));
  noSecretsIn(lines, PLAIN_SECRETS);
});

ok('migratsiya --write: ochiq maydonlar faqat tekshiruvdan keyin o\'chadi; audit har sotuvchiga 1; o\'qish yo\'llari ishlaydi; takror — idempotent', async () => {
  const { kms, cardCrypto } = setup();
  const db = await migrationDb(cardCrypto);
  kms.reset();
  const lines = [];
  const sum = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: (l) => lines.push(l), batchSize: 2 });
  assert.deepStrictEqual([sum.migrated, sum.failed, sum.alreadyEncrypted, sum.invalid, sum.skippedChanged], [2, 0, 1, 1, 0]);
  assert.deepStrictEqual([kms.count('encrypt'), kms.count('decrypt')], [4, 4], 'har hujjat: 2 shifr + 2 tekshiruv dekripti');
  for (const [id, card, holder, last4, version] of [[SELLER, CARD, HOLDER, '1111', 1], [SELLER9, CARD2, 'ALI VALIYEV', '4444', 3]]) {
    const p = db.docs.get(PAYOUT(id));
    assert.ok(!('cardNumber' in p) && !('holderName' in p), `${id}: ochiq maydonlar o'chdi`);
    assert.deepStrictEqual([p.last4, p.encVersion, p.version, p.encryptedBy, p.encryptedAt.getTime()], [last4, 1, version, 'tools/encrypt_seller_cards.js', NOW.getTime()]);
    assert.strictEqual(await cardCrypto.decryptCard(p.cardNumberEnc, { sellerId: id, field: 'cardNumber' }), card);
    assert.strictEqual(await cardCrypto.decryptCard(p.holderNameEnc, { sellerId: id, field: 'holderName' }), holder);
    assert.strictEqual(DEFAULT_WO.payoutDocHasCard(p), true, 'default placeWholesaleOrder kartani ko\'radi');
  }
  // 9 xonali hujjat: xaridor yo'li (sellerId 12 xonali) dekript qiladi.
  const db2 = db;
  db2.docs.set('wholesale_orders/o9', { ...ORDER_CARD, sellerId: `998${SELLER9}` });
  const r = await q(() => C.makeGetWholesaleCardPaymentInfo({ db: db2, cardCrypto })({ orderId: 'o9' }, ctx(BUYER)));
  assert.deepStrictEqual([r.cardNumber, r.holderName], [CARD2, 'ALI VALIYEV']);
  assert.strictEqual(db.docs.get(PAYOUT('998904440004')).cardNumber, '1234', 'yaroqsiz hujjat tegilmadi');
  const audits = Object.values(db.dump('admin_audit'));
  assert.strictEqual(audits.length, 2);
  for (const a of audits) {
    assert.deepStrictEqual([a.kind, a.actor, a.from, a.to], ['wholesale_card_encrypt_migration', 'tools/encrypt_seller_cards.js', 'plaintext', 'kms:v1']);
    assert.ok(!JSON.stringify(a).includes(CARD) && !JSON.stringify(a).includes(CARD2) && !JSON.stringify(a).includes(HOLDER));
  }
  noSecretsIn(lines, PLAIN_SECRETS);
  const all = JSON.stringify([...db.docs.entries()]);
  assert.ok(!all.includes(CARD) && !all.includes(CARD2) && !all.includes(HOLDER), 'Firestore\'da ochiq karta qolmadi');
  // Takror — idempotent.
  kms.reset();
  const snap = JSON.stringify([...db.docs.entries()]);
  const again = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: () => {} });
  assert.deepStrictEqual([again.migrated, again.alreadyEncrypted, again.plaintext], [0, 3, 0]);
  assert.strictEqual(JSON.stringify([...db.docs.entries()]), snap);
  assert.strictEqual(kms.calls.length, 0);
});

ok('migratsiya: tekshiruv mos kelmasa — *Enc olib tashlanadi, ochiq QOLADI, audit yo\'q; KMS ishlamasa — hech narsa o\'zgarmaydi', async () => {
  const { kms, cardCrypto } = setup({ timeoutMs: 40 });
  let db = await migrationDb(cardCrypto);
  const before = db.docs.get(PAYOUT(SELLER));
  kms.mode = 'decryptWrong';
  let sum = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: () => {} });
  assert.deepStrictEqual([sum.migrated, sum.failed], [0, 2]);
  assert.deepStrictEqual(db.docs.get(PAYOUT(SELLER)), before, 'hujjat asl holatiga qaytdi');
  assert.strictEqual(Object.keys(db.dump('admin_audit')).length, 0);
  for (const mode of ['down', 'hang', '403']) {
    db = await (async () => { kms.mode = 'ok'; return migrationDb(cardCrypto); })();
    const snap = JSON.stringify([...db.docs.entries()]);
    kms.mode = mode;
    const lines = [];
    sum = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: (l) => lines.push(l) });
    assert.deepStrictEqual([sum.migrated, sum.failed], [0, 2], mode);
    assert.strictEqual(JSON.stringify([...db.docs.entries()]), snap, `${mode}: o'zgarmadi`);
    noSecretsIn(lines, PLAIN_SECRETS);
  }
});

ok('migratsiya: yarim holat (ochiq + *Enc, B dan keyin uzilgan) — tekshiruvdan davom etadi; --limit; restore-plaintext → eski kod o\'qiydi, keyingi --write yana tozalaydi', async () => {
  const { kms, cardCrypto } = setup();
  const db = await migrationDb(cardCrypto);
  // Tartib: hujjat ID bo'yicha — SELLER9 ('907…') birinchi; yarim holat shunda.
  const enc = await cardCrypto.encryptCard(CARD2, { sellerId: SELLER9, field: 'cardNumber' });
  const encH = await cardCrypto.encryptCard('ALI VALIYEV', { sellerId: SELLER9, field: 'holderName' });
  db.docs.set(PAYOUT(SELLER9), { ...db.docs.get(PAYOUT(SELLER9)), cardNumberEnc: enc, holderNameEnc: encH, encVersion: 1 });
  kms.reset();
  let sum = await runMigration({ db, cardCrypto, write: true, limit: 1, now: () => NOW, print: () => {} });
  assert.deepStrictEqual([sum.halfMigrated, sum.plaintext, sum.migrated], [1, 1, 1]);
  assert.deepStrictEqual([kms.count('encrypt'), kms.count('decrypt')], [0, 2], 'yarim holat — qayta shifrlanmaydi');
  assert.strictEqual(db.docs.get(PAYOUT(SELLER9)).cardNumberEnc, enc);
  assert.ok(!('cardNumber' in db.docs.get(PAYOUT(SELLER9))));
  assert.strictEqual(db.docs.get(PAYOUT(SELLER)).cardNumber, CARD, '--limit 1: ikkinchisi tegilmadi');
  assert.strictEqual(Object.values(db.dump('admin_audit'))[0].from, 'plaintext+kms:v1');
  sum = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: () => {} });
  assert.strictEqual(sum.migrated, 1);
  // Restore (rollback uchun): dry-run hech narsa yozmaydi; write — ochiq maydonlar qaytadi, *Enc saqlanadi.
  const snap = JSON.stringify([...db.docs.entries()]);
  sum = await runMigration({ db, cardCrypto, restorePlaintext: true, print: () => {} });
  assert.strictEqual(JSON.stringify([...db.docs.entries()]), snap);
  sum = await runMigration({ db, cardCrypto, write: true, restorePlaintext: true, now: () => NOW, print: () => {} });
  assert.deepStrictEqual([sum.restored, sum.failed], [3, 0]);
  const p = db.docs.get(PAYOUT(SELLER9));
  assert.deepStrictEqual([p.cardNumber, p.holderName, p.cardNumberEnc], [CARD2, 'ALI VALIYEV', enc]);
  assert.strictEqual(db.docs.get(PAYOUT(SELLER)).cardNumber, CARD);
  assert.strictEqual(Object.values(db.dump('admin_audit')).filter((a) => a.reason === 'restore_plaintext').length, 3);
  // Eski kod shakli (faqat ochiq maydonlar) ham, yangi kod ham ishlaydi.
  assert.ok(/^\d{16}$/.test(p.cardNumber));
  sum = await runMigration({ db, cardCrypto, write: true, now: () => NOW, print: () => {} });
  assert.deepStrictEqual([sum.halfMigrated, sum.migrated], [3, 3]);
  assert.ok(!('cardNumber' in db.docs.get(PAYOUT(SELLER))) && !('plaintextRestoredAt' in db.docs.get(PAYOUT(SELLER))));
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
