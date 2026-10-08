/**
 * realty.js — муддат, лимит ва «ўрин сарфланиши» мантиғи (2026-10-02
 * аудитида тузатилган нуқсонлар).
 *
 * Emulator KERAK EMAS: minimal in-memory Firestore taqlidi
 * (`ev_charging_paid.test.js`дан бир хил нақш).
 *
 * МУҲИМ: бу тақлид Firestore'нинг ТУР ТАРТИБИНИ ҳам такрорлайди —
 * `null` ҳар қандай `Timestamp` дан кичик ва тартибда биринчи туради.
 * Айнан шу хусусият `realtyExpirySweep` даги нуқсонни келтириб
 * чиқарган эди, шунинг учун тақлидда уни соддалаштириб бўлмайди.
 *
 * Ишлатиш: node functions/test/realty_expiry.test.js
 */
'use strict';
const assert = require('assert');
const { attachRealty } = require('../realty');

// Ҳамён аудити Y-1: харидлар ledger кўзгусидан ўтади (`settlementLedger`).
// Бу тест муддат/лимит/даража мантиғини текширади — ledger stub
// (`ev_charging_paid.test.js` билан бир хил нақш).
const ledgerCalls = [];
const settlementLedger = {
  prepareBonusInTx: async (t, db, uid, o) => ({ uid, o, jExists: false }),
  commitBonusInTx: (t, ctx, input) => { ledgerCalls.push(input); },
};

// ---------------------------------------------------------------- fake db
class FakeTs {
  constructor(ms) { this.ms = ms; }
  toMillis() { return this.ms; }
}
const SERVER_TS = Symbol('serverTimestamp');
const DELETE_FIELD = Symbol('delete');
class Increment { constructor(n) { this.n = n; } }

function applyData(prev, data, merge) {
  const out = merge ? { ...(prev || {}) } : {};
  for (const [k, v] of Object.entries(data)) {
    if (v === SERVER_TS) out[k] = new FakeTs(Date.now());
    else if (v === DELETE_FIELD) delete out[k];
    else if (v instanceof Increment) out[k] = (Number(out[k]) || 0) + v.n;
    else out[k] = v;
  }
  return out;
}

/** Firestore тур тартиби: null < сон < Timestamp. */
function rank(v) {
  if (v === null || v === undefined) return 0;
  if (typeof v === 'number') return 1;
  if (v instanceof FakeTs) return 2;
  return 3;
}

function cmp(a, b) {
  const ra = rank(a);
  const rb = rank(b);
  if (ra !== rb) return ra < rb ? -1 : 1;
  const va = a instanceof FakeTs ? a.ms : a;
  const vb = b instanceof FakeTs ? b.ms : b;
  if (va === vb) return 0;
  return va < vb ? -1 : 1;
}

function matches(data, f) {
  const v = data[f.field];
  switch (f.op) {
    case '==': return v === f.value;
    case 'in': return f.value.includes(v);
    case '<=': return cmp(v, f.value) <= 0;
    case '<': return cmp(v, f.value) < 0;
    case '>': return cmp(v, f.value) > 0;
    default: throw new Error('op not supported: ' + f.op);
  }
}

function makeDb() {
  const store = new Map();
  let autoId = 0;

  const childPaths = (prefix) => [...store.keys()].filter(
    (k) => k.startsWith(`${prefix}/`) && !k.slice(prefix.length + 1).includes('/'),
  );

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
    async delete() { store.delete(path); },
    collection: (name) => colRef(`${path}/${name}`),
  });

  const snap = (path) => ({
    id: path.split('/').pop(),
    ref: docRef(path),
    exists: store.has(path),
    data: () => (store.has(path) ? { ...store.get(path) } : undefined),
  });

  /** `where`/`limit` занжири — сўров объекти ўзгармас (immutable). */
  const query = (path, filters, max) => ({
    where: (field, op, value) =>
      query(path, [...filters, { field, op, value }], max),
    limit: (n) => query(path, filters, n),
    async get() {
      let docs = childPaths(path)
        .map((k) => snap(k))
        .filter((s) => filters.every((f) => matches(s.data(), f)));
      // Firestore тенгсизлик сўровини шу майдон бўйича ўсиш
      // тартибида қайтаради — нуқсонни такрорлаш учун шу муҳим.
      const range = filters.find((f) => ['<', '<=', '>'].includes(f.op));
      if (range) {
        docs = docs.sort((a, b) => cmp(a.data()[range.field], b.data()[range.field]));
      }
      if (max != null) docs = docs.slice(0, max);
      return { docs, empty: docs.length === 0, size: docs.length };
    },
  });

  const colRef = (path) => ({
    doc: (id) => docRef(`${path}/${id || `auto${++autoId}`}`),
    where: (field, op, value) => query(path, [{ field, op, value }], null),
    limit: (n) => query(path, [], n),
    get: () => query(path, [], null).get(),
    async listDocuments() { return childPaths(path).map((k) => docRef(k)); },
  });

  return {
    _store: store,
    collection: (name) => colRef(name),
    batch() {
      const ops = [];
      return {
        set: (ref, data, opts) => ops.push(() => ref.set(data, opts)),
        update: (ref, data) => ops.push(() => ref.update(data)),
        async commit() { for (const op of ops) await op(); },
      };
    },
    async runTransaction(fn) {
      return fn({
        get: (ref) => ref.get(),
        set: (ref, data, opts) => { ref.set(data, opts); },
        update: (ref, data) => { ref.update(data); },
      });
    },
  };
}

