/**
 * Туман ичида юк — `functions/yuk_local.js` (аудит 2026-10-31, эга қарорлари):
 * муддат 60/30 кун сервердан (эга 2026-10-31: 60/10 → 60/30), телефон/туман нормаллаштириш, «Узайтириш» +30 кун,
 * 3/2/1 кун пуш (кунига бир марта), 30 кундан кейин ўчириш, 10 та ҳақиқий
 * эълондан кейин намуналарни ўчириш, намуна cron'и `updatedAt` ёзмайди.
 *
 * Firestore Emulator (Admin SDK, rules'сиз), real маълумотга тегмайди:
 *   firebase emulators:exec --only firestore --project demo-yuk-local "node functions/test/yuk_local_cf.test.js"
 */
'use strict';
const admin = require('firebase-admin');
const { createYukLocal, daysLeft } = require('../yuk_local');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-yuk-local';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { Timestamp } = admin.firestore;
const DAY = 24 * 60 * 60 * 1000;
const OWNER = '998901112233';
const OTHER = '998907778899';

const results = [];
function check(name, pass, detail) {
  results.push(pass);
  console.log(`${pass ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
}

async function wipe(col) {
  const snap = await db.collection(col).get();
  await Promise.all(snap.docs.map((d) => d.ref.delete()));
}

const yuk = createYukLocal({ db, admin });

/** Триггерни қўлда чақириш: ҳужжатни ёзиб, before/after билан. */
async function createListing(id, data) {
  const ref = db.collection('yuk_local_drivers').doc(id);
  await ref.set(data);
  const after = await ref.get();
  return yuk.onListingWrite(id, null, after);
}

function listing(owner, extra = {}) {
  return {
    ownerId: owner, ownerName: 'A', phone: `+${owner}`, vehicleType: 'labo', plateNumber: '90A1',
    capacityKg: 500, lat: 41.85, lng: 60.39, workStartMinutes: 0, workEndMinutes: 1440,
    loadStatus: 'empty', districtId: 'gurlan', createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    rating: 0, completedLoads: 0, ...extra,
  };
}

async function testTtl() {
  await Promise.all(['yuk_local_drivers', 'yuk_local_owner_state', 'yuk_local_created_log'].map(wipe));
  await db.doc('config/yuk_local_demo').delete();
  const now = Date.now();
  // Клиент 60 кун ёзди — биринчи эълон: 60 кун қолади.
  const r1 = await createListing('a1', listing(OWNER, { expiresAt: Timestamp.fromMillis(now + 60 * DAY) }));
  const a1 = (await db.doc('yuk_local_drivers/a1').get()).data();
  check('биринчи эълон: first=true, муддат ≈ createdAt+60 кун',
    r1.first === true && Math.abs(a1.expiresAt.toMillis() - (a1.createdAt.toMillis() + 60 * DAY)) < 2000, JSON.stringify(r1));
  // Иккинчи эълон, клиент (ёлғон) 60 кун ёзди — сервер 30 кунга туширади.
  const r2 = await createListing('a2', listing(OWNER, { expiresAt: Timestamp.fromMillis(now + 60 * DAY) }));
  const a2 = (await db.doc('yuk_local_drivers/a2').get()).data();
  check('иккинчи эълон: first=false, муддат 30 кунга туширилди',
    r2.first === false && Math.abs(a2.expiresAt.toMillis() - (a2.createdAt.toMillis() + 30 * DAY)) < 2000);
  // Retry: ўша ҳужжат учун триггер қайта чақирилди — қарор ўзгармайди, ҳисоб 2 та.
  const again = await yuk.onListingWrite('a1', null, await db.doc('yuk_local_drivers/a1').get());
  const state = (await db.doc(`yuk_local_owner_state/${OWNER}`).get()).data();
  check('retry idempotent: first ўзгармади, listingsCreated=2',
    again.first === true && state.listingsCreated === 2 && state.firstListingId === 'a1', JSON.stringify(state));
  // Ўчирилган биринчи эълон кейин ҳам «биринчи» бўлмайди.
  await db.doc('yuk_local_drivers/a1').delete();
  const r3 = await createListing('a3', listing(OWNER));
  check('аввалгиси ўчирилган бўлса ҳам кейингиси 30 кун', r3.first === false);
  // Бошқа эга — биринчи.
  const r4 = await createListing('b1', listing(OTHER));
  check('бошқа эга: биринчи', r4.first === true);
}

/** Триггердан ОЛДИНГИ эгалар (сервер ҳолати йўқ) — тарихдан аниқланади. */
async function testLegacyOwners() {
  await Promise.all(['yuk_local_drivers', 'yuk_local_owner_state', 'yuk_local_created_log', 'yuk_local_owner_meta'].map(wipe));
  const L1 = '998901000001';
  const L2 = '998901000002';
  const L3 = '998901000003';
  // L1: эски эълони турибди (триггерсиз ёзилган) — янгиси 30 кун.
  await db.doc('yuk_local_drivers/old1').set(listing(L1));
  const r1 = await createListing('new1', listing(L1));
  check('эски эълони бор эга: first=false (30 кун)', r1.first === false);
  // L2: эълони ўчирилган, лекин meta аввал яратилган — 30 кун.
  await db.doc(`yuk_local_owner_meta/${L2}`).set({ ownerId: L2, everPublished: true });
  await new Promise((r) => setTimeout(r, 2300));
  const r2 = await createListing('new2', listing(L2));
  check('meta эълондан олдин яратилган: first=false', r2.first === false);
  // L3: эски клиент — эълон, кейин meta (биринчи марта) — 60 кун қолади.
  const ref = db.collection('yuk_local_drivers').doc('new3');
  await ref.set(listing(L3));
  await db.doc(`yuk_local_owner_meta/${L3}`).set({ ownerId: L3, everPublished: true });
  const r3 = await yuk.onListingWrite('new3', null, await ref.get());
  check('meta эълондан КЕЙИН ёзилган (эски клиент, биринчи эълон): first=true', r3.first === true);
}

async function testNormalize() {
  // Бегона телефон (эски ёки ёлғон клиент) — эга рақамига қайтади; туман йўқ — ''.
  const data = listing(OWNER, { phone: `+${OTHER}` });
  delete data.districtId;
  await createListing('n1', data);
  const n1 = (await db.doc('yuk_local_drivers/n1').get()).data();
  check('телефон эгага қайтарилди, districtId=\'\'', n1.phone === `+${OWNER}` && n1.districtId === '', JSON.stringify({ p: n1.phone, d: n1.districtId }));
  // Ўз ёзувидан қайта ишга тушиш — ҳеч нарса ёзмайди.
  const before = await db.doc('yuk_local_drivers/n1').get();
  const r = await yuk.onListingWrite('n1', before, before);
  check('қайта ишга тушиш: patch бўш (цикл йўқ)', Object.keys(r.patch).length === 0);
  // Намуна — тегилмайди.
  const d = await yuk.onListingWrite('demoX', null, { exists: true, data: () => ({ isDemo: true, ownerId: 'demo' }) });
  check('намуна эълонига триггер тегмайди', d.action === 'demo');
}

async function testRenew() {
  const now = Date.now();
  await db.doc('yuk_local_drivers/r1').set(listing(OWNER, { expiresAt: Timestamp.fromMillis(now + 2 * DAY), expiryPushDays: [3, 2] }));
  await db.doc('yuk_local_drivers/r2').set(listing(OWNER, { expiresAt: Timestamp.fromMillis(now + 5 * DAY) }));
  await db.doc('yuk_local_drivers/r3').set(listing(OWNER, { expiresAt: Timestamp.fromMillis(now - 10 * DAY) }));
  const early = await yuk.renew(OWNER, 'r2', now);
  check('5 кун қолган — YUK_RENEW_TOO_EARLY', !early.ok && early.code === 'YUK_RENEW_TOO_EARLY');
  const other = await yuk.renew(OTHER, 'r1', now);
  check('бегона — YUK_RENEW_NOT_OWNER', !other.ok && other.code === 'YUK_RENEW_NOT_OWNER');
  const ok = await yuk.renew('901112233', 'r1', now);
  const r1 = (await db.doc('yuk_local_drivers/r1').get()).data();
  check('2 кун қолган: +30 кун бугундан, пуш белгилари тозаланди, renewCount=1',
    ok.ok && r1.expiresAt.toMillis() === now + 30 * DAY && r1.expiryPushDays === undefined && r1.renewCount === 1);
  const twice = await yuk.renew(OWNER, 'r1', now);
  const r1b = (await db.doc('yuk_local_drivers/r1').get()).data();
  check('иккинчи босиш: иккинчи марта чўзилмайди', !twice.ok && twice.code === 'YUK_RENEW_TOO_EARLY' && r1b.renewCount === 1);
  const expired = await yuk.renew(OWNER, 'r3', now);
  check('муддати ўтган (10 кун олдин) — узайтирилади', expired.ok === true);
  const missing = await yuk.renew(OWNER, 'nope', now);
  check('йўқ эълон — YUK_LISTING_NOT_FOUND', missing.code === 'YUK_LISTING_NOT_FOUND');
}

async function testDaily() {
  await Promise.all(['yuk_local_drivers', 'notifications'].map(wipe));
  const now = Date.UTC(2026, 10, 1, 5, 0, 0); // 10:00 Тошкент
  const at = (ms) => Timestamp.fromMillis(now + ms);
  await db.doc('yuk_local_drivers/d3').set(listing(OWNER, { expiresAt: at(2.5 * DAY), plateNumber: '90A777AA' }));
  await db.doc('yuk_local_drivers/d2').set(listing(OWNER, { expiresAt: at(1.2 * DAY) }));
  await db.doc('yuk_local_drivers/d1').set(listing(OWNER, { expiresAt: at(0.3 * DAY) }));
  await db.doc('yuk_local_drivers/d4').set(listing(OWNER, { expiresAt: at(3.5 * DAY) }));
  await db.doc('yuk_local_drivers/dsent').set(listing(OWNER, { expiresAt: at(1.5 * DAY), expiryPushDays: [2] }));
  await db.doc('yuk_local_drivers/demo').set(listing('demo_1', { expiresAt: at(1 * DAY), isDemo: true }));
  await db.doc('yuk_local_drivers/old').set(listing(OWNER, { expiresAt: at(-31 * DAY) }));
  await db.doc('yuk_local_drivers/grace').set(listing(OWNER, { expiresAt: at(-29 * DAY) }));
  await db.doc('yuk_local_drivers/olddemo').set(listing('demo_2', { expiresAt: at(-40 * DAY), isDemo: true }));

  check('daysLeft: 2.5→3, 1.2→2, 0.3→1', daysLeft(2.5 * DAY, 0) === 3 && daysLeft(1.2 * DAY, 0) === 2 && daysLeft(0.3 * DAY, 0) === 1);
  const s1 = await yuk.runDaily(now);
  const notifs = (await db.collection('notifications').get()).docs.map((d) => d.data());
  const byId = Object.fromEntries(notifs.map((n) => [n.listingId, n]));
  check('пуш: d3(3 кун), d2(2), d1(1) — 3 та; d4/dsent/demo йўқ',
    s1.reminded === 3 && byId.d3 && byId.d3.daysLeft === 3 && byId.d2.daysLeft === 2 && byId.d1.daysLeft === 1
      && !byId.d4 && !byId.dsent && !byId.demo, JSON.stringify(s1));
  check('пуш шакли: targetPhone, screen=yuk_local, type, матнда рақам ва кун',
    byId.d3.targetPhone === OWNER && byId.d3.screen === 'yuk_local' && byId.d3.type === 'yuk_local_expire_soon'
      && byId.d3.sent === false && byId.d3.body.includes('90A777AA') && byId.d3.body.includes('3 кун'));
  const left = (await db.collection('yuk_local_drivers').get()).docs.map((d) => d.id).sort();
  check('ўчирилди: old (31 кун); қолди: grace (29 кун), olddemo (намуна)',
    !left.includes('old') && left.includes('grace') && left.includes('olddemo'), left.join(','));
  // Ўша куни қайта ишга тушса — янги пуш йўқ.
  const s2 = await yuk.runDaily(now + 60 * 1000);
  const n2 = await db.collection('notifications').get();
  check('қайта ишга тушиш: пуш такрорланмайди', s2.reminded === 0 && n2.size === 3, JSON.stringify(s2));
  // Эртаси куни: d3 → «2», d2 → «1», dsent → «1», d4 → «3»; d1 муддати ўтди.
  const s3 = await yuk.runDaily(now + DAY);
  const d3 = (await db.doc('yuk_local_drivers/d3').get()).data();
  const d1 = (await db.doc('yuk_local_drivers/d1').get()).data();
  check('эртасига: 4 та пуш (d3 «2», d2 «1», dsent «1», d4 «3»), d1 га йўқ',
    s3.reminded === 4 && d3.expiryPushDays.includes(2) && d3.expiryPushDays.includes(3)
      && d1.expiryPushDays.length === 1, JSON.stringify(s3));
}

async function testDemoDeletion() {
  await Promise.all(['yuk_local_drivers', 'yuk_local_owner_state', 'yuk_local_created_log'].map(wipe));
  await db.doc('config/yuk_local_demo').delete();
  for (let i = 0; i < 7; i += 1) {
    await db.doc(`yuk_local_drivers/demo${i}`).set(listing(`demo_${i}`, { isDemo: true }));
  }
  for (let i = 0; i < 9; i += 1) await createListing(`real${i}`, listing(`99890000000${i}`));
  const nine = await db.collection('yuk_local_drivers').where('isDemo', '==', true).get();
  check('9 та ҳақиқий: намуналар турибди', nine.size === 7);
  await createListing('real9', listing('998900000009'));
  const ten = await db.collection('yuk_local_drivers').where('isDemo', '==', true).get();
  const st = (await db.doc('config/yuk_local_demo').get()).data() || {};
  check('10-эълон: 7 намуна ўчди, config белгиси', ten.size === 0 && st.deletedCount === 7 && st.realListingsAtDelete === 10);
  // Ўчирилган ҳақиқий эълон ҳам саналган эди (log қолади).
  await db.doc('yuk_local_drivers/demoNew').set(listing('demo_x', { isDemo: true }));
  await createListing('real10', listing('998900000010'));
  const after = await db.doc('yuk_local_drivers/demoNew').get();
  check('бир марталик: кейин қўшилган намуна ўчирилмайди', after.exists);
}

async function testDemoRefresh() {
  await wipe('yuk_local_drivers');
  const now = Date.now();
  const oldUpdated = Timestamp.fromMillis(now - 5 * DAY);
  await db.doc('yuk_local_drivers/dmA').set({ isDemo: true, ownerId: 'demo', workStartMinutes: 0, workEndMinutes: 1440,
    expiresAt: Timestamp.fromMillis(now + 100 * DAY), updatedAt: oldUpdated });
  await db.doc('yuk_local_drivers/dmB').set({ isDemo: true, ownerId: 'demo', workStartMinutes: 540, workEndMinutes: 1080,
    expiresAt: Timestamp.fromMillis(now + 5 * DAY), updatedAt: oldUpdated, online: true });
  await yuk.refreshDemos(now);
  const a = (await db.doc('yuk_local_drivers/dmA').get()).data();
  const b = (await db.doc('yuk_local_drivers/dmB').get()).data();
  check('муддати етарли намунага тегилмади', a.expiresAt.toMillis() === now + 100 * DAY && a.updatedAt.toMillis() === oldUpdated.toMillis());
  check('муддати оз намуна: +180 кун, бут кун, online ўчди, updatedAt ЁЗИЛМАДИ',
    b.expiresAt.toMillis() > now + 170 * DAY && b.workStartMinutes === 0 && b.online === undefined
      && b.updatedAt.toMillis() === oldUpdated.toMillis());
}

async function main() {
  await testTtl();
  await testLegacyOwners();
  await testNormalize();
  await testRenew();
  await testDaily();
  await testDemoDeletion();
  await testDemoRefresh();
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
