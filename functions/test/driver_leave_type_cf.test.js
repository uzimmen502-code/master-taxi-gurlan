/**
 * `leaveDriverType` — ҳайдовчи БИТТА такси турини ўзи бекор қилади (эга,
 * 2026-10-16). HAQIQIY Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-leave-type \
 *     "node functions/test/driver_leave_type_cf.test.js"
 *
 * Qulflanadi:
 *   A  faqat o'z hisobi (anonim / begona raqam rad), noto'g'ri tur rad
 *   B  tur deklaratsiyadan olinadi (`local` ≡ `alone`), boshqa turlar qoladi
 *   C  `status.taxi` TEGILMAYDI (starter qayta boshlanmaydi)
 *   D  idempotent: ikkinchi chaqiruv `alreadyLeft`, hech narsa o'zgarmaydi
 *   E  faol/onlayn tur yoki qabul qilingan safar — RAD, hech narsa o'zgarmaydi
 *   F  oxirgi tur: eski `role: driver` → `user`; admin roli saqlanadi
 *   G  tur tozalovi: marshrut (reys/navbat/profil), mahalliy (navbat/reys),
 *      shaharlararo (e'lon yopiladi)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-leave-type';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:1';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ANON = { auth: { uid: 'anon_uid_x', token: {} } };
const call = (phone, type, ctx) => fns.leaveDriverType.run(
  { userPhone: phone, taxiType: type }, ctx === undefined ? ctxOf(phone) : ctx);

let n = 0;
const nextPhone = () => `99890300${String(1000 + (n++)).padStart(4, '0')}`;

async function seed(phone, { types, role = 'driver', taxiType, drv = {}, status = 'starter' }) {
  const acc = `acc_${phone}`;
  await db.collection('users').doc(phone).set({ phone, role, accountId: acc });
  await db.collection('provider_capabilities').doc(acc).set({
    identity: { accountId: acc, primaryUid: phone },
    status: { taxi: status },
    taxi: { active: true, taxiTypes: types },
  });
  await db.collection('drivers').doc(phone).set({
    phone, name: 'Test', taxiTypes: types, taxiType: taxiType || types[0],
    isOnline: false, ...drv,
  });
  return acc;
}
const capOf = async (phone) => (await db.collection('provider_capabilities').doc(`acc_${phone}`).get()).data();
const drvOf = async (phone) => (await db.collection('drivers').doc(phone).get()).data();
const userOf = async (phone) => (await db.collection('users').doc(phone).get()).data();

async function rejectsWith(promise, code) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    return;
  }
  assert.fail(`${code} kutilgan edi, lekin muvaffaqiyatli o'tdi`);
}

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

(async () => {
  await check('A1 anonim va begona raqam rad etiladi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local'] });
    await rejectsWith(call(p, 'local', ANON), 'permission-denied');
    await rejectsWith(call(p, 'local', ctxOf('998909999999')), 'permission-denied');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['local']);
  });

  await check('A2 noto\'g\'ri / bo\'sh tur rad etiladi (jimgina `local` bo\'lib ketmaydi)', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local'] });
    await rejectsWith(call(p, 'taxi'), 'invalid-argument');
    await rejectsWith(call(p, ''), 'invalid-argument');
    await rejectsWith(fns.leaveDriverType.run({ taxiType: 'local' }, ctxOf(p)), 'invalid-argument');
  });

  await check('B+C mahalliy: faqat o\'sha tur ketadi, `alone` ham; boshqalar va status qoladi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['intercity', 'alone'], taxiType: 'alone' });
    const r = await call(p, 'local');
    assert.strictEqual(r.ok, true);
    assert.deepStrictEqual(r.remainingTypes, ['intercity']);
    const cap = await capOf(p);
    assert.deepStrictEqual(cap.taxi.taxiTypes, ['intercity']);
    assert.strictEqual(cap.status.taxi, 'starter', 'status tegilmaydi');
    const d = await drvOf(p);
    assert.deepStrictEqual(d.taxiTypes, ['intercity']);
    assert.strictEqual(d.taxiType, 'intercity');
    assert.strictEqual((await userOf(p)).role, 'driver', 'turlar qoldi — rol qoladi');
  });

  await check('C2 verified status ham o\'zgarmaydi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['marshrut', 'intercity'], status: 'verified' });
    await call(p, 'marshrut');
    assert.strictEqual((await capOf(p)).status.taxi, 'verified');
  });

  await check('D idempotent: ikkinchi chaqiruv alreadyLeft va hech narsa o\'zgarmaydi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['intercity', 'local'] });
    await call(p, 'local');
    const before = JSON.stringify(await capOf(p));
    const r = await call(p, 'local');
    assert.strictEqual(r.alreadyLeft, true);
    assert.deepStrictEqual(r.remainingTypes, ['intercity']);
    assert.strictEqual(JSON.stringify(await capOf(p)), before);
  });

  await check('D2 hech qachon qo\'shilmagan tur — alreadyLeft (xato emas)', async () => {
    const p = nextPhone();
    await seed(p, { types: ['intercity'] });
    const r = await call(p, 'marshrut');
    assert.strictEqual(r.alreadyLeft, true);
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['intercity']);
  });

  await check('E1 mahalliy onlayn — rad, hech narsa o\'zgarmaydi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local'], drv: { isOnline: true, taxiType: 'local' } });
    await rejectsWith(call(p, 'local'), 'failed-precondition');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['local']);
    assert.strictEqual((await userOf(p)).role, 'driver');
  });

  await check('E2 marshrut onlayn — rad', async () => {
    const p = nextPhone();
    await seed(p, { types: ['marshrut'], drv: { isOnline: true, taxiType: 'marshrut' } });
    await rejectsWith(call(p, 'marshrut'), 'failed-precondition');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['marshrut']);
  });

  await check('E3 onlayn ammo BOSHQA tur — mahalliyni tark etish mumkin', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local', 'marshrut'], drv: { isOnline: true, taxiType: 'marshrut' } });
    const r = await call(p, 'local');
    assert.strictEqual(r.ok, true);
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['marshrut']);
  });

  await check('E4 shaharlararo e\'lon faol — rad', async () => {
    const p = nextPhone();
    await seed(p, { types: ['intercity'] });
    await db.collection('intercity_drivers').doc(p).set({ isActive: true, isOnPanel: true });
    await rejectsWith(call(p, 'intercity'), 'failed-precondition');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['intercity']);
    assert.strictEqual((await db.collection('intercity_drivers').doc(p).get()).data().isActive, true);
  });

  await check('E5 qabul qilingan safar bor — rad (jimgina bekor qilinmaydi)', async () => {
    const p = nextPhone();
    await seed(p, { types: ['marshrut'] });
    const t = await db.collection('trips').add({
      acceptedDriverId: p, status: 'accepted', taxiType: 'marshrut',
    });
    await rejectsWith(call(p, 'marshrut'), 'failed-precondition');
    assert.strictEqual((await t.get()).data().status, 'accepted');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['marshrut']);
  });

  await check('F1 oxirgi tur: eski role driver → user', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local'] });
    await call(p, 'local');
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, []);
    assert.strictEqual((await userOf(p)).role, 'user');
  });

  await check('F2 oxirgi tur: dispatcher roli saqlanadi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local'], role: 'dispatcher' });
    await call(p, 'local');
    assert.strictEqual((await userOf(p)).role, 'dispatcher');
  });

  await check('G1 marshrut tozalovi: reys o\'chadi, navbat/profil faolsiz', async () => {
    const p = nextPhone();
    await seed(p, { types: ['marshrut', 'intercity'] });
    const s = await db.collection('schedules').add({ driverId: p, taxiType: 'marshrut', isActive: true });
    const other = await db.collection('schedules').add({ driverId: p, taxiType: 'intercity', isActive: true });
    await db.collection('queue').doc(p).set({ isActive: true });
    await db.collection('users').doc(p).collection('driverProfiles').doc('marshrut').set({ isActive: true });
    await call(p, 'marshrut');
    assert.strictEqual((await s.get()).data().isActive, false);
    assert.strictEqual((await other.get()).data().isActive, true, 'boshqa tur reysiga tegilmaydi');
    assert.strictEqual((await db.collection('queue').doc(p).get()).data().isActive, false);
    const prof = await db.collection('users').doc(p).collection('driverProfiles').doc('marshrut').get();
    assert.strictEqual(prof.data().isActive, false);
  });

  await check('G2 mahalliy tozalovi: navbat va mahalliy reys faolsiz, marshrut reysi qoladi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['local', 'marshrut'] });
    const a = await db.collection('schedules').add({ driverId: p, taxiType: 'local', isActive: true });
    const b = await db.collection('schedules').add({ driverId: p, taxiType: 'marshrut', isActive: true });
    await db.collection('queue').doc(p).set({ isActive: true });
    await call(p, 'local');
    assert.strictEqual((await a.get()).data().isActive, false);
    assert.strictEqual((await b.get()).data().isActive, true);
    assert.strictEqual((await db.collection('queue').doc(p).get()).data().isActive, false);
  });

  await check('G3 shaharlararo: e\'lon yopiladi (faol bo\'lmaganda), panel o\'chadi', async () => {
    const p = nextPhone();
    await seed(p, { types: ['intercity', 'local'] });
    await db.collection('intercity_drivers').doc(p).set({ isActive: false, isOnPanel: true });
    await call(p, 'intercity');
    const ic = (await db.collection('intercity_drivers').doc(p).get()).data();
    assert.strictEqual(ic.isActive, false);
    assert.strictEqual(ic.isOnPanel, false);
    assert.deepStrictEqual((await capOf(p)).taxi.taxiTypes, ['local']);
  });

  await check('G4 drivers hujjati yo\'q bo\'lsa ham yiqilmaydi va bo\'sh hujjat yaratmaydi', async () => {
    const p = nextPhone();
    const acc = `acc_${p}`;
    await db.collection('users').doc(p).set({ phone: p, role: 'driver', accountId: acc });
    await db.collection('provider_capabilities').doc(acc).set({
      status: { taxi: 'starter' }, taxi: { active: true, taxiTypes: ['intercity'] },
    });
    const r = await call(p, 'intercity');
    assert.strictEqual(r.ok, true);
    assert.strictEqual((await db.collection('drivers').doc(p).get()).exists, false);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