const admin = {
  firestore: {
    FieldValue: {
      serverTimestamp: () => SERVER_TS,
      increment: (n) => new Increment(n),
      delete: () => DELETE_FIELD,
    },
    Timestamp: {
      fromMillis: (ms) => new FakeTs(ms),
      fromDate: (d) => new FakeTs(d.getTime()),
      now: () => new FakeTs(Date.now()),
    },
  },
};

class HttpsError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}
const functions = {
  https: { HttpsError, onCall: (fn) => fn },
  runWith: () => functions,
  pubsub: {
    schedule: () => ({
      timeZone: () => ({ onRun: (fn) => fn }),
    }),
  },
};

const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const callerPhone = (c) => (c.auth.token.phone_number || '').replace(/\D/g, '');
const canonicalUid = (v) => v;
const ownerGeoStamp = async () => ({ districtId: 'gurlan' });
const assertAdmin = async () => { throw new Error('not used'); };
const notifications = [];
const notifyUserInApp = async (n) => { notifications.push(n); };

async function expectError(promise, code, reason) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `code: ${e.code} (${e.message})`);
    if (reason) assert.strictEqual(e.message, reason);
    return e;
  }
  assert.fail(`expected error ${code}/${reason}`);
}

const DAY = 24 * 60 * 60 * 1000;

/**
 * Очиқ ҳужжатдаги нуқта «силкитилган»ми: 3 хонага яхлитланган ва
 * аниқ нуқтадан ≈1.2 км радиусда.
 *
 * НЕГА «тенг эмас» деб текширилмайди: силкитиш тасодифий, шунинг учун
 * яхлитлангандан кейин аниқ нуқтанинг ўзига тушиши ҲАМ мумкин — ундай
 * текширув вақти-вақти билан йиқиладиган тест бўлар эди. Муҳими —
 * қиймат тўрга тушган ва радиусдан чиқмаган.
 */
function assertJittered(areaLat, areaLng, lat, lng) {
  assert.strictEqual(areaLat, Number(areaLat.toFixed(3)), '3 хонага яхлитланган');
  assert.strictEqual(areaLng, Number(areaLng.toFixed(3)), '3 хонага яхлитланган');
  const dLat = (areaLat - lat) * 111320;
  const dLng = (areaLng - lng) * 111320 * Math.cos((lat * Math.PI) / 180);
  const meters = Math.sqrt(dLat * dLat + dLng * dLng);
  assert.ok(meters <= 1400, `силкитиш радиуси: ${Math.round(meters)} м`);
}

/** Тўғридан-тўғри базага эълон ёзади (CF орқали эмас — тез бўлсин). */
function seedListing(db, id, data) {
  db._store.set(`realty_listings/${id}`, {
    ownerKey: 'KEY', tier: 'plain', status: 'active',
    tierUntil: null, expiresAt: new FakeTs(Date.now() + 30 * DAY),
    ...data,
  });
  db._store.set(`realty_listings/${id}/private/detail`, {
    ownerId: '998901234567', lat: 41.5, lng: 60.6, ownerPhone: '998901234567',
  });
}

