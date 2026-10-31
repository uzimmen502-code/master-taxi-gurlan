/**
 * Ulgurji — qadoqlar bo'yicha qoldiq (`setWholesaleStock`, 2026-10-31).
 *
 *   node functions_demand/test/wholesale_stock.test.js
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const {
  STOCK, makeSetWholesaleStock, packIdsOf, parseStockRequest,
} = require('../api/wholesale_stock');

const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const SELLER = '998901234567';
const OTHER = '998901110001';
const NOW = new Date('2026-10-31T12:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

const PACKED = {
  sellerId: SELLER,
  title: 'Гуруч',
  priceTiers: [{ minQty: 1, price: 15000 }],
  packs: [
    { id: 'p1', label: '1 кг', priceTiers: [{ minQty: 1, price: 15000 }] },
    { id: 'p2', label: '25 кг', priceTiers: [{ minQty: 1, price: 320000 }] },
  ],
};
const LEGACY = { sellerId: SELLER, title: 'Ун', priceTiers: [{ minQty: 1, price: 9000 }] };

function makeDb(seed = {}) {
  const db = new FakeFirestore({
    'wholesale_products/a': PACKED,
    'wholesale_products/old': LEGACY,
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
const call = (db) => makeSetWholesaleStock({ db, now: () => NOW });
const stockOf = (db, id) => db.dump(STOCK)[id];
const history = (db, id) => Object.values(db.dump(`${STOCK}/${id}/history`));

async function rejects(promise, code) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    return e;
  }
  throw new Error(`«${code}» xatosi kutilgan edi`);
}

// ─── sof funksiyalar ─────────────────────────────────────────────────
ok('packIdsOf: qadoqlar; qadoqsiz — default; noto\'g\'ri/takror tashlanadi', () => {
  assert.deepStrictEqual(packIdsOf(PACKED), ['p1', 'p2']);
  assert.deepStrictEqual(packIdsOf(LEGACY), ['default']);
  assert.deepStrictEqual(packIdsOf({
    packs: [
      { id: 'p1', label: 'a', priceTiers: [{}] },
      { id: 'p1', label: 'b', priceTiers: [{}] },
      { id: 'default', label: 'c', priceTiers: [{}] },
      { id: 'p2', label: '', priceTiers: [{}] },
      { id: 'p3', label: 'd', priceTiers: [] },
    ],
  }), ['p1']);
});

ok('parseStockRequest: musbat + chegara (0 va 1 000 000)', () => {
  assert.deepStrictEqual(
    parseStockRequest({ productId: 'a', stock: { p1: 0, p2: 1000000 } }),
    { productId: 'a', stock: { p1: 0, p2: 1000000 } },
  );
});

ok('parseStockRequest: noto\'g\'ri kirish RAD', () => {
  assert.throws(() => parseStockRequest({ stock: { p1: 1 } }), /productId/);
  assert.throws(() => parseStockRequest({ productId: 'a/b', stock: { p1: 1 } }), /productId/);
  assert.throws(() => parseStockRequest({ productId: 'a' }), /stock/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: {} }), /stock/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: { x: 1 } }), /qadoq/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: { p1: -1 } }), /qoldiq/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: { p1: 1.5 } }), /qoldiq/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: { p1: 1000001 } }), /qoldiq/);
  assert.throws(() => parseStockRequest({ productId: 'a', stock: { p1: '5' } }), /qoldiq/);
});

// ─── callable ────────────────────────────────────────────────────────
ok('egasi qoldiq yozadi → hujjat + history v1', async () => {
  const db = makeDb();
  const r = await call(db)({ productId: 'a', stock: { p1: 120, p2: 0 } }, ctx(SELLER));
  assert.strictEqual(r.changed, true);
  const s = stockOf(db, 'a');
  assert.deepStrictEqual(s.packs, { p1: 120, p2: 0 });
  assert.strictEqual(s.version, 1);
  assert.strictEqual(s.sellerId, SELLER);
  const h = history(db, 'a');
  assert.strictEqual(h.length, 1);
  assert.deepStrictEqual(h[0].from, {});
  assert.deepStrictEqual(h[0].to, { p1: 120, p2: 0 });
});

ok('qisman yangilash: boshqa qadoq qoldig\'i saqlanadi; history v2', async () => {
  const db = makeDb();
  await call(db)({ productId: 'a', stock: { p1: 120, p2: 3 } }, ctx(SELLER));
  await call(db)({ productId: 'a', stock: { p1: 100 } }, ctx(SELLER));
  assert.deepStrictEqual(stockOf(db, 'a').packs, { p1: 100, p2: 3 });
  assert.strictEqual(stockOf(db, 'a').version, 2);
  assert.strictEqual(history(db, 'a').length, 2);
});

ok('21: bir xil qiymat — hech narsa yozilmaydi (idempotent)', async () => {
  const db = makeDb();
  await call(db)({ productId: 'a', stock: { p1: 5 } }, ctx(SELLER));
  const r = await call(db)({ productId: 'a', stock: { p1: 5 } }, ctx(SELLER));
  assert.strictEqual(r.changed, false);
  assert.strictEqual(stockOf(db, 'a').version, 1);
  assert.strictEqual(history(db, 'a').length, 1);
});

ok('o\'chirilgan qadoqning eski qoldig\'i tashlanadi', async () => {
  const db = makeDb({ [`${STOCK}/a`]: { packs: { p1: 1, p9: 7 }, version: 4 } });
  await call(db)({ productId: 'a', stock: { p2: 2 } }, ctx(SELLER));
  assert.deepStrictEqual(stockOf(db, 'a').packs, { p1: 1, p2: 2 });
  assert.strictEqual(stockOf(db, 'a').version, 5);
});

ok('qadoqsiz eski mahsulot — faqat default', async () => {
  const db = makeDb();
  await call(db)({ productId: 'old', stock: { default: 40 } }, ctx(SELLER));
  assert.deepStrictEqual(stockOf(db, 'old').packs, { default: 40 });
  await rejects(call(db)({ productId: 'old', stock: { p1: 1 } }, ctx(SELLER)), 'invalid-argument');
});

ok('19: boshqa odam RAD, hech narsa yozilmaydi', async () => {
  const db = makeDb();
  await rejects(call(db)({ productId: 'a', stock: { p1: 1 } }, ctx(OTHER)), 'permission-denied');
  assert.strictEqual(stockOf(db, 'a'), undefined);
});

ok('kirmagan — unauthenticated; mahsulot yo\'q — not-found; begona qadoq — invalid', async () => {
  const db = makeDb();
  await rejects(call(db)({ productId: 'a', stock: { p1: 1 } }, {}), 'unauthenticated');
  await rejects(call(db)({ productId: 'zz', stock: { p1: 1 } }, ctx(SELLER)), 'not-found');
  await rejects(call(db)({ productId: 'a', stock: { p3: 1 } }, ctx(SELLER)), 'invalid-argument');
  await rejects(call(db)({ productId: 'a', stock: { default: 1 } }, ctx(SELLER)), 'invalid-argument');
});

(async () => {
  let passed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      passed++;
    } catch (e) {
      console.error(`FAIL: ${t.name}\n  ${e.stack || e}`);
      process.exitCode = 1;
    }
  }
  console.log(`wholesale_stock: ${passed}/${tests.length} passed`);
})();
