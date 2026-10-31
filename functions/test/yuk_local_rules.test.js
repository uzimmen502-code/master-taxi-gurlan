/**
 * yuk_local_drivers rules — аудит 2026-10-31: Y-2 (телефон эгага боғланган),
 * Y-3 (isDemo/сервер майдонлари клиентга ёпиқ), O-2 (турлар, рухсат этилган
 * калитлар), O-7 (ўқиш фақат телефон билан кирганларга), эски APK мослиги.
 *   RULES_FILE=<path> firebase emulators:exec --only firestore --project demo-yuk-local-rules \
 *     "node functions/test/yuk_local_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { Timestamp, serverTimestamp, deleteField } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const OWNER = '998901112233';
const OTHER = '998907778899';
const DAY = 24 * 60 * 60 * 1000;

/** Эски (ва янги) APK `publishListing` create тўплами. */
function oldApkCreate(owner = OWNER, extra = {}) {
  return {
    ownerId: owner, ownerName: 'Ali', phone: `+${owner}`, vehicleType: 'labo',
    plateNumber: '90A123BC', capacityKg: 1000, bodyLengthM: 2, bodyWidthM: 1.5, bodyHeightM: 1,
    acceptRadiusKm: 20, loadStatus: 'empty', lat: 41.85, lng: 60.39, locationLabel: 'Гурлан',
    workStartMinutes: 480, workEndMinutes: 1200, updatedAt: serverTimestamp(),
    regionId: 'xorazm', districtId: 'gurlan', serviceAreaId: 'gurlan',
    rating: 0, completedLoads: 0, createdAt: serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 60 * DAY),
    ...extra,
  };
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: 'demo-yuk-local-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => env.authenticatedContext(phone, { phone_number: `+${phone}` }).firestore();
  const anon = env.authenticatedContext('anon-uid', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  const guest = env.unauthenticatedContext().firestore();
  const col = (db) => db.collection('yuk_local_drivers');

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${OWNER}`).set({ phone: OWNER, role: 'user' });
    await db.doc(`users/${OTHER}`).set({ phone: OTHER, role: 'user' });
    const base = oldApkCreate();
    delete base.updatedAt; delete base.createdAt;
    await db.doc('yuk_local_drivers/mine').set({ ...base, updatedAt: Timestamp.now(), createdAt: Timestamp.now() });
    // Эски телефон-ID ҳужжат: иш вақти/муддат йўқ, онлайн қолдиқлари бор.
    await db.doc(`yuk_local_drivers/${OWNER}`).set({
      ownerId: OWNER, ownerName: 'Ali', phone: `+${OWNER}`, vehicleType: 'labo', plateNumber: '',
      capacityKg: 500, bodyLengthM: 0, bodyWidthM: 0, bodyHeightM: 0, acceptRadiusKm: 20,
      loadStatus: 'offline', lat: 41.8, lng: 60.4, locationLabel: 'x', updatedAt: Timestamp.now(),
      rating: 0, completedLoads: 0, online: true, lastOnlineAt: Timestamp.now(), districtId: 'gurlan', regionId: 'xorazm',
    });
    await db.doc('yuk_local_drivers/demo1').set({ ...base, ownerId: 'demo_1', phone: '+998912778777', isDemo: true, updatedAt: Timestamp.now() });
  });

  // ── O-7: ўқиш ──
  await check('O-7 read: телефон билан кирган — OK (list)', () => assertSucceeds(col(as(OTHER)).limit(5).get()));
  await check('O-7 read: аноним сессия — DENIED (list)', () => assertFails(col(anon).limit(5).get()));
  await check('O-7 read: аноним — DENIED (get)', () => assertFails(anon.doc('yuk_local_drivers/mine').get()));
  await check('O-7 read: auth йўқ — DENIED', () => assertFails(col(guest).limit(5).get()));

  // ── create: эски/янги APK тўплами ──
  await check('create: эски APK тўплами — OK', () => assertSucceeds(col(as(OWNER)).doc('n1').set(oldApkCreate())));
  await check('create: 9 хонали ownerId — OK', () => assertSucceeds(col(as(OWNER)).doc('n2').set(oldApkCreate(OWNER, { ownerId: '901112233', phone: '+998901112233' }))));
  await check('create: busy ҳолати — OK', () => assertSucceeds(col(as(OWNER)).doc('n3').set(oldApkCreate(OWNER, { loadStatus: 'busy' }))));
  // ── Y-2 ──
  await check('Y-2 create: бегона телефон — DENIED', () => assertFails(col(as(OWNER)).doc('x1').set(oldApkCreate(OWNER, { phone: `+${OTHER}` }))));
  await check('Y-2 create: бегона ownerId — DENIED', () => assertFails(col(as(OWNER)).doc('x2').set(oldApkCreate(OTHER))));
  await check('Y-2 create: аноним, ownerId бўш — DENIED', () => assertFails(col(anon).doc('x3').set(oldApkCreate('', { phone: '' }))));
  // ── Y-3 / O-2 ──
  await check('Y-3 create: isDemo — DENIED', () => assertFails(col(as(OWNER)).doc('x4').set(oldApkCreate(OWNER, { isDemo: true }))));
  await check('Y-3 create: expiryPushDays — DENIED', () => assertFails(col(as(OWNER)).doc('x5').set(oldApkCreate(OWNER, { expiryPushDays: [3] }))));
  await check('O-2 create: номаълум майдон — DENIED', () => assertFails(col(as(OWNER)).doc('x6').set(oldApkCreate(OWNER, { foo: 1 }))));
  await check('O-2 create: loadStatus нотўғри — DENIED', () => assertFails(col(as(OWNER)).doc('x7').set(oldApkCreate(OWNER, { loadStatus: 'vip' }))));
  await check('O-2 create: lat матн — DENIED', () => assertFails(col(as(OWNER)).doc('x8').set(oldApkCreate(OWNER, { lat: '41' }))));
  await check('create: rating > 0 — DENIED', () => assertFails(col(as(OWNER)).doc('x9').set(oldApkCreate(OWNER, { rating: 5 }))));
  await check('create: муддат 66 кун — DENIED', () => assertFails(col(as(OWNER)).doc('x10').set(oldApkCreate(OWNER, { expiresAt: Timestamp.fromMillis(Date.now() + 66 * DAY) }))));

  // ── update ──
  const mine = (db) => db.doc('yuk_local_drivers/mine');
  await check('update: эга таҳрири (эски APK merge, phone ўзи) — OK', () => assertSucceeds(mine(as(OWNER)).set({
    ownerId: OWNER, ownerName: 'Ali', phone: `+${OWNER}`, vehicleType: 'gazel', plateNumber: '90A777AA',
    capacityKg: 1500, capacityTons: deleteField(), loadStatus: 'empty', lat: 41.9, lng: 60.4,
    workStartMinutes: 0, workEndMinutes: 1440, updatedAt: serverTimestamp(), online: deleteField(), lastOnlineAt: deleteField(),
    districtId: 'urganch', regionId: 'xorazm',
  }, { merge: true })));
  await check('update: радиус (updateAcceptRadius) — OK', () => assertSucceeds(mine(as(OWNER)).set({ acceptRadiusKm: 50, updatedAt: serverTimestamp() }, { merge: true })));
  await check('update: эски телефон-ID ҳужжат (иш вақтисиз, offline) — OK', () => assertSucceeds(as(OWNER).doc(`yuk_local_drivers/${OWNER}`).set({
    plateNumber: '90B111CC', updatedAt: serverTimestamp(), online: deleteField(), lastOnlineAt: deleteField(),
  }, { merge: true })));
  await check('Y-2 update: телефонни бегонага — DENIED', () => assertFails(mine(as(OWNER)).update({ phone: `+${OTHER}` })));
  await check('Y-3 update: isDemo — DENIED', () => assertFails(mine(as(OWNER)).update({ isDemo: true })));
  await check('update: expiresAt — DENIED', () => assertFails(mine(as(OWNER)).update({ expiresAt: Timestamp.fromMillis(Date.now() + 30 * DAY) })));
  await check('update: ownerId — DENIED', () => assertFails(mine(as(OWNER)).update({ ownerId: OTHER })));
  await check('update: expiryPushDays — DENIED', () => assertFails(mine(as(OWNER)).update({ expiryPushDays: [] })));
  await check('O-2 update: loadStatus нотўғри — DENIED', () => assertFails(mine(as(OWNER)).update({ loadStatus: 'vip' })));
  await check('O-2 update: workStartMinutes матн — DENIED', () => assertFails(mine(as(OWNER)).update({ workStartMinutes: '8' })));
  await check('update: бегона фойдаланувчи — DENIED', () => assertFails(mine(as(OTHER)).update({ plateNumber: 'X' })));
  await check('update: намуна эълони — DENIED', () => assertFails(as(OWNER).doc('yuk_local_drivers/demo1').update({ plateNumber: 'X' })));

  // ── delete ──
  await check('delete: бегона — DENIED', () => assertFails(mine(as(OTHER)).delete()));
  await check('delete: эга — OK', () => assertSucceeds(mine(as(OWNER)).delete()));

  // ── сервер коллекциялари клиентга ёпиқ ──
  await check('yuk_local_owner_state: клиент ўқий олмайди', () => assertFails(as(OWNER).doc(`yuk_local_owner_state/${OWNER}`).get()));
  await check('yuk_local_created_log: клиент ёза олмайди', () => assertFails(as(OWNER).doc('yuk_local_created_log/a').set({ ownerId: OWNER })));

  await env.cleanup();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
