/**
 * Рағбат дастурлари — callable'лар, HAQIQIY `functions/index.js`, Firestore Emulator.
 * Firebase Auth (рўйхатдан ўтган вақт) — stub.
 *
 *   firebase emulators:exec --only firestore --project demo-incentives "node test/incentives_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-incentives';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const {
  validateProgram, evaluateEligibility, parseBirthDate, ageAt, hasCarProfile, tashkentDayKey,
} = require('../incentives');

const DAY = 86400000;
const NOW = Date.now();
const SINCE = NOW - 10 * DAY;
const authCreated = {};
Object.defineProperty(admin, 'auth', {
  configurable: true,
  value: () => ({
    getUser: async (authUid) => {
      const ms = authCreated[authUid];
      if (ms == null) throw new Error('stub: no user');
      return { metadata: { creationTime: new Date(ms).toUTCString() } };
    },
  }),
});

const db = admin.firestore();
const ADMIN = '998914000001';
const WOMAN = '998914000002';
const WOMAN2 = '998914000003';
const MAN = '998914000004';
const OLD_WOMAN = '998914000005';
const TEEN14 = '998914000006';
const TEEN15 = '998914000007';
const WOMAN61 = '998914000008';
const NOBIRTH = '998914000009';
const W3 = '998914000010';
const W4 = '998914000011';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
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
const userDoc = async (id) => (await db.collection('users').doc(id).get()).data();
const progDoc = async (id) => (await db.collection('incentive_programs').doc(id).get()).data();

/** Тошкент бўйича «бугундан N йил олдин» туғилган сана, D.M.YYYY. */
function birthYearsAgo(years, dayShift = 0) {
  const t = new Date(NOW + 5 * 3600000 + dayShift * DAY);
  return `${t.getUTCDate()}.${t.getUTCMonth() + 1}.${t.getUTCFullYear() - years}`;
}

const women = (over = {}) => ({
  key: 'women', title: { uz_Cyrl: 'Аёллар', uz_Latn: 'Ayollar', ru: 'Женщины' }, stage: 'off',
  internalPhones: [], pilotDistrictIds: [],
  audience: { gender: 'female', ageMin: 15, ageMax: 60, requireCar: false, newUsersSince: SINCE },
  amount: 100000, buckets: [], maxOrderSharePct: 30, validityDays: 90, budgetTotal: 300000, budgetDaily: 0,
  ...over,
});
const car = (over = {}) => ({
  key: 'car', title: { uz_Cyrl: 'Машина', uz_Latn: 'Mashina', ru: 'Авто' }, stage: 'public',
  internalPhones: [], pilotDistrictIds: [],
  audience: { gender: 'any', ageMin: 0, ageMax: 120, requireCar: true, newUsersSince: SINCE },
  amount: 200000,
  buckets: [{ category: 'insurance', amount: 50000 }, { category: 'tire', amount: 60000 }, { category: 'oil', amount: 40000 }, { category: 'battery', amount: 50000 }],
  maxOrderSharePct: 30, validityDays: 90, budgetTotal: 10000000, budgetDaily: 0,
  ...over,
});

