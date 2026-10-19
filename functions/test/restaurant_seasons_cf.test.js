/**
 * KAFE-RESTORAN — mavsumlar va Ramazon jadvali: admin callable'lar va kunlik taxminiy davrlar (D-REST-22),
 * HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-restaurant-seasons \
 *     "node functions/test/restaurant_seasons_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-restaurant-seasons';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const ADMIN = '998915000001';
const USER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const seasons = async () => (await db.collection('settings').doc('restaurant_seasons').get()).data();
const ramadan = async () => (await db.collection('settings').doc('restaurant_ramadan').get()).data();

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  await check('S1 admin davrlarni yozadi: v1, tarix + audit; oddiy foydalanuvchi rad; sabab shart', async () => {
    const periods = [{ key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true }];
    await assert.rejects(call('adminSetRestaurantSeasons', { periods, reason: 'test' }, USER));
    await expectCode(call('adminSetRestaurantSeasons', { periods, reason: '' }, ADMIN), 'REASON_REQUIRED');
    const r = await call('adminSetRestaurantSeasons', { periods, reason: 'Musulmonlar idorasi e\'lon qildi' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.version, r.changed], [true, 1, true]);
    const d = await seasons();
    assert.deepStrictEqual(d.periods, [{ key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true }]);
    assert.strictEqual(d.opensDaysBefore, 10);
    assert.ok((await db.collection('restaurant_seasons_history').doc('v1').get()).exists);
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'restaurant_seasons_set').get()).size, 1);
  });

  await check('S2 takroriy chaqiruv versiyani OSHIRMAYDI; noto\'g\'ri davr/opens rad', async () => {
    const periods = [{ key: 'ramadan', from: '2027-02-09', to: '2027-03-09', confirmed: true }];
    const again = await call('adminSetRestaurantSeasons', { periods, reason: 'qayta' }, ADMIN);
    assert.deepStrictEqual([again.version, again.changed], [1, false]);
    await expectCode(call('adminSetRestaurantSeasons', { periods: [{ key: 'eid', from: '2027-02-09', to: '2027-03-09' }], reason: 'x y z' }, ADMIN), 'PERIODS_INVALID');
    await expectCode(call('adminSetRestaurantSeasons', { periods: [{ key: 'ramadan', from: '2027-03-09', to: '2027-02-09' }], reason: 'x y z' }, ADMIN), 'PERIODS_INVALID');
    await expectCode(call('adminSetRestaurantSeasons', { opensDaysBefore: 31, reason: 'x y z' }, ADMIN), 'OPENS_INVALID');
    await expectCode(call('adminSetRestaurantSeasons', { opensDaysBefore: 1.5, reason: 'x y z' }, ADMIN), 'OPENS_INVALID');
    assert.strictEqual((await seasons()).version, 1);
  });

  await check('S3 opensDaysBefore o\'zgartiriladi (davrlar saqlanadi); berilmagan davrlar tegilmaydi', async () => {
    const r = await call('adminSetRestaurantSeasons', { opensDaysBefore: 7, reason: '7 kun oldin' }, ADMIN);
    assert.deepStrictEqual([r.version, r.changed], [2, true]);
    const d = await seasons();
    assert.strictEqual(d.opensDaysBefore, 7);
    assert.strictEqual(d.periods.length, 1);
    await call('adminSetRestaurantSeasons', { opensDaysBefore: 10, reason: 'qaytarish' }, ADMIN);
  });

  await check('S4 kunlik ensureRestaurantSeasons: yetishmayotgan YILLAR uchun taxminiy davrlar; admin davriga tegmaydi; takroriy — o\'zgarish yo\'q', async () => {
    const before = await seasons();
    const out = await fns.ensureRestaurantSeasons.run({});
    assert.ok(out.added >= 4, JSON.stringify(out));
    const d = await seasons();
    const ram = d.periods.filter((p) => p.key === 'ramadan');
    assert.ok(ram.some((p) => p.from === '2027-02-09' && p.confirmed === true), 'admin davri saqlandi');
    const thisYear = new Date().getUTCFullYear();
    for (const y of [thisYear, thisYear + 1]) {
      for (const key of ['qurbon', 'navruz', 'newyear']) {
        assert.ok(d.periods.some((p) => p.key === key && p.from.startsWith(`${y}-`) && p.confirmed === false), `${key} ${y}`);
      }
    }
    assert.ok(d.version > before.version);
    const hist = await db.collection('restaurant_seasons_history').doc(`v${d.version}`).get();
    assert.match(hist.data().updatedBy, /^system:/);
    const again = await fns.ensureRestaurantSeasons.run({});
    assert.strictEqual(again.added, 0);
    assert.strictEqual((await seasons()).version, d.version, 'takroriy ishga tushirish versiyani oshirmaydi');
  });

  await check('S5 to\'y mavsumi avtomatik qo\'shilmaydi (sana UNKNOWN)', async () => {
    assert.ok(!(await seasons()).periods.some((p) => p.key === 'wedding'));
  });

  await check('R1 Ramazon jadvali: admin yozadi (v1 + tarix + audit); takroriy — o\'zgarishsiz; noto\'g\'ri qiymat rad', async () => {
    const days = { '2027-02-09': { sahar: '05:51', iftar: '18:02' }, '2027-02-10': { sahar: '05:50', iftar: '18:03' } };
    const offsets = { toshkent: 0, nukus: 42, andijon: -11 };
    await assert.rejects(call('adminSetRestaurantRamadan', { days, offsets, reason: 'jadval' }, USER));
    await expectCode(call('adminSetRestaurantRamadan', { days, offsets, reason: '' }, ADMIN), 'REASON_REQUIRED');
    const r = await call('adminSetRestaurantRamadan', { days, offsets, reason: 'Idora taqvimi 2027' }, ADMIN);
    assert.deepStrictEqual([r.version, r.changed], [1, true]);
    assert.deepStrictEqual((await ramadan()).offsets, { andijon: -11, nukus: 42, toshkent: 0 });
    assert.ok((await db.collection('restaurant_ramadan_history').doc('v1').get()).exists);
    const again = await call('adminSetRestaurantRamadan', { days, offsets, reason: 'qayta' }, ADMIN);
    assert.deepStrictEqual([again.version, again.changed], [1, false]);
    await expectCode(call('adminSetRestaurantRamadan', { days: { '2027-02-09': { sahar: '5:51', iftar: '18:02' } }, offsets, reason: 'xato' }, ADMIN), 'RAMADAN_DAYS_INVALID');
    await expectCode(call('adminSetRestaurantRamadan', { days, offsets: { nukus: 500 }, reason: 'xato' }, ADMIN), 'RAMADAN_OFFSETS_INVALID');
    await expectCode(call('adminSetRestaurantRamadan', { days: null, offsets, reason: 'xato' }, ADMIN), 'RAMADAN_DAYS_INVALID');
    assert.strictEqual((await ramadan()).version, 1);
  });

  await check('R2 jadval to\'liq almashtiriladi (eski kun qolmaydi) va versiya oshadi', async () => {
    const r = await call('adminSetRestaurantRamadan', {
      days: { '2027-02-11': { sahar: '05:49', iftar: '18:04' } }, offsets: { toshkent: 0 }, reason: 'yangilandi',
    }, ADMIN);
    assert.deepStrictEqual([r.version, r.changed], [2, true]);
    assert.deepStrictEqual(Object.keys((await ramadan()).days), ['2027-02-11']);
  });

  const ok = results.filter(Boolean).length;
  console.log(`\n${ok} passed, ${results.length - ok} failed`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
