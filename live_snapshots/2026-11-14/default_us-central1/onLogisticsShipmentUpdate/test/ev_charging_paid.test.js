/**
 * ev_charging.js — payAndCreateEvStation (пуллик станция қўшиш) мантиғи.
 *
 * Emulator KERAK EMAS: minimal in-memory Firestore taqlidi
 * (`assistant_chat.test.js`дан бир хил naqsh), settlementLedger stub.
 *
 * Ишлатиш: node functions/test/ev_charging_paid.test.js
 */
'use strict';
const assert = require('assert');
const { attachEvCharging } = require('../ev_charging');

// ---------------------------------------------------------------- fake db
class FakeTs {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
}
const SERVER_TS = Symbol('serverTimestamp');
class Increment { constructor(n) { this.n = n; } }

function applyData(prev, data, merge) {
  const out = merge ? { ...(prev || {}) } : {};
  for (const [k, v] of Object.entries(data)) {
    if (v === SERVER_TS) out[k] = new FakeTs(Date.now());
    else if (v instanceof Increment) out[k] = (Number(out[k]) || 0) + v.n;
    else out[k] = v;
  }
  return out;
}

function makeDb() {
  const store = new Map();
  let autoId = 0;
  const docRef = (path) => ({
    id: path.split('/').pop(),
    path,
    async get() { return snap(path); },
    async set(data, opts) {
      store.set(path, applyData(store.get(path), data, !!(opts && opts.merge)));
    },
    async update(data) {
      if (!store.has(path)) throw new Error('not found: ' + path);
      store.set(path, applyData(store.get(path), data, true));
    },
    collection: (name) => colRef(`${path}/${name}`),
  });
  const snap = (path) => ({
    id: path.split('/').pop(),
    ref: docRef(path),
    exists: store.has(path),
    data: () => (store.has(path) ? { ...store.get(path) } : undefined),
  });
  const colRef = (path) => ({
    doc: (id) => docRef(`${path}/${id || `auto${++autoId}`}`),
    async get() {
      const docs = [...store.keys()]
        .filter((k) => k.startsWith(`${path}/`) && !k.slice(path.length + 1).includes('/'))
        .map((k) => snap(k));
      return { docs, empty: docs.length === 0, size: docs.length };
    },
  });
  const db = {
    _store: store,
    collection: (name) => colRef(name),
    async runTransaction(fn) {
      const t = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => { ref.set(data, opts); },
      };
      return fn(t);
    },
  };
  return db;
}

const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => SERVER_TS,
      increment: (n) => new Increment(n),
    },
    Timestamp: { fromMillis: (ms) => new FakeTs(ms) },
  },
};

class HttpsError extends Error {
  constructor(code, message, details) { super(message); this.code = code; this.details = details; }
}
const functions = { https: { HttpsError, onCall: (fn) => fn } };

const handlers = {};
const ledgerCalls = [];
const settlementLedger = {
  prepareBonusInTx: async (t, db, uid, o) => ({ uid, o }),
  commitBonusInTx: (t, ctx, input) => { ledgerCalls.push(input); },
};
const assertAdmin = async () => { throw new Error('not used in this test'); };

const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const callerPhone = (c) => (c.auth.token.phone_number || '').replace(/\D/g, '');
const canonicalUid = (v) => v;

async function expectError(promise, code, message) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `code: ${e.code} (${e.message})`);
    if (message) assert.strictEqual(e.message, message);
    return e;
  }
  assert.fail(`expected error ${code}/${message}`);
}

