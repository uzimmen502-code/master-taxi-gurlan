/**
 * R-7 — taksi operatsion qoidalari CAPABILITY bo'yicha (D-TAXI-1…5, D-CLEAN-1).
 *
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/taxi_capability_rules.test.js"
 *
 * Avval `schedules`/`queue` yaratish `drivers.approved` talab qilardi.
 * Endi: `provider_capabilities.status.taxi`:
 *   starter | verified              → yangi ish kuni / navbat (PUBLISH)
 *   verification_required           → mavjud ish HA, yangi PUBLISH YO'Q
 *   drivers.approved (legacy)       → HECH NARSA (D-CLEAN-1)
 * Taksi turi — `taxi.taxiTypes` deklaratsiyasi (filtr).
 *
 * Bu yo'llar avval HECH QAYSI testda ijobiy holat bilan sinalmagan edi —
 * R-7 almashtirilganda 309 tekshiruv o'zgarmay o'tdi, ya'ni qamrov bo'shlig'i.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');

const STARTER = '998901110001';
const VERIFIED9 = '902220002';
const VERIFIED12 = '998902220002';
const VREQ = '998903330003';
const LEGACY = '998904440004';
const NOCAP = '998905550005';

function schedule(driverId, taxiType = 'intercity') {
  return {
    driverId, taxiType, date: '2026-10-07', seats: 4, seatsLeft: 4, isActive: true,
    from: 'Urganch', to: 'Toshkent', expiresAt: new Date(Date.now() + 86400000), createdAt: new Date(),
  };
}
function queue(driverId, taxiType = 'intercity') {
  return { driverId, taxiType, from: 'Urganch', to: 'Toshkent', seats: 4, seatsLeft: 4, isActive: true, onlineAt: new Date() };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-taxi-cap',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const record = (n, p, d) => { results.push({ n, p }); console.log(`${p ? 'PASS' : 'FAIL'} - ${n}${d ? ' :: ' + d : ''}`); };
  const check = async (n, fn) => { try { await fn(); record(n, true); } catch (e) { record(n, false, e.message); } };

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const cap = (acc, uid, status, types) => ({
      identity: { accountId: acc, primaryUid: uid },
      taxi: { active: true, taxiTypes: types },
      status: { taxi: status },
    });
    await db.collection('users').doc(STARTER).set({ accountId: 'accSTARTER' });
    await db.collection('provider_capabilities').doc('accSTARTER').set(cap('accSTARTER', STARTER, 'starter', ['intercity']));
    // Eski 9 xonali users kaliti.
    await db.collection('users').doc(VERIFIED9).set({ accountId: 'accVERIFIED' });
    await db.collection('provider_capabilities').doc('accVERIFIED').set(cap('accVERIFIED', VERIFIED12, 'verified', ['local']));
    await db.collection('users').doc(VREQ).set({ accountId: 'accVREQ' });
    await db.collection('provider_capabilities').doc('accVREQ').set(cap('accVREQ', VREQ, 'verification_required', ['intercity']));
    // Legacy: faqat drivers.approved, capability yo'q.
    await db.collection('users').doc(LEGACY).set({ role: 'driver' });
    await db.collection('drivers').doc(LEGACY).set({ approved: true, approvalStatus: 'approved', taxiTypes: ['intercity'], name: 'L', phone: LEGACY });
    await db.collection('users').doc(NOCAP).set({});
    // verification_required haydovchining MAVJUD jadvali — operate uchun.
    await db.collection('schedules').doc('vreq_sched').set({ ...schedule(VREQ), seatsLeft: 3 });
    await db.collection('drivers').doc(VREQ).set({ name: 'V', phone: VREQ, isOnline: false });
  });
  const ctxFor = (p) => testEnv.authenticatedContext(`uid_${p}`, { phone_number: '+' + p });
  const starter = ctxFor(STARTER).firestore();
  const verified = ctxFor(VERIFIED12).firestore();
  const vreq = ctxFor(VREQ).firestore();
  const legacy = ctxFor(LEGACY).firestore();
  const nocap = ctxFor(NOCAP).firestore();

  // ── PUBLISH: schedules / queue ──────────────────────────────────────
  await check('STARTER yangi ish kuni yaratadi (D-TAXI-1: admin kutilmaydi)',
    () => assertSucceeds(starter.collection('schedules').doc('s1').set(schedule(STARTER))));
  await check('STARTER navbatga kiradi',
    () => assertSucceeds(starter.collection('queue').doc(STARTER).set(queue(STARTER))));
  await check('VERIFIED (9 xonali users kaliti) ham yaratadi — o\'z turi bilan',
    () => assertSucceeds(verified.collection('schedules').doc('s2').set(schedule(VERIFIED12, 'local'))));
  await check('`alone` ↔ `local` sinonimi ishlaydi',
    () => assertSucceeds(verified.collection('queue').doc(VERIFIED12).set(queue(VERIFIED12, 'alone'))));
  await check('deklaratsiya qilinmagan tur RAD (verified lekin faqat local)',
    () => assertFails(verified.collection('schedules').doc('s3').set(schedule(VERIFIED12, 'intercity'))));
  await check('VERIFICATION_REQUIRED yangi ish kuni yarata OLMAYDI (D-TAXI-5)',
    () => assertFails(vreq.collection('schedules').doc('s4').set(schedule(VREQ))));
  await check('VERIFICATION_REQUIRED navbatga kira OLMAYDI',
    () => assertFails(vreq.collection('queue').doc(VREQ).set(queue(VREQ))));
  await check('VERIFICATION_REQUIRED mavjud ishini DAVOM ETTIRADI (seatsLeft patch)',
    () => assertSucceeds(vreq.collection('schedules').doc('vreq_sched').update({ seatsLeft: 2, updatedAt: new Date() })));
  await check('LEGACY drivers.approved HECH NARSA bermaydi (D-CLEAN-1)',
    () => assertFails(legacy.collection('schedules').doc('s5').set(schedule(LEGACY))));
  await check('LEGACY navbatga ham kira olmaydi',
    () => assertFails(legacy.collection('queue').doc(LEGACY).set(queue(LEGACY))));
  await check('capability\'siz foydalanuvchi yarata olmaydi',
    () => assertFails(nocap.collection('schedules').doc('s6').set(schedule(NOCAP))));
  await check('starter BOSHQA haydovchi nomidan jadval yarata olmaydi (egalik)',
    () => assertFails(starter.collection('schedules').doc('s7').set(schedule(VERIFIED12, 'local'))));
  await check('starter boshqa haydovchining navbatini yarata olmaydi',
    () => assertFails(starter.collection('queue').doc(VREQ).set(queue(VREQ))));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.p);
  console.log(`\n${results.length - failed.length}/${results.length} taxi capability rules checks passed.`);
  if (failed.length) { console.log('FAILED:', failed.map((f) => f.n).join(', ')); process.exitCode = 1; }
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
