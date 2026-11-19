/**
 * Жонли c8c5b324 `submitRealtyListing` / `updateRealtyListing` га кўчирилган
 * қўшимча майдонлар ва расм чегараси 10 — сохта db билан (эмуляторсиз).
 * Ишга тушириш: `node test/realty_fields_wiring.test.js`.
 */
'use strict';

const assert = require('assert');
const { attachRealty } = require('../realty');

const DEL = { __del: true };
class HttpsError extends Error {
  constructor(code, msg, details) { super(msg); this.code = code; this.details = details; }
}

function makeDb(store) {
  const writes = [];
  function docRef(path) {
    return {
      id: path.split('/').pop(),
      path,
      async get() {
        const v = store[path];
        return { exists: v !== undefined, data: () => (v === undefined ? undefined : { ...v }) };
      },
      async set(v, opt) { writes.push({ op: 'set', path, v, opt }); store[path] = { ...(opt && opt.merge ? store[path] : {}), ...v }; },
      async update(v) { writes.push({ op: 'update', path, v }); store[path] = { ...store[path], ...v }; },
      collection(name) { return coll(`${path}/${name}`); },
    };
  }
  let auto = 0;
  function coll(path) {
    const q = {
      doc(id) { return docRef(`${path}/${id || `auto${++auto}`}`); },
      where() { return q; },
      limit() { return q; },
      async get() { return { docs: [] }; },
    };
    return q;
  }
  return {
    writes,
    collection: coll,
    batch() {
      const ops = [];
      return {
        set(ref, v) { ops.push({ op: 'set', path: ref.path, v }); },
        async commit() { for (const o of ops) { writes.push(o); store[o.path] = o.v; } },
      };
    },
  };
}

function setup(store = {}) {
  const db = makeDb(store);
  const exports = {};
  attachRealty(exports, {
    functions: { https: { onCall: (fn) => fn, HttpsError }, pubsub: { schedule: () => ({ timeZone: () => ({ onRun: (f) => f }), onRun: (f) => f }) }, runWith: () => ({ pubsub: { schedule: () => ({ timeZone: () => ({ onRun: (f) => f }), onRun: (f) => f }) }, https: { onCall: (f) => f } }) },
    db,
    admin: {
      firestore: {
        FieldValue: { serverTimestamp: () => 'TS', delete: () => DEL, increment: (n) => ({ inc: n }) },
        Timestamp: { fromDate: (d) => ({ toMillis: () => d.getTime() }), now: () => ({ toMillis: () => Date.now() }) },
      },
    },
    callerPhone: () => '998901234567',
    canonicalUid: (p) => String(p || ''),
    ownerGeoStamp: async () => ({ districtId: 'd1' }),
    assertAdmin: () => {},
    notifyUserInApp: async () => {},
  });
  return { exports, db, store };
}

const ctx = { auth: { uid: 'u1', token: { phone_number: '+998901234567' } } };
const base = { title: 'Uy sotiladi', text: 'Yaxshi uy', lat: 41.5, lng: 60.6 };
const imgs = (n) => Array.from({ length: n }, (_, i) => `https://x/${i}.jpg`);

let passed = 0;
async function check(name, fn) { await fn(); passed += 1; console.log(`✓ ${name}`); }
async function rejects(p, reason) {
  try { await p; } catch (e) { assert.strictEqual(e.details && e.details.reason, reason); return; }
  assert.fail(`expected ${reason}`);
}
const mainDoc = (db) => db.writes.find((w) => /^realty_listings\/[^/]+$/.test(w.path)).v;