async function main() {
  const UID = '998901234567';
  const db = makeDb();
  db._store.set(`users/${UID}`, { phone: UID, bonusBalance: 400000 });

  attachEvCharging(handlers, {
    db, admin, functions, assertAdmin, callerPhone, canonicalUid, settlementLedger,
  });

  // 1) default tarif ro'yxati (config/ev_charging hujjati yo'q)
  const t0 = await handlers.getEvStationTariffs({}, ctx(UID));
  assert.deepStrictEqual(t0.tariffs, {
    m6: { months: 6, price: 350000 },
    y12: { months: 12, price: 500000 },
  });

  // 2) auth/validatsiya
  await expectError(handlers.payAndCreateEvStation({ tariff: 'm6', idempotencyKey: 'k' }, {}), 'unauthenticated');
  await expectError(
    handlers.payAndCreateEvStation({ tariff: 'm6', lat: 41, lng: 60 }, ctx(UID)),
    'invalid-argument');
  await expectError(
    handlers.payAndCreateEvStation({ tariff: 'x', idempotencyKey: 'k', lat: 41, lng: 60 }, ctx(UID)),
    'invalid-argument', 'unknown_tariff');
  await expectError(
    handlers.payAndCreateEvStation({ tariff: 'm6', idempotencyKey: 'k' }, ctx(UID)),
    'invalid-argument', 'lat/lng required');

  // 3) balans yetmaydi (y12 = 500000 > 400000)
  const ins = await expectError(
    handlers.payAndCreateEvStation({ tariff: 'y12', idempotencyKey: 'k1', lat: 41.5, lng: 60.6 }, ctx(UID)),
    'failed-precondition', 'insufficient_balance');
  assert.strictEqual(ins.details.balance, 400000);
  assert.strictEqual(ins.details.price, 500000);

  // 4) m6 (350000) — muvaffaqiyatli
  const before = Date.now();
  const r = await handlers.payAndCreateEvStation({
    tariff: 'm6', idempotencyKey: 'k2', lat: 41.55, lng: 60.6,
    chargingTypes: ['DC'], connectors: ['CCS2'], powerKw: 60, operatorName: 'Test Co',
  }, ctx(UID));
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.debited, 350000);
  assert.strictEqual(r.balance, 50000);
  assert.ok(r.paidUntil >= before + 6 * 30 * 86400000 - 5);
  assert.strictEqual(ledgerCalls.length, 1);
  assert.strictEqual(ledgerCalls[0].delta, -350000);
  assert.strictEqual(ledgerCalls[0].refType, 'ev_station_listing');

  const station = db._store.get(`ev_charging_stations/${r.stationId}`);
  assert.strictEqual(station.isActive, true);
  assert.strictEqual(station.listingType, 'paid');
  assert.strictEqual(station.paidTariff, 'm6');
  assert.strictEqual(station.paidAmount, 350000);
  assert.strictEqual(station.createdBy, UID);
  assert.strictEqual(station.verificationStatus, 'community');
  assert.strictEqual(station.geohash4.length, 4);
  assert.deepStrictEqual(station.location, { latitude: 41.55, longitude: 60.6 });
  assert.deepStrictEqual(station.chargingTypes, ['DC']);
  assert.strictEqual(station.powerKw, 60);
  assert.strictEqual(station.operatorName, 'Test Co');
  assert.strictEqual(db._store.get(`users/${UID}`).bonusBalance, 50000);

  const ledgerDocs = await db.collection('users').doc(UID).collection('wallet_ledger').get();
  assert.strictEqual(ledgerDocs.size, 1);
  assert.strictEqual(ledgerDocs.docs[0].data().amount, -350000);
  assert.strictEqual(ledgerDocs.docs[0].data().refId, r.stationId);

  // 5) idempotent takror — qayta yechilmaydi, yangi stansiya yaratilmaydi
  const dup = await handlers.payAndCreateEvStation({
    tariff: 'm6', idempotencyKey: 'k2', lat: 41.55, lng: 60.6,
  }, ctx(UID));
  assert.strictEqual(dup.stationId, r.stationId);
  assert.strictEqual(db._store.get(`users/${UID}`).bonusBalance, 50000);
  assert.strictEqual(ledgerCalls.length, 1);

  // 6) config/ev_charging.stationTariffs override
  db._store.set('config/ev_charging', {
    stationTariffs: { m6: { months: 6, price: 300000 }, promo: { months: 1, price: 50000 } },
  });
  const t1 = await handlers.getEvStationTariffs({}, ctx(UID));
  assert.deepStrictEqual(t1.tariffs, {
    m6: { months: 6, price: 300000 },
    promo: { months: 1, price: 50000 },
  });

  console.log('ev_charging_paid.test.js: OK (6 bo\'lim)');
}

main().catch((e) => { console.error(e); process.exit(1); });
