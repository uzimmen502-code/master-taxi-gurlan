/**
 * Ижара хабарномаси — ҲАҚИҚИЙ Admin SDK (Emulator).
 *
 *   firebase emulators:exec --only firestore --project demo-realty-alerts \
 *     "node functions/test/realty_alerts_cf.test.js"
 *
 * Қулфланади (эга қарори 2026-10-08):
 *   - createRealtyAlert: текширув, лимит (3), idempotencyKey, ҳозирги мос
 *     эълонлар рўйхати;
 *   - мослик: мос хабарномага inbox + push, бошқасига йўқ;
 *   - IDEMPOTENT: иккинчи ишга тушиш push ҳам, inbox ҳам қўшмайди (21);
 *   - МАХФИЙЛИК: push ва inbox'да телефон / манзил / аниқ нуқта йўқ;
 *   - тинч соат: inbox бор, push йўқ; кунлик чегара: ошгани push'сиз;
 *   - trigger: фақат `active`га ЎТГАНДА ишлайди;
 *   - setRealtyAlertStatus: бегона ўзгартира олмайди.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-realty-alerts';

const fns = require('../index');
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { attachRealtyAlerts } = require('../realty_alerts');
const db = admin.firestore();

const SEEKER = '998901110001';
const SEEKER2 = '998901110002';
const OWNER = '998902220001';
const STRANGER = '998903330001';

const ctx = (phone) => ({ auth: { uid: phone, token: { phone_number: `+${phone}` } } });
const call = (name, data, phone) => fns[name].run(data, ctx(phone));
const callerPhone = (c) => String(((c.auth || {}).token || {}).phone_number || '').replace(/\D/g, '');
const canonicalUid = (v) => {
  const d = String(v || '').replace(/\D/g, '');
  return d.length === 9 ? `998${d}` : d;
};

// Гурлан маркази; эълон ≈1 км шимолда.
const C = { lat: 41.844, lng: 60.392 };
const P = { lat: 41.853, lng: 60.392 };
// 12:00 Тошкент — тинч соат эмас.
const DAY_NOON = Date.parse('2026-10-08T07:00:00Z');
// 01:00 Тошкент — тинч соат.
const NIGHT = Date.parse('2026-10-08T20:00:00Z');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));
}
async function reset() {
  await Promise.all(['users', 'realty_alerts', 'realty_alert_hits', 'realty_listings', 'settings'].map(wipe));
  await db.doc(`users/${SEEKER}`).set({ fcmToken: 'tok-seeker' });
  await db.doc(`users/${SEEKER2}`).set({ fcmToken: 'tok-seeker2' });
  await db.doc(`users/${OWNER}`).set({ fcmToken: 'tok-owner' });
}

async function seedListing(id, over = {}, point = P) {
  const pub = {
    ownerKey: 'KEY', deal: 'rent', tier: 'plain', status: 'active',
    title: 'Икки хонали', text: 'Таъмирланган', priceText: '3 000 000 сўм',
    rooms: 2, priceAmount: 3000000,
    areaLat: Number((point.lat + 0.004).toFixed(3)), areaLng: point.lng,
    geohash4: require('../geo_hash').encode(point.lat, point.lng, 4),
    createdAt: admin.firestore.Timestamp.fromMillis(DAY_NOON),
    expiresAt: admin.firestore.Timestamp.fromMillis(DAY_NOON + 20 * 86400000),
    ...over,
  };
  await db.doc(`realty_listings/${id}`).set(pub);
  await db.doc(`realty_listings/${id}/private/detail`).set({
    ownerId: OWNER, ownerPhone: OWNER, lat: point.lat, lng: point.lng,
    addressText: 'Гурлан, Навоий кўчаси 12',
  });
}

function harness(now) {
  const sent = [];
  const h = {};
  const api = attachRealtyAlerts(h, {
    functions, db, admin, callerPhone, canonicalUid,
    now: () => now,
    messaging: { send: async (m) => { sent.push(m); return 'id'; } },
  });
  return { h, api, sent };
}

const alertInput = (over = {}) => ({
  deal: 'rent', lat: C.lat, lng: C.lng, radiusKm: 3, roomsMin: 2, roomsMax: 3,
  priceMax: 3500000, ...over,
});

(async () => {
  await check('create: тўғри хабарнома сақланади; ҳозир мос эълон рўйхатда', async () => {
    await reset();
    await seedListing('L0');
    const r = await call('createRealtyAlert', alertInput(), SEEKER);
    assert.strictEqual(r.ok, true);
    const a = (await db.doc(`realty_alerts/${r.alertId}`).get()).data();
    assert.strictEqual(a.ownerId, SEEKER);
    assert.strictEqual(a.status, 'active');
    assert.strictEqual(a.radiusKm, 3);
    assert.ok(a.expiresAt.toMillis() > Date.now() + 29 * 86400000, '30 кун');
    assert.deepStrictEqual(r.matches, ['L0']);
  });

  await check('create: нотўғри кирувчи ва телефонсиз чақирув рад', async () => {
    await reset();
    await assert.rejects(call('createRealtyAlert', alertInput({ radiusKm: 7 }), SEEKER),
      (e) => e.code === 'invalid-argument' && e.details.reason === 'radius_invalid');
    await assert.rejects(fns.createRealtyAlert.run(alertInput(), {}),
      (e) => e.code === 'unauthenticated');
  });

  await check('create: лимит 3 та актив; idempotencyKey иккинчисини яратмайди', async () => {
    await reset();
    const k = await call('createRealtyAlert', alertInput({ idempotencyKey: 'abc' }), SEEKER);
    const k2 = await call('createRealtyAlert', alertInput({ idempotencyKey: 'abc' }), SEEKER);
    assert.strictEqual(k2.alertId, k.alertId);
    assert.strictEqual(k2.duplicate, true);
    await call('createRealtyAlert', alertInput(), SEEKER);
    await call('createRealtyAlert', alertInput(), SEEKER);
    await assert.rejects(call('createRealtyAlert', alertInput(), SEEKER),
      (e) => e.code === 'resource-exhausted' && e.details.limit === 3);
    // Созлама билан ўзгаради.
    await db.doc('settings/app').set({ realtyAlertMaxActive: 4 });
    await call('createRealtyAlert', alertInput(), SEEKER);
  });

  await check('мослик: мос хабарномага inbox + push; мос эмасига ҳеч нарса', async () => {
    await reset();
    const { h, api, sent } = harness(DAY_NOON);
    const a1 = await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    // Бошқа одам: 4+ хона қидиради → мос эмас.
    await h.createRealtyAlert.run(alertInput({ roomsMin: 4, roomsMax: 5 }), ctx(SEEKER2));
    await seedListing('L1');
    const res = await api.matchListing('L1');
    assert.deepStrictEqual(res, { matched: 1, pushed: 1 });
    assert.strictEqual(sent.length, 1);
    assert.strictEqual(sent[0].token, 'tok-seeker');
    assert.deepStrictEqual(sent[0].data, { type: 'realty_match', screen: 'realty_match', listingId: 'L1' });
    const inbox = (await db.doc(`users/${SEEKER}/realty_matches/L1`).get()).data();
    assert.strictEqual(inbox.alertId, a1.alertId);
    assert.strictEqual(inbox.seen, false);
    assert.strictEqual((await db.doc(`users/${SEEKER2}/realty_matches/L1`).get()).exists, false);
  });

  await check('МАХФИЙЛИК: push ва inbox\'да рақам, манзил, аниқ нуқта йўқ', async () => {
    await reset();
    const { h, api, sent } = harness(DAY_NOON);
    await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    await seedListing('L2');
    await api.matchListing('L2');
    const inbox = (await db.doc(`users/${SEEKER}/realty_matches/L2`).get()).data();
    const blob = JSON.stringify({ push: sent[0], inbox });
    for (const secret of [OWNER, 'Навоий', String(P.lat), String(P.lng)]) {
      assert.ok(!blob.includes(secret), `сизиб чиқди: ${secret}`);
    }
    assert.ok(!('lat' in inbox) && !('addressText' in inbox));
  });

  await check('IDEMPOTENT: иккинчи ишга тушиш push ҳам, inbox ҳам қўшмайди', async () => {
    await reset();
    const { h, api, sent } = harness(DAY_NOON);
    await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    await seedListing('L3');
    await api.matchListing('L3');
    await db.doc(`users/${SEEKER}/realty_matches/L3`).update({ seen: true });
    const again = await api.matchListing('L3');
    assert.deepStrictEqual(again, { matched: 0, pushed: 0 });
    assert.strictEqual(sent.length, 1);
    assert.strictEqual((await db.doc(`users/${SEEKER}/realty_matches/L3`).get()).data().seen, true,
      'inbox қайта ёзилмади');
    // Параллел (22-қоида): иккита бир вақтда — битта hit.
    await seedListing('L3b');
    const both = await Promise.all([api.matchListing('L3b'), api.matchListing('L3b')]);
    assert.strictEqual(both[0].matched + both[1].matched, 1);
  });

  await check('ўз эълони эгасига хабар бўлмайди', async () => {
    await reset();
    const { h, api, sent } = harness(DAY_NOON);
    await h.createRealtyAlert.run(alertInput(), ctx(OWNER));
    await seedListing('L4');
    assert.deepStrictEqual(await api.matchListing('L4'), { matched: 0, pushed: 0 });
    assert.strictEqual(sent.length, 0);
  });

  await check('тинч соат: inbox бор, push йўқ', async () => {
    await reset();
    const { h, api, sent } = harness(NIGHT);
    await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    await seedListing('L5');
    assert.deepStrictEqual(await api.matchListing('L5'), { matched: 1, pushed: 0 });
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await db.doc(`users/${SEEKER}/realty_matches/L5`).get()).exists, true);
  });

  await check('кунлик push чегараси: ошгани фақат inbox\'да', async () => {
    await reset();
    await db.doc('settings/app').set({ realtyAlertPushPerDay: 2 });
    const { h, api, sent } = harness(DAY_NOON);
    await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    for (const id of ['M1', 'M2', 'M3']) {
      await seedListing(id);
      await api.matchListing(id);
    }
    assert.strictEqual(sent.length, 2);
    assert.strictEqual((await db.doc(`users/${SEEKER}/realty_matches/M3`).get()).exists, true);
  });

  await check('нофаол / тасдиқланмаган эълон — мослик йўқ', async () => {
    await reset();
    const { h, api } = harness(DAY_NOON);
    await h.createRealtyAlert.run(alertInput(), ctx(SEEKER));
    await seedListing('L6', { status: 'pending' });
    assert.strictEqual((await api.matchListing('L6')).reason, 'not_active');
  });

  await check('trigger: фақат `active`га ЎТГАНДА (pending→active ҳа, active→active йўқ)', async () => {
    await reset();
    await call('createRealtyAlert', alertInput(), SEEKER);
    await seedListing('T1');
    const snap = (data) => ({ exists: !!data, data: () => data });
    const params = { params: { listingId: 'T1' } };
    await fns.onRealtyListingActivated.run({ before: snap({ status: 'active' }), after: snap({ status: 'active' }) }, params);
    assert.strictEqual((await db.doc(`users/${SEEKER}/realty_matches/T1`).get()).exists, false);
    await fns.onRealtyListingActivated.run({ before: snap({ status: 'pending' }), after: snap({ status: 'active' }) }, params);
    assert.strictEqual((await db.doc(`users/${SEEKER}/realty_matches/T1`).get()).exists, true);
  });

  await check('setRealtyAlertStatus: бегона ўзгартира олмайди; эга тўхтатади/ўчиради', async () => {
    await reset();
    const r = await call('createRealtyAlert', alertInput(), SEEKER);
    await assert.rejects(call('setRealtyAlertStatus', { alertId: r.alertId, status: 'deleted' }, STRANGER),
      (e) => e.code === 'permission-denied');
    await call('setRealtyAlertStatus', { alertId: r.alertId, status: 'paused' }, SEEKER);
    assert.strictEqual((await db.doc(`realty_alerts/${r.alertId}`).get()).data().status, 'paused');
    await call('setRealtyAlertStatus', { alertId: r.alertId, status: 'deleted' }, SEEKER);
    assert.strictEqual((await db.doc(`realty_alerts/${r.alertId}`).get()).exists, false);
  });

  const okCount = results.filter(Boolean).length;
  console.log(`\n${okCount}/${results.length} realty alerts CF checks passed.`);
  process.exit(okCount === results.length ? 0 : 1);
})();