(async () => {
  await check('W1 submit: тўлиқ майдонлар ёзилади, 12 расм → 10', async () => {
    const { exports, db } = setup();
    await exports.submitRealtyListing({
      ...base, deal: 'rent', propertyType: 'apartment', renovation: 'euro',
      priceCurrency: 'usd', deposit: 500, rentPeriod: 'month', utilities: ['water', 'gas', 'gas'],
      furnished: true, rooms: 3, imageUrls: imgs(12),
    }, ctx);
    const d = mainDoc(db);
    assert.strictEqual(d.imageUrls.length, 10);
    assert.strictEqual(d.propertyType, 'apartment');
    assert.strictEqual(d.priceCurrency, 'USD');
    assert.strictEqual(d.deposit, 500);
    assert.deepStrictEqual(d.utilities, ['gas', 'water']);
    assert.strictEqual(d.rooms, 3);
  });

  await check('W2 submit: эски APK (қўшимча йўқ) — ҳеч қандай янги калит ёзилмайди', async () => {
    const { exports, db } = setup();
    await exports.submitRealtyListing({ ...base, imageUrls: imgs(3), rooms: 2 }, ctx);
    const d = mainDoc(db);
    for (const k of ['propertyType', 'priceCurrency', 'deposit', 'rentPeriod', 'landSotix']) {
      assert.ok(!(k in d), k);
    }
    assert.strictEqual(d.imageUrls.length, 3);
    assert.strictEqual(d.addressText, '');
  });

  await check('W3 submit: ер участкаси — хона/қават/таъмир тозаланади, сотувда депозит йўқ', async () => {
    const { exports, db } = setup();
    await exports.submitRealtyListing({
      ...base, propertyType: 'land', landSotix: 6.255, rooms: 4, floor: 2, renovation: 'euro', deposit: 100,
    }, ctx);
    const d = mainDoc(db);
    assert.strictEqual(d.landSotix, 6.26);
    assert.ok(!('rooms' in d) && !('floor' in d) && !('renovation' in d) && !('deposit' in d));
  });

  await check('W4 submit: нотўғри қиймат — invalid-argument, ҳеч нарса ёзилмайди', async () => {
    const { exports, db } = setup();
    await rejects(exports.submitRealtyListing({ ...base, priceCurrency: 'EUR' }, ctx), 'currency_invalid');
    await rejects(exports.submitRealtyListing({ ...base, yearBuilt: 1899 }, ctx), 'year_built_invalid');
    await rejects(exports.submitRealtyListing({ ...base, propertyType: 'castle' }, ctx), 'property_type_invalid');
    assert.strictEqual(db.writes.length, 0);
  });

  await check('W5 submit: чегара — 10 расм ўзгармайди, landSotix 0.1 қабул', async () => {
    const { exports, db } = setup();
    await exports.submitRealtyListing({ ...base, propertyType: 'house', landSotix: 0.1, imageUrls: imgs(10) }, ctx);
    const d = mainDoc(db);
    assert.strictEqual(d.imageUrls.length, 10);
    assert.strictEqual(d.landSotix, 0.1);
  });

  const owned = () => ({
    'users/998901234567': { realtyOwnerKey: 'K' },
    'realty_listings/L1': {
      ownerKey: 'K', status: 'active', propertyType: 'land', landSotix: 8, priceCurrency: 'USD', areaLat: 41.5, areaLng: 60.6,
    },
    'realty_listings/L1/private/detail': { lat: 41.5, lng: 60.6 },
  });

  await check('W6 update: эски APK — қўшимчалар тегилмайди (фақат сотувда ижара шартлари ўчади)', async () => {
    const { exports, db } = setup(owned());
    await exports.updateRealtyListing({ ...base, listingId: 'L1', imageUrls: imgs(11) }, ctx);
    const u = db.writes.find((w) => w.op === 'update').v;
    assert.ok(!('propertyType' in u) && !('priceCurrency' in u) && !('landSotix' in u));
    assert.strictEqual(u.deposit, DEL);
    assert.strictEqual(u.rentPeriod, DEL);
    assert.strictEqual(u.imageUrls.length, 10);
    // жорий тур land → хона/қават ўчирилади
    assert.strictEqual(u.rooms, DEL);
  });

  await check('W7 update: null — ўчирилади, тур ўзгарса сотих тозаланади', async () => {
    const { exports, db } = setup(owned());
    await exports.updateRealtyListing({
      ...base, listingId: 'L1', propertyType: 'apartment', priceCurrency: null, rooms: 2,
    }, ctx);
    const u = db.writes.find((w) => w.op === 'update').v;
    assert.strictEqual(u.propertyType, 'apartment');
    assert.strictEqual(u.priceCurrency, DEL);
    assert.strictEqual(u.landSotix, DEL);
    assert.strictEqual(u.rooms, 2);
  });

  await check('W8 update: нотўғри қиймат — ёзилмайди', async () => {
    const { exports, db } = setup(owned());
    await rejects(exports.updateRealtyListing({ ...base, listingId: 'L1', deposit: 1.5, deal: 'rent' }, ctx), 'deposit_invalid');
    assert.strictEqual(db.writes.filter((w) => w.op === 'update').length, 0);
  });

  console.log(`\n${passed} passed`);
})().catch((e) => { console.error(e); process.exit(1); });