async function main() {
  const OWNER = '998901234567';
  const BUYER = '998907654321';

  // ─────────────────────────────────────────────────────────────────
  // 1) Янги эълон: AVA риэлтор рақами ЁЗУВГА ТУШМАЙДИ
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, { phone: OWNER, name: 'Эга' });
    db._store.set('settings/app', { realtyAgentPhone: '998900000001' });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    const res = await h.submitRealtyListing({
      deal: 'sale', tier: 'plain', title: 'Уч хонали', text: 'Марказда',
      lat: 41.5, lng: 60.6, addressText: 'Гурлан, Навоий 12',
      contactMode: 'ava_agent',
    }, ctx(OWNER));
    assert.strictEqual(res.ok, true);

    const pub = db._store.get(`realty_listings/${res.listingId}`);
    const priv = db._store.get(`realty_listings/${res.listingId}/private/detail`);
    assert.strictEqual(pub.contactMode, 'ava_agent');
    assert.strictEqual(pub.hasAgent, true, 'hasAgent танловдан олинади');
    assert.strictEqual(
      priv.agentPhone, '998900000001',
      'ВАҚТИНЧА: Play\'даги эски илова рақамни ёпиқ ҳужжатдан ўқийди',
    );
    assert.strictEqual(priv.ownerPhone, OWNER);
    // Аниқ координата ФАҚАТ ёпиқ ҳужжатда; очиғида — силкитилган нуқта.
    assert.strictEqual(priv.lat, 41.5);
    assert.strictEqual(priv.lng, 60.6);
    assertJittered(pub.areaLat, pub.areaLng, 41.5, 60.6);
    // Эга қарори 2026-10-08: кўча/уй — ПУЛЛИК, фақат ёпиқ ҳужжатда.
    assert.ok(!('addressText' in pub), 'манзил очиқ ҳужжатда бўлмаслиги керак');
    assert.strictEqual(priv.addressText, 'Гурлан, Навоий 12');
    console.log('✓ 1) Янги эълон: танлов ёзувда, рақам созламадан');
  }

  // ─────────────────────────────────────────────────────────────────
  // 2) Пуллик даража: ягона муддат (expiresAt === tierUntil)
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, {
      phone: OWNER, bonusBalance: 500000, realtyOwnerKey: 'KEY',
    });
    seedListing(db, 'L1', { expiresAt: new FakeTs(Date.now() + 28 * DAY) });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    const r = await h.purchaseRealtyTier({
      idempotencyKey: 'i1', listingId: 'L1', tier: 'urgent', durationDays: 3,
    }, ctx(OWNER));
    const doc = db._store.get('realty_listings/L1');
    assert.strictEqual(doc.tier, 'urgent');
    assert.strictEqual(
      doc.expiresAt.toMillis(), doc.tierUntil.toMillis(),
      'объектда ягона муддат бўлиши керак',
    );
    assert.ok(
      doc.expiresAt.toMillis() < Date.now() + 4 * DAY,
      'бепул 28 кун муддатни узайтирмайди (эга қарори)',
    );
    assert.strictEqual(r.tierUntil, doc.tierUntil.toMillis());

    // Даража алмашганда ТЎЛАНГАН кун куймайди.
    await h.purchaseRealtyTier({
      idempotencyKey: 'i2', listingId: 'L1', tier: 'promo', durationDays: 7,
    }, ctx(OWNER));
    const after = db._store.get('realty_listings/L1');
    assert.strictEqual(after.tier, 'promo');
    assert.ok(
      after.tierUntil.toMillis() >= doc.tierUntil.toMillis(),
      'амалдаги пуллик муддат қисқармайди',
    );
    console.log('✓ 2) Пуллик даража муддати = объект умри, тўланган кун куймайди');
  }

  // ─────────────────────────────────────────────────────────────────
  // 3) Тозалаш: ОДДИЙ ёзувлар (tierUntil=null) пуллик навбатни
  //    тўсиб қўймайди — 2026-10-02 нуқсонининг регрессия тести
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    // Саҳифа чегарасидан (150) кўп ОДДИЙ эълон: `tierUntil` — null.
    for (let i = 0; i < 200; i += 1) {
      seedListing(db, `P${i}`, { expiresAt: new FakeTs(Date.now() + 10 * DAY) });
    }
    // Муддати тугаган пуллик даража — айнан шу ўчиши керак.
    seedListing(db, 'EXPIRED', {
      tier: 'urgent',
      tierUntil: new FakeTs(Date.now() - DAY),
      expiresAt: new FakeTs(Date.now() - DAY),
    });
    // ЭСКИ ШАКЛ (2026-10-02 гача): даража муддати ўтган, лекин
    // объектнинг `expiresAt` и узоқда. Биринчи ўтиш буни кўрмайди —
    // айнан иккинчи (`tier` + `tierUntil`) ўтиш ушлаши керак.
    seedListing(db, 'LEGACY', {
      tier: 'promo',
      tierUntil: new FakeTs(Date.now() - DAY),
      expiresAt: new FakeTs(Date.now() + 20 * DAY),
    });
    // Муддати ҳали тугамаган пуллик даража — тегилмайди.
    seedListing(db, 'LIVE', {
      tier: 'promo',
      tierUntil: new FakeTs(Date.now() + 5 * DAY),
      expiresAt: new FakeTs(Date.now() + 5 * DAY),
    });

    await h.realtyExpirySweep();

    assert.ok(
      !db._store.has('realty_listings/EXPIRED'),
      'муддати тугаган пуллик эълон ўчирилиши керак эди',
    );
    assert.ok(
      !db._store.has('realty_listings/EXPIRED/private/detail'),
      'ёпиқ ҳужжат ҳам ўчади',
    );
    assert.ok(
      !db._store.has('realty_listings/LEGACY'),
      'эски шаклдаги ёзувни иккинчи ўтиш ушлаши керак — 150 талик '
      + 'саҳифа ОДДИЙ ёзувлар билан тўлиб қолмаслиги керак',
    );
    assert.ok(
      !db._store.has('realty_listings/LEGACY/private/detail'),
      'эски ёзувнинг ёпиқ ҳужжати ҳам ўчади',
    );
    assert.ok(db._store.has('realty_listings/LIVE'), 'фаол пуллик тегилмайди');
    assert.ok(db._store.has('realty_listings/P0'), 'ОДДИЙ эълон тегилмайди');
    assert.strictEqual(
      db._store.get('realty_listings/LIVE').tier, 'promo',
      'ОДДИЙга қайтариш олиб ташланган',
    );
    console.log('✓ 3) Тозалаш: null tierUntil навбатни тўсмайди, ўчириш ишлайди');
  }

  // ─────────────────────────────────────────────────────────────────
  // 4) Профессионал пакет лимити 50 тадан кейин ҳам ишлайди
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, {
      phone: OWNER, realtyOwnerKey: 'KEY',
      realtyPro: {
        planId: 'pro_150', objects: 150,
        expiresAt: new FakeTs(Date.now() + 30 * DAY),
      },
    });
    for (let i = 0; i < 150; i += 1) seedListing(db, `Q${i}`, {});
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    const quota = await h.getRealtyQuota({}, ctx(OWNER));
    assert.strictEqual(quota.used, 150, 'саноқ 50 та билан чекланмайди');
    assert.strictEqual(quota.limit, 150);
    assert.strictEqual(quota.isPro, true);

    const err = await expectError(
      h.submitRealtyListing({
        deal: 'sale', tier: 'plain', title: 'Яна бири', text: 'Матн',
        lat: 41.5, lng: 60.6, addressText: 'Гурлан, Навоий 12',
      }, ctx(OWNER)),
      'resource-exhausted', 'free_limit_reached',
    );
    assert.strictEqual(err.details.limit, 150);
    assert.strictEqual(err.details.pro, true);
    console.log('✓ 4) 150 объектли пакетда лимит ҳақиқатан ишлайди');
  }

  // ─────────────────────────────────────────────────────────────────
  // 5) Бепул лимит: кўтарилган эълон ҳам ўринни эгаллайди
  //    (2026-10-02 да ёпилган тешикнинг регрессия тести)
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, {
      phone: OWNER, realtyOwnerKey: 'KEY', bonusBalance: 0,
    });
    // Иккита бепул объект, лекин биттасига РЕКЛАМА олинган.
    seedListing(db, 'F1', {});
    seedListing(db, 'F2', {
      tier: 'promo',
      tierUntil: new FakeTs(Date.now() + 7 * DAY),
      expiresAt: new FakeTs(Date.now() + 7 * DAY),
    });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    const quota = await h.getRealtyQuota({}, ctx(OWNER));
    assert.strictEqual(quota.used, 2, 'РЕКЛАМА олинган эълон ҳам саналади');
    assert.strictEqual(quota.limit, 2);

    const err = await expectError(
      h.submitRealtyListing({
        deal: 'sale', tier: 'plain', title: 'Учинчи', text: 'Матн',
        lat: 41.5, lng: 60.6, addressText: 'Гурлан, Навоий 12',
      }, ctx(OWNER)),
      'resource-exhausted', 'free_limit_reached',
    );
    assert.strictEqual(err.details.limit, 2);
    assert.strictEqual(err.details.pro, false);

    // Блокланган эълон ўринни эгалламайди — лентада кўринмайди.
    db._store.set('realty_listings/F2', {
      ...db._store.get('realty_listings/F2'), status: 'blocked',
    });
    const after = await h.getRealtyQuota({}, ctx(OWNER));
    assert.strictEqual(after.used, 1, 'блокланган эълон ўрин эгалламайди');
    console.log('✓ 5) Бепул лимит: кўтарилган эълон ҳам ўрин эгаллайди');
  }

  // ─────────────────────────────────────────────────────────────────
  // 6) Ахборот пакети ўрни беҳуда сарфланмайди
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${BUYER}`, {
      phone: BUYER, realtyUnlocksLeft: 2, realtyOwnerKey: 'BUYER_KEY',
    });
    db._store.set(`users/${OWNER}`, { phone: OWNER, realtyOwnerKey: 'KEY' });
    seedListing(db, 'OK', {});
    seedListing(db, 'BLOCKED', { status: 'blocked' });
    seedListing(db, 'OLD', { expiresAt: new FakeTs(Date.now() - DAY) });
    seedListing(db, 'MINE', { ownerKey: 'BUYER_KEY' });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    await expectError(
      h.unlockRealtyListing({ listingId: 'BLOCKED' }, ctx(BUYER)),
      'failed-precondition', 'listing_blocked',
    );
    await expectError(
      h.unlockRealtyListing({ listingId: 'OLD' }, ctx(BUYER)),
      'failed-precondition', 'listing_expired',
    );
    assert.strictEqual(
      db._store.get(`users/${BUYER}`).realtyUnlocksLeft, 2,
      'рад этилган очишда ўрин ейилмайди',
    );

    const own = await h.unlockRealtyListing({ listingId: 'MINE' }, ctx(BUYER));
    assert.strictEqual(own.own, true);
    assert.strictEqual(own.unlocksLeft, 2, 'ўз эълонида ўрин ейилмайди');
    assert.ok(
      !db._store.has(`users/${BUYER}/realty_unlocked/MINE`),
      'ўз эълони учун ёзув яратилмайди',
    );

    const ok = await h.unlockRealtyListing({ listingId: 'OK' }, ctx(BUYER));
    assert.strictEqual(ok.alreadyUnlocked, false);
    assert.strictEqual(ok.unlocksLeft, 1);
    assert.ok(db._store.has(`users/${BUYER}/realty_unlocked/OK`));

    // Такрор очиш — ўрин ейилмайди.
    const again = await h.unlockRealtyListing({ listingId: 'OK' }, ctx(BUYER));
    assert.strictEqual(again.alreadyUnlocked, true);
    assert.strictEqual(again.unlocksLeft, 1);
    console.log('✓ 6) Блокланган/тугаган/ўз эълонида пуллик ўрин сарфланмайди');
  }

  // ─────────────────────────────────────────────────────────────────
  // 7) Таҳрирлаш: умумий валидация, бўш майдонни ўчириш ва
  //    силкитилган нуқтанинг сақланиши
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, { phone: OWNER, realtyOwnerKey: 'KEY' });
    seedListing(db, 'E1', {
      title: 'Эски сарлавҳа',
      text: 'Эски матн',
      rooms: 3,
      areaLat: 41.511,
      areaLng: 60.611,
      // Эски ёзувда қолган, ҳеч ким ўқимайдиган майдонлар.
      searchTokens: ['eski', 'matn'],
      views: 0,
    });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });

    const base = {
      listingId: 'E1', deal: 'rent', title: 'Янги сарлавҳа',
      text: 'Янги тавсиф матни', lat: 41.5, lng: 60.6,
      addressText: 'Гурлан, Навоий 12', priceText: '45 000 $',
      contactMode: 'owner',
    };

    // Умумий валидация иккала чақирувда бир хил ишлайди.
    await expectError(
      h.updateRealtyListing({ ...base, addressText: 'ўй' }, ctx(OWNER)),
      'invalid-argument', 'address_required',
    );
    await expectError(
      h.updateRealtyListing({ ...base, title: 'ав' }, ctx(OWNER)),
      'invalid-argument', 'title_required',
    );

    const res = await h.updateRealtyListing(base, ctx(OWNER));
    assert.strictEqual(res.status, 'active');

    const doc = db._store.get('realty_listings/E1');
    assert.strictEqual(doc.title, 'Янги сарлавҳа');
    assert.strictEqual(doc.deal, 'rent');
    assert.strictEqual(doc.priceText, '45 000 $');
    assert.ok(!('rooms' in doc), 'бўш қолдирилган майдон ўчирилади');
    assert.ok(!('searchTokens' in doc), 'эски searchTokens тозаланади');
    assert.ok(!('views' in doc), 'эски views тозаланади');
    // Нуқта ўзгармаган — ЭСКИ силкитиш сақланади, акс ҳолда бир неча
    // таҳрирнинг ўртачаси аниқ жойни очиб қўярди.
    assert.strictEqual(doc.areaLat, 41.511);
    assert.strictEqual(doc.areaLng, 60.611);

    const priv = db._store.get('realty_listings/E1/private/detail');
    assert.strictEqual(priv.lat, 41.5);
    // Мурожаат усули «эга» — агентлик рақами ёзилмайди.
    assert.ok(!('agentPhone' in priv));

    // Нуқта ўзгарса — янги силкитиш (аниқ координатага тенг эмас).
    await h.updateRealtyListing(
      { ...base, lat: 41.7, lng: 60.9 }, ctx(OWNER),
    );
    const moved = db._store.get('realty_listings/E1');
    assertJittered(moved.areaLat, moved.areaLng, 41.7, 60.9);
    assert.ok(
      Math.abs(moved.areaLat - 41.511) > 0.05,
      'нуқта кўчса очиқ ҳужжатдаги тахминий нуқта ҳам кўчади',
    );
    console.log('✓ 7) Таҳрирлаш: валидация, майдон ўчириш, силкитиш сақланади');
  }

  // ─────────────────────────────────────────────────────────────────
  // 8) Манзил пакетдан кейин (эга қарори 2026-10-08) + рақамли нарх:
  //    эски очиқ манзил таҳрирда ёпиққа кўчади; бўш манзил — эскиси
  //    сақланади (эски илова); нарх — бутун сўм, нотўғриси рад
  // ─────────────────────────────────────────────────────────────────
  {
    const db = makeDb();
    const h = {};
    db._store.set(`users/${OWNER}`, { phone: OWNER, realtyOwnerKey: 'KEY' });
    // Эски ёзув: манзил ОЧИҚ ҳужжатда қолган.
    seedListing(db, 'A1', { addressText: 'Гурлан, Эски кўча 5' });
    attachRealty(h, {
      functions, db, admin, callerPhone, canonicalUid, ownerGeoStamp,
      assertAdmin, notifyUserInApp, settlementLedger,
    });
    const base = {
      listingId: 'A1', deal: 'rent', title: 'Икки хонали',
      text: 'Таъмирланган', lat: 41.5, lng: 60.6, contactMode: 'owner',
    };

    // Эски илова манзилни юбормади → эскиси ёпиқ ҳужжатга кўчади.
    await h.updateRealtyListing({ ...base, addressText: '' }, ctx(OWNER));
    let pub = db._store.get('realty_listings/A1');
    let priv = db._store.get('realty_listings/A1/private/detail');
    assert.ok(!('addressText' in pub), 'эски очиқ манзил тозаланади');
    assert.strictEqual(priv.addressText, 'Гурлан, Эски кўча 5');

    // Янги манзил + рақамли нарх.
    await h.updateRealtyListing(
      { ...base, addressText: 'Гурлан, Янги кўча 7', priceAmount: 3000000 },
      ctx(OWNER),
    );
    pub = db._store.get('realty_listings/A1');
    priv = db._store.get('realty_listings/A1/private/detail');
    assert.strictEqual(priv.addressText, 'Гурлан, Янги кўча 7');
    assert.strictEqual(pub.priceAmount, 3000000);

    // Бўш қолдирилган нарх ўчирилади; каср ва манфий — рад (8-қоида).
    await h.updateRealtyListing({ ...base, addressText: 'Гурлан, Янги кўча 7' }, ctx(OWNER));
    assert.ok(!('priceAmount' in db._store.get('realty_listings/A1')));
    await expectError(
      h.updateRealtyListing({ ...base, priceAmount: 2500.5 }, ctx(OWNER)),
      'invalid-argument', 'price_invalid',
    );
    await expectError(
      h.updateRealtyListing({ ...base, priceAmount: -1 }, ctx(OWNER)),
      'invalid-argument', 'price_invalid',
    );
    console.log('✓ 8) Манзил ёпиқ ҳужжатда, эскиси кўчади; рақамли нарх бутун сўм');
  }

  console.log('\nҲаммаси ўтди: realty_expiry.test.js');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
