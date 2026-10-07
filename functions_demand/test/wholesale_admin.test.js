/**
 * ADMIN — Ulgurji/Xitoy bozori: mahsulot bozorini almashtirish
 * (`adminSetWholesaleProductMarket`, 2026-10-07).
 *
 *   node functions_demand/test/wholesale_admin.test.js
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const {
  AUDIT, makeAdminSetWholesaleProductMarket, marketOf, parseMarketRequest,
} = require('../api/wholesale_admin');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const ADMIN = '998909990000';
const USER = '998901110001';
const SELLER = '998901234567';
const NOW = new Date('2026-10-07T12:00:00.000Z');
const DELETED = Symbol('FieldValue.delete');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

/** Prodakshn 2026-10-07 dagi eski yozuv shakli: `market` va `currency` YO'Q. */
const LEGACY = {
  sellerId: SELLER, title: 'трактор', description: 'хитойда', status: 'active',
  priceTiers: [{ minQty: 1, price: 3800 }], unit: 'дона',
};

function makeDb(seed = {}) {
  const db = new FakeFirestore({
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${USER}`]: { role: 'user' },
    ...seed,
  });
  db.runTransaction = async (fn) => {
    const tx = {
      // Haqiqiy SDK kabi: yozuvdan keyin o'qish — xato.
      get: (ref) => {
        if (tx._ops.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
        return ref.get();
      },
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      // Haqiqiy Firestore kabi: `FieldValue.delete()` maydonni O'CHIRADI
      // (sentinel qiymat sifatida saqlanib qolmaydi).
      update: (ref, data) => {
        tx._ops.push(async () => {
          const keep = {};
          const drop = [];
          for (const [k, v] of Object.entries(data)) {
            if (v === DELETED) drop.push(k); else keep[k] = v;
          }
          await ref.update(keep);
          const doc = db.docs.get(ref.path);
          for (const k of drop) delete doc[k];
        });
      },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

function callable(db) {
  return makeAdminSetWholesaleProductMarket({ db, now: () => NOW, deleteField: () => DELETED });
}
const product = (db, id) => db.dump('wholesale_products')[id];
const audits = (db) => Object.values(db.dump(AUDIT));

async function rejects(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    return e;
  }
  throw new Error(`«${code}» xatosi kutilgan edi`);
}

// ─── sof funksiyalar ───────────────────────────────────────────────────
ok('marketOf: maydon yo\'q / wholesale → Ulgurji, china → Xitoy', () => {
  assert.strictEqual(marketOf({}), 'wholesale');
  assert.strictEqual(marketOf({ market: 'wholesale' }), 'wholesale');
  assert.strictEqual(marketOf({ market: 'china' }), 'china');
});

ok('parseMarketRequest: Ulgurjiga — valyuta va muddat tashlanadi', () => {
  const r = parseMarketRequest({ productId: 'p', market: 'wholesale', currency: '$', deliveryDays: 9 });
  assert.deepStrictEqual(r, { productId: 'p', market: 'wholesale', currency: '', deliveryDays: null, reason: '' });
});

ok('parseMarketRequest: noto\'g\'ri kirish RAD (negative + chegara)', () => {
  assert.throws(() => parseMarketRequest({ market: 'china' }), /productId/);
  assert.throws(() => parseMarketRequest({ productId: 'a/b', market: 'china' }), /productId/);
  assert.throws(() => parseMarketRequest({ productId: 'p', market: 'usa' }), /bozor/);
  assert.throws(() => parseMarketRequest({ productId: 'p', market: 'china', currency: '€' }), /valyuta/);
  assert.throws(() => parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: 0 }), /muddat/);
  assert.throws(() => parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: 366 }), /muddat/);
  assert.throws(() => parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: 2.5 }), /muddat/);
  assert.strictEqual(parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: 1 }).deliveryDays, 1);
  assert.strictEqual(parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: 365 }).deliveryDays, 365);
  assert.strictEqual(parseMarketRequest({ productId: 'p', market: 'china', deliveryDays: '' }).deliveryDays, null);
});

// ─── callable ──────────────────────────────────────────────────────────
ok('eski Xitoy traktori → Xitoy bozori ($): yoziladi + audit', async () => {
  const db = makeDb({ 'wholesale_products/t1': LEGACY });
  const r = await callable(db)({ productId: 't1', market: 'china', currency: '$', reason: 'audit' }, ctx(ADMIN));
  assert.strictEqual(r.changed, true);
  assert.deepStrictEqual(r.from, { market: 'wholesale', currency: '', deliveryDays: null });
  assert.deepStrictEqual(r.to, { market: 'china', currency: '$', deliveryDays: null });
  const p = product(db, 't1');
  assert.strictEqual(p.market, 'china');
  assert.strictEqual(p.currency, '$');
  assert.ok(!('deliveryDays' in p), 'muddat yo\'q edi — yozilmaydi');
  assert.strictEqual(p.marketChangedBy, ADMIN);
  assert.strictEqual(p.status, 'active', 'holat o\'zgarmaydi');
  assert.deepStrictEqual(p.priceTiers, LEGACY.priceTiers, 'narx raqamlari o\'zgarmaydi');
  const a = audits(db);
  assert.strictEqual(a.length, 1);
  assert.strictEqual(a[0].kind, 'market_change');
  assert.strictEqual(a[0].productId, 't1');
  assert.strictEqual(a[0].by, ADMIN);
  assert.strictEqual(a[0].from.market, 'wholesale');
  assert.strictEqual(a[0].to.market, 'china');
  assert.strictEqual(a[0].reason, 'audit');
});

ok('IDEMPOTENT: qayta chaqiruv hech narsa yozmaydi (audit ham yo\'q)', async () => {
  const db = makeDb({ 'wholesale_products/t1': LEGACY });
  const call = callable(db);
  await call({ productId: 't1', market: 'china', currency: '$' }, ctx(ADMIN));
  const writes = db.writes;
  const r2 = await call({ productId: 't1', market: 'china', currency: '$' }, ctx(ADMIN));
  assert.strictEqual(r2.changed, false);
  assert.strictEqual(db.writes, writes);
  assert.strictEqual(audits(db).length, 1);
});

ok('Xitoy ichida valyuta/muddat tuzatish ham o\'zgarish hisoblanadi', async () => {
  const db = makeDb({ 'wholesale_products/c': { ...LEGACY, market: 'china', currency: '$' } });
  const r = await callable(db)({ productId: 'c', market: 'china', currency: '¥', deliveryDays: 14 }, ctx(ADMIN));
  assert.strictEqual(r.changed, true);
  assert.strictEqual(product(db, 'c').currency, '¥');
  assert.strictEqual(product(db, 'c').deliveryDays, 14);
});

ok('so\'mdagi Xitoy mahsuloti → Ulgurji: valyuta va muddat o\'chiriladi', async () => {
  const db = makeDb({ 'wholesale_products/c': { ...LEGACY, market: 'china', currency: '', deliveryDays: 10 } });
  const r = await callable(db)({ productId: 'c', market: 'wholesale' }, ctx(ADMIN));
  assert.strictEqual(r.changed, true);
  const p = product(db, 'c');
  assert.strictEqual(p.market, 'wholesale');
  assert.ok(!('currency' in p), 'valyuta o\'chirildi');
  assert.ok(!('deliveryDays' in p), 'muddat o\'chirildi');
});

ok('$ dagi Xitoy mahsuloti → Ulgurji RAD («3 800 $» «3 800 so\'m» bo\'lmasin)', async () => {
  const db = makeDb({ 'wholesale_products/c': { ...LEGACY, market: 'china', currency: '$' } });
  const e = await rejects(callable(db)({ productId: 'c', market: 'wholesale' }, ctx(ADMIN)), 'failed-precondition');
  assert.strictEqual(e.details.reason, 'foreign_currency');
  assert.strictEqual(product(db, 'c').market, 'china', 'hech narsa yozilmagan');
  assert.strictEqual(audits(db).length, 0);
});

ok('eski yozuv (market yo\'q) → Ulgurji: maydon aniq yoziladi', async () => {
  const db = makeDb({ 'wholesale_products/w': LEGACY });
  const r = await callable(db)({ productId: 'w', market: 'wholesale' }, ctx(ADMIN));
  assert.strictEqual(r.changed, true);
  assert.strictEqual(product(db, 'w').market, 'wholesale');
});

ok('admin bo\'lmagan foydalanuvchi — RAD, hech narsa yozilmaydi', async () => {
  const db = makeDb({ 'wholesale_products/t1': LEGACY });
  await rejects(callable(db)({ productId: 't1', market: 'china', currency: '$' }, ctx(USER)), 'permission-denied');
  assert.strictEqual(product(db, 't1').market, undefined);
  assert.strictEqual(audits(db).length, 0);
});

ok('kirmagan (auth yo\'q) — RAD', async () => {
  const db = makeDb({ 'wholesale_products/t1': LEGACY });
  await rejects(callable(db)({ productId: 't1', market: 'china' }, {}), 'unauthenticated');
});

ok('mahsulot yo\'q — not-found', async () => {
  const db = makeDb();
  await rejects(callable(db)({ productId: 'nope', market: 'china' }, ctx(ADMIN)), 'not-found');
});

ok('deleteField bog\'liqligisiz yaratib bo\'lmaydi', () => {
  assert.throws(() => makeAdminSetWholesaleProductMarket({ db: makeDb() }), /deleteField/);
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  ok  ${t.name}`);
    } catch (e) {
      // `run_all.js` muvaffaqiyatsizlikni qator boshidagi «  XATO » dan taniydi.
      console.log(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
