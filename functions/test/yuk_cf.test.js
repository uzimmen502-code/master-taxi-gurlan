/**
 * Yuk birjasi CF qismi — `functions/yuk_intercity.js` (runExpiry,
 * listingToSearchEntry) va `functions/yuk_local.js` (refreshYukDemoPresence).
 *
 * To'liq izolyatsiyalangan Firestore Emulator ustida (Admin SDK, rules'siz),
 * real ma'lumotga tegmaydi.
 *
 * Ishlatish (functions/ ichidan):
 *   firebase emulators:exec --only firestore --project demo-yuk "npm run test:yuk-cf"
 * yoki emulator alohida ishlayotgan bo'lsa: npm run test:yuk-cf
 */
'use strict';
const admin = require('firebase-admin');
const { createYukIntercity } = require('../yuk_intercity');
const { attachYukLocal } = require('../yuk_local');

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-yuk';

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { Timestamp } = admin.firestore;

function digits(v) {
  return String(v || '').replace(/[^\d]/g, '');
}

const results = [];
function check(name, pass, detail) {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
}

async function wipe(col) {
  const snap = await db.collection(col).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

async function testIntercityExpiry() {
  await Promise.all(['yuk_listings', 'notifications'].map(wipe));
  const yuk = createYukIntercity({ db, admin, digits });
  const nowMs = Date.now();
  const ts = (deltaMs) => Timestamp.fromMillis(nowMs + deltaMs);
  const H = 60 * 60 * 1000;

  const base = {
    type: 'cargo', from: 'Гурлан', to: 'Тошкент', vehicleType: 'fura',
    ownerId: '998901112233', ownerName: 'T', phone: '+998901112233',
    createdAt: ts(-47 * H),
  };
  await db.collection('yuk_listings').doc('expired').set(
    { ...base, status: 'active', expiresAt: ts(-60 * 1000) });
  await db.collection('yuk_listings').doc('expiredNoOwner').set(
    { ...base, ownerId: '', phone: '', status: 'active', expiresAt: ts(-60 * 1000) });
  await db.collection('yuk_listings').doc('fresh').set(
    { ...base, status: 'active', expiresAt: ts(30 * H) });
  await db.collection('yuk_listings').doc('warnWindow').set(
    { ...base, status: 'active', expiresAt: ts(6 * H) });
  await db.collection('yuk_listings').doc('warnNotified').set(
    { ...base, status: 'active', expiresAt: ts(6 * H), expireSoonNotified: true });
  await db.collection('yuk_listings').doc('warnOutside').set(
    { ...base, status: 'active', expiresAt: ts(6 * H + 5 * 60 * 1000) });
  await db.collection('yuk_listings').doc('alreadyClosed').set(
    { ...base, status: 'closed', expiresAt: ts(-5 * H) });

  const stats = await yuk.runExpiry(Timestamp.fromMillis(nowMs));
  check('runExpiry: stats.closed=2 (expired + expiredNoOwner)', stats.closed === 2,
    JSON.stringify(stats));
  check('runExpiry: stats.warn=2 (window snapshot, notified ham kiradi)',
    stats.warn === 2, JSON.stringify(stats));

  const expired = (await db.doc('yuk_listings/expired').get()).data();
  check('expired → status closed, autoExpired, closedAt',
    expired.status === 'closed' && expired.autoExpired === true && !!expired.closedAt);
  const fresh = (await db.doc('yuk_listings/fresh').get()).data();
  check('fresh → tegilmadi', fresh.status === 'active' && !fresh.expireSoonNotified);
  const warn = (await db.doc('yuk_listings/warnWindow').get()).data();
  check('warnWindow → expireSoonNotified=true, status active',
    warn.expireSoonNotified === true && warn.status === 'active');
  const outside = (await db.doc('yuk_listings/warnOutside').get()).data();
  check('warnOutside (+5 daq) → ogohlantirilmadi', !outside.expireSoonNotified);
  const closed = (await db.doc('yuk_listings/alreadyClosed').get()).data();
  check('alreadyClosed → autoExpired yozilmadi', closed.autoExpired === undefined);

  const notifs = (await db.collection('notifications').get()).docs.map((d) => d.data());
  const closedN = notifs.filter((n) => n.type === 'yuk_listing_closed');
  const warnN = notifs.filter((n) => n.type === 'yuk_listing_expire_soon');
  check('notifications: 1 ta yuk_listing_closed (egasiz e\'lon uchun yo\'q)',
    closedN.length === 1 && closedN[0].listingId === 'expired'
      && closedN[0].targetPhone === '998901112233' && closedN[0].screen === 'yuk_birja'
      && closedN[0].sent === false,
    `${closedN.length}`);
  check('notifications: 1 ta yuk_listing_expire_soon (warnWindow), notified takrorlanmadi',
    warnN.length === 1 && warnN[0].listingId === 'warnWindow'
      && warnN[0].body.includes('6 соат'),
    `${warnN.length}`);

  // Ikkinchi chaqiruv — idempotent: yangi xabar yo'q.
  const stats2 = await yuk.runExpiry(Timestamp.fromMillis(nowMs));
  const notifs2 = await db.collection('notifications').get();
  check('runExpiry ikkinchi marta: closed=0, yangi notification yo\'q',
    stats2.closed === 0 && notifs2.size === notifs.length, JSON.stringify(stats2));
}

function testSearchEntry() {
  const yuk = createYukIntercity({ db, admin, digits });
  const e = yuk.listingToSearchEntry('abc', {
    type: 'truck', from: 'Хива', to: 'Бухоро', stops: ['Навоий'],
    vehicleType: 'ref', status: 'active', price: 1500000.7,
    expiresAt: Timestamp.fromMillis(Date.now() + 3600 * 1000),
  });
  check('listingToSearchEntry: asosiy maydonlar',
    e.type === 'yuk_listing' && e.moduleId === 'yuk_birja'
      && e.sourceCollection === 'yuk_listings' && e.sourceId === 'abc'
      && e.title === 'Хива → Бухоро' && e.subtitle === 'ref' && e.price === 1500000
      && e.active === true && e.keywords.includes('Навоий') && e.geo.to === 'Бухоро',
    JSON.stringify(e));
  const dead = yuk.listingToSearchEntry('x', {
    from: 'A', to: 'B', status: 'active',
    expiresAt: Timestamp.fromMillis(Date.now() - 1000),
  });
  check('listingToSearchEntry: muddati o\'tgan → active=false', dead.active === false);
  const closed = yuk.listingToSearchEntry('y', { from: 'A', to: 'B', status: 'closed' });
  check('listingToSearchEntry: closed → active=false; cargo default subtitle "Юк"',
    closed.active === false && closed.subtitle === 'Юк');
}

async function testLocalDemoBackfill() {
  await wipe('yuk_local_drivers');
  const exp = {};
  const fakeFunctions = {
    pubsub: {
      schedule() {
        return {
          timeZone() { return this; },
          onRun(handler) { return { run: handler }; },
        };
      },
    },
  };
  attachYukLocal(exp, { functions: fakeFunctions, db, admin });
  check('attachYukLocal: refreshYukDemoPresence eksport qilinadi',
    typeof exp.refreshYukDemoPresence.run === 'function');

  await db.collection('yuk_local_drivers').doc('demo1').set({
    isDemo: true, ownerId: 'demo', workStartMinutes: 540, workEndMinutes: 1080,
    expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    online: true, lastOnlineAt: Timestamp.now(),
  });
  await db.collection('yuk_local_drivers').doc('real1').set({
    isDemo: false, ownerId: '998901112233', workStartMinutes: 540, workEndMinutes: 1080,
    expiresAt: Timestamp.fromMillis(Date.now() - 1000), online: true,
  });
  await exp.refreshYukDemoPresence.run();
  const demo = (await db.doc('yuk_local_drivers/demo1').get()).data();
  const real = (await db.doc('yuk_local_drivers/real1').get()).data();
  const farEnough = demo.expiresAt.toMillis() > Date.now() + 170 * 24 * 3600 * 1000;
  check('demo: 0–1440 ish vaqti, expiresAt ≈ +180 kun, online/lastOnlineAt o\'chirildi',
    demo.workStartMinutes === 0 && demo.workEndMinutes === 1440 && farEnough
      && demo.online === undefined && demo.lastOnlineAt === undefined);
  check('real e\'lon tegilmadi',
    real.workStartMinutes === 540 && real.online === true);
}

async function main() {
  await testIntercityExpiry();
  testSearchEntry();
  await testLocalDemoBackfill();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