async function main() {
  await clearEmulator();
  const mk = async (id, data, createdMs = NOW - DAY) => {
    authCreated[`uid_${id}`] = createdMs;
    await db.collection('users').doc(id).set({ role: 'user', bonusBalance: 5000, ...data });
  };
  await mk(ADMIN, { role: 'admin', gender: 'male' });
  await mk(WOMAN, { gender: 'female', birthDate: birthYearsAgo(25), districtId: 'gurlan' });
  await mk(WOMAN2, { gender: 'female', birthDate: '1999-05-20', districtId: 'yashnobod' });
  await mk(MAN, { gender: 'male', birthDate: birthYearsAgo(30) });
  await mk(OLD_WOMAN, { gender: 'female', birthDate: birthYearsAgo(30) }, SINCE - DAY);
  await mk(TEEN14, { gender: 'female', birthDate: birthYearsAgo(15, 1) }); // эртага 15 — бугун 14
  await mk(TEEN15, { gender: 'female', birthDate: birthYearsAgo(15) }); // бугун 15
  await mk(WOMAN61, { gender: 'female', birthDate: birthYearsAgo(61) });
  await mk(NOBIRTH, { gender: 'female' });
  await mk(W3, { gender: 'female', birthDate: birthYearsAgo(20) });
  await mk(W4, { gender: 'female', birthDate: birthYearsAgo(20) });

  await check('P1 sof: validateProgram (ok, buckets yig\'indisi, yosh, bosqich, sarlavha, budjet)', () => {
    const v = validateProgram(car());
    assert.strictEqual(v.amount, 200000);
    assert.strictEqual(v.buckets.length, 4);
    assert.throws(() => validateProgram(car({ buckets: [{ category: 'tire', amount: 1 }] })), /buckets_sum/);
    assert.throws(() => validateProgram(women({ audience: { gender: 'female', ageMin: 60, ageMax: 15, newUsersSince: SINCE } })), /VALIDATION_age/);
    assert.throws(() => validateProgram(women({ stage: 'on' })), /VALIDATION_stage/);
    assert.throws(() => validateProgram(women({ title: { uz_Cyrl: 'A', uz_Latn: '', ru: 'B' } })), /title_uz_Latn/);
    assert.throws(() => validateProgram(women({ budgetTotal: 1000 })), /budgetTotal/);
    assert.throws(() => validateProgram(women({ amount: 10.5 })), /VALIDATION_amount/);
    assert.throws(() => validateProgram(women({ audience: { gender: 'female' } })), /newUsersSince/);
  });

  await check('P2 sof: tug\'ilgan sana formatlari, yosh chegarasi (tug\'ilgan kuni), mashina profili, Toshkent kuni', () => {
    assert.deepStrictEqual(parseBirthDate('2001-03-09'), { y: 2001, m: 3, d: 9 });
    assert.deepStrictEqual(parseBirthDate('9.3.2001'), { y: 2001, m: 3, d: 9 });
    assert.strictEqual(parseBirthDate('31.02.2001'), null);
    assert.strictEqual(parseBirthDate(''), null);
    assert.strictEqual(ageAt(parseBirthDate(birthYearsAgo(15)), NOW), 15);
    assert.strictEqual(ageAt(parseBirthDate(birthYearsAgo(15, 1)), NOW), 14);
    assert.strictEqual(hasCarProfile({ carModel: 'Cobalt', carColor: 'oq', carPlate: '90A123BC', carSeats: 4 }), true);
    assert.strictEqual(hasCarProfile({ carModel: 'Cobalt', carColor: 'oq', carPlate: '', carSeats: 4 }), false);
    assert.strictEqual(hasCarProfile({ carModel: 'Cobalt', carColor: 'oq', carPlate: 'X', carSeats: 0 }), false);
    assert.strictEqual(tashkentDayKey(Date.UTC(2026, 10, 1, 20, 0)), '20261102');
    const p = { ...women(), stage: 'public' };
    assert.deepStrictEqual(evaluateEligibility(p, { gender: 'female', birthDate: birthYearsAgo(20) }, { nowMs: NOW, uid: 'x', registeredMs: null }), { ok: false, code: 'NOT_NEW_USER' });
  });

  await check('A1 admin: oddiy foydalanuvchi — rad; yaratish (counters 0, audit); noto\'g\'ri maydon — VALIDATION', async () => {
    await assert.rejects(call('adminUpsertIncentiveProgram', women(), WOMAN), (e) => e.code === 'permission-denied');
    const r = await call('adminUpsertIncentiveProgram', women(), ADMIN);
    assert.deepStrictEqual(r, { ok: true, programId: 'women', created: true });
    const p = await progDoc('women');
    assert.deepStrictEqual(p.counters, { grantedAmount: 0, grantedCount: 0, spentAmount: 0, expiredAmount: 0, revokedAmount: 0 });
    assert.strictEqual(p.stage, 'off');
    assert.strictEqual(p.audience.newUsersSince.toMillis(), SINCE);
    await expectCode(call('adminUpsertIncentiveProgram', women({ amount: -1 }), ADMIN), 'VALIDATION_amount');
    const audit = await db.collection('admin_audit').where('programId', '==', 'women').get();
    assert.strictEqual(audit.size, 1);
  });

  await check('C1 off — PROGRAM_OFF; internal — ro\'yxatda yo\'q NOT_IN_STAGE, ro\'yxatdagi oladi', async () => {
    await expectCode(call('claimIncentive', { programId: 'women' }, WOMAN), 'PROGRAM_OFF');
    await call('adminUpsertIncentiveProgram', { ...women({ stage: 'internal', internalPhones: [WOMAN] }), programId: 'women' }, ADMIN);
    await expectCode(call('claimIncentive', { programId: 'women' }, WOMAN2), 'NOT_IN_STAGE');
    const r = await call('claimIncentive', { programId: 'women' }, WOMAN);
    assert.deepStrictEqual(r, { ok: true, grantId: `women_${WOMAN}`, amount: 100000, duplicate: false });
    const u = await userDoc(WOMAN);
    assert.strictEqual(u.incentiveBalance, 100000);
    assert.strictEqual(u.bonusBalance, 5000, 'shaxsiy pul (bonusBalance) o\'zgarmaydi');
    const g = (await db.collection('incentive_grants').doc(`women_${WOMAN}`).get()).data();
    assert.deepStrictEqual([g.status, g.remaining, g.buckets.any, g.maxOrderSharePct], ['active', 100000, 100000, 30]);
    assert.ok(Math.abs(g.expiresAt.toMillis() - (Date.now() + 90 * DAY)) < 60000);
    assert.ok((await db.collection('incentive_ledger').doc(`grant_women_${WOMAN}`).get()).exists);
    const p = await progDoc('women');
    assert.deepStrictEqual([p.counters.grantedAmount, p.counters.grantedCount], [100000, 1]);
  });

  await check('C2 takror — duplicate, ikki marta berilmaydi', async () => {
    const r = await call('claimIncentive', { programId: 'women' }, WOMAN);
    assert.strictEqual(r.duplicate, true);
    assert.strictEqual((await userDoc(WOMAN)).incentiveBalance, 100000);
    assert.strictEqual((await progDoc('women')).counters.grantedCount, 1);
  });

  await check('C3 pilot: tuman bo\'yicha; public: shartlar — jins, yosh 14/15/61, sanasiz, eski foydalanuvchi', async () => {
    await call('adminUpsertIncentiveProgram', { ...women({ stage: 'pilot', pilotDistrictIds: ['yashnobod'], budgetTotal: 1000000 }), programId: 'women' }, ADMIN);
    await expectCode(call('claimIncentive', { programId: 'women' }, W3), 'NOT_IN_STAGE');
    assert.strictEqual((await call('claimIncentive', { programId: 'women' }, WOMAN2)).amount, 100000);
    await call('adminSetIncentiveStage', { programId: 'women', stage: 'public' }, ADMIN);
    await expectCode(call('claimIncentive', { programId: 'women' }, MAN), 'GENDER_MISMATCH');
    await expectCode(call('claimIncentive', { programId: 'women' }, TEEN14), 'AGE_OUT_OF_RANGE');
    assert.strictEqual((await call('claimIncentive', { programId: 'women' }, TEEN15)).amount, 100000);
    await expectCode(call('claimIncentive', { programId: 'women' }, WOMAN61), 'AGE_OUT_OF_RANGE');
    await expectCode(call('claimIncentive', { programId: 'women' }, NOBIRTH), 'AGE_UNKNOWN');
    await expectCode(call('claimIncentive', { programId: 'women' }, OLD_WOMAN), 'NOT_NEW_USER');
  });

  await check('C4 budjet: umumiy chegara — BUDGET_EXHAUSTED; byudjetni berilgandan kamaytirib bo\'lmaydi', async () => {
    // Hozir berilgan: 300 000 (WOMAN, WOMAN2, TEEN15). Budjet 400 000 → W3 oladi, W4 — yo'q.
    await call('adminUpsertIncentiveProgram', { ...women({ stage: 'public', budgetTotal: 400000 }), programId: 'women' }, ADMIN);
    assert.strictEqual((await call('claimIncentive', { programId: 'women' }, W3)).amount, 100000);
    await expectCode(call('claimIncentive', { programId: 'women' }, W4), 'BUDGET_EXHAUSTED');
    await expectCode(call('adminUpsertIncentiveProgram', { ...women({ stage: 'public', budgetTotal: 300000 }), programId: 'women' }, ADMIN), 'VALIDATION_budgetTotal_below_granted');
  });

  await check('C5 parallel: bitta foydalanuvchi 2 marta bir vaqtda — bitta grant; 2 xil foydalanuvchi oxirgi budjetga — bittasi', async () => {
    await call('adminUpsertIncentiveProgram', { ...women({ stage: 'public', budgetTotal: 600000 }), programId: 'women' }, ADMIN);
    const [a, b] = await Promise.all([
      call('claimIncentive', { programId: 'women' }, W4),
      call('claimIncentive', { programId: 'women' }, W4),
    ]);
    assert.strictEqual([a.duplicate, b.duplicate].filter((x) => x === false).length, 1);
    assert.strictEqual((await userDoc(W4)).incentiveBalance, 100000);
    // Budjet: 500 000 berilgan, 600 000 chegara → faqat 1 ta joy. Ikki yangi ayol bir vaqtda.
    const A = '998914000020'; const B = '998914000021';
    await mk(A, { gender: 'female', birthDate: birthYearsAgo(22) });
    await mk(B, { gender: 'female', birthDate: birthYearsAgo(22) });
    const rs = await Promise.allSettled([
      call('claimIncentive', { programId: 'women' }, A),
      call('claimIncentive', { programId: 'women' }, B),
    ]);
    assert.strictEqual(rs.filter((x) => x.status === 'fulfilled').length, 1);
    assert.strictEqual((await progDoc('women')).counters.grantedAmount, 600000);
  });

  await check('C6 kunlik budjet — DAILY_BUDGET_EXHAUSTED', async () => {
    await call('adminUpsertIncentiveProgram', car({ key: 'daily_t', budgetDaily: 200000 }), ADMIN);
    const C1 = '998914000030'; const C2 = '998914000031';
    const carProfile = { carModel: 'Cobalt', carColor: 'oq', carPlate: '90A123BC', carSeats: 4 };
    await mk(C1, { gender: 'male', ...carProfile });
    await mk(C2, { gender: 'male', ...carProfile });
    assert.strictEqual((await call('claimIncentive', { programId: 'daily_t' }, C1)).amount, 200000);
    await expectCode(call('claimIncentive', { programId: 'daily_t' }, C2), 'DAILY_BUDGET_EXHAUSTED');
  });

  await check('C7 mashina dasturi: profilsiz — CAR_PROFILE_REQUIRED + takliflarda needsCar; profil bilan — 200 000, toifalar', async () => {
    await call('adminUpsertIncentiveProgram', car(), ADMIN);
    await expectCode(call('claimIncentive', { programId: 'car' }, MAN), 'CAR_PROFILE_REQUIRED');
    const offers = await call('getMyIncentiveOffers', {}, MAN);
    const carOffer = offers.offers.find((o) => o.programId === 'car');
    assert.deepStrictEqual([carOffer.needsCar, carOffer.claimed, carOffer.amount], [true, false, 200000]);
    assert.ok(!offers.offers.some((o) => o.programId === 'women'), 'erkakka ayollar dasturi ko\'rinmaydi');
    await db.collection('users').doc(MAN).update({ carModel: 'Cobalt', carColor: 'oq', carPlate: '01A777AA', carSeats: 4 });
    assert.strictEqual((await call('claimIncentive', { programId: 'car' }, MAN)).amount, 200000);
    const g = (await db.collection('incentive_grants').doc(`car_${MAN}`).get()).data();
    assert.deepStrictEqual(g.buckets, { insurance: 50000, tire: 60000, oil: 40000, battery: 50000 });
    // Mashinasi bor ayol: 100 000 + 200 000 (ega tasdiqladi).
    await db.collection('users').doc(WOMAN).update({ carModel: 'Spark', carColor: 'qora', carPlate: '01B111BB', carSeats: 4 });
    assert.strictEqual((await call('claimIncentive', { programId: 'car' }, WOMAN)).amount, 200000);
    assert.strictEqual((await userDoc(WOMAN)).incentiveBalance, 300000);
    const wo = await call('getMyIncentiveOffers', {}, WOMAN);
    assert.deepStrictEqual(wo.offers.filter((o) => o.claimed).map((o) => o.programId).sort(), ['car', 'women']);
    assert.strictEqual(wo.incentiveBalance, 300000);
  });

  await check('E1 muddat: o\'tgan grant yonadi (balans, ledger, counters); qayta yurgizish — o\'zgarmaydi', async () => {
    await db.collection('incentive_grants').doc(`women_${W3}`).update({ expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
    const before = (await progDoc('women')).counters.expiredAmount;
    await fns.incentiveExpirySweep.run({}, {});
    const g = (await db.collection('incentive_grants').doc(`women_${W3}`).get()).data();
    assert.deepStrictEqual([g.status, g.remaining, g.buckets.any], ['expired', 0, 0]);
    assert.strictEqual((await userDoc(W3)).incentiveBalance, 0);
    assert.strictEqual((await userDoc(W3)).bonusBalance, 5000);
    assert.strictEqual((await progDoc('women')).counters.expiredAmount, before + 100000);
    assert.ok((await db.collection('incentive_ledger').doc(`expire_women_${W3}`).get()).exists);
    await fns.incentiveExpirySweep.run({}, {});
    assert.strictEqual((await progDoc('women')).counters.expiredAmount, before + 100000);
    assert.strictEqual((await userDoc(WOMAN)).incentiveBalance, 300000, 'muddati o\'tmagan tegilmaydi');
  });

  await check('R1 bekor qilish: admin — qoldiq olinadi, audit; takror — o\'zgarmaydi; oddiy foydalanuvchi — rad', async () => {
    await assert.rejects(call('adminRevokeIncentiveGrant', { grantId: `car_${WOMAN}`, reason: 'test' }, WOMAN), (e) => e.code === 'permission-denied');
    await expectCode(call('adminRevokeIncentiveGrant', { grantId: `car_${WOMAN}`, reason: '' }, ADMIN), 'VALIDATION_reason');
    const r = await call('adminRevokeIncentiveGrant', { grantId: `car_${WOMAN}`, reason: 'soxta mashina' }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, changed: true, amount: 200000 });
    assert.strictEqual((await userDoc(WOMAN)).incentiveBalance, 100000);
    const again = await call('adminRevokeIncentiveGrant', { grantId: `car_${WOMAN}`, reason: 'soxta mashina' }, ADMIN);
    assert.deepStrictEqual(again, { ok: true, changed: false, amount: 0 });
    assert.strictEqual((await progDoc('car')).counters.revokedAmount, 200000);
  });

  await check('S1 bosqichni o\'chirish — yangi da\'vo PROGRAM_OFF, takliflardan yo\'qoladi', async () => {
    await call('adminSetIncentiveStage', { programId: 'car', stage: 'off' }, ADMIN);
    const C3 = '998914000040';
    await mk(C3, { gender: 'male', carModel: 'Nexia', carColor: 'oq', carPlate: '01C222CC', carSeats: 4 });
    await expectCode(call('claimIncentive', { programId: 'car' }, C3), 'PROGRAM_OFF');
    const o = await call('getMyIncentiveOffers', {}, C3);
    assert.ok(!o.offers.some((x) => x.programId === 'car'));
    await expectCode(call('adminSetIncentiveStage', { programId: 'car', stage: 'on' }, ADMIN), 'VALIDATION_stage');
  });

  const passed = results.filter(Boolean).length;
  console.log(`${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
