/**
 * HISOBNI O'CHIRISH — admin callable'lari, HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-admin \
 *     "node test/account_deletion_admin_cf.test.js"
 *
 * Qulflanadi: rollar (list/detail/cancel — admin|superadmin; request/retry/gate — faqat superadmin), sabab majburiy,
 * har o'zgartiruvchi amal admin_audit'ga tushadi, kutish muddati qisqartirilmaydi, ichki xato matni sizib chiqmaydi.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-admin';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const db = admin.firestore();

const SUPER = '998901000001';
const ADMIN = '998901000002';
const DISP = '998901000003';
const U = '998901112233';
const OTHER = '998907776655';
const NOBODY = '998909990000';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data || {}, who ? ctxOf(who) : {});
const codeOf = (e) => (e.details && e.details.code) || e.message;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectErr(promise, status, code) {
  await assert.rejects(promise, (e) => {
    assert.strictEqual(e.code, status, `status ${e.code}: ${e.message}`);
    if (code) assert.strictEqual(codeOf(e), code, `kod ${codeOf(e)}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get());
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

async function seed() {
  await clearEmulator();
  await db.collection('settings').doc('account_deletion').set({ enabled: true });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin', phone: `+${SUPER}` });
  await db.collection('users').doc(ADMIN).set({ role: 'admin', phone: `+${ADMIN}` });
  await db.collection('users').doc(DISP).set({ role: 'dispatcher', phone: `+${DISP}` });
  await db.collection('users').doc(U).set({ role: 'user', phone: `+${U}`, name: 'Ali', bonusBalance: 30000, fcmToken: 'tok' });
  await db.collection('users').doc(OTHER).set({ role: 'user', phone: `+${OTHER}`, name: 'Vali' });
}

async function main() {
  await seed();

  await check('A1 rollar: kirmagan va oddiy foydalanuvchi/dispetcher — rad; admin ko\'ra oladi', async () => {
    await expectErr(call('adminListAccountDeletions', {}, null), 'unauthenticated');
    await expectErr(call('adminListAccountDeletions', {}, U), 'permission-denied');
    await expectErr(call('adminListAccountDeletions', {}, DISP), 'permission-denied');
    const r = await call('adminListAccountDeletions', {}, ADMIN);
    assert.deepStrictEqual(r.rows, []);
  });

  await check('A2 faqat superadmin: qo\'lda so\'rov, qayta yuritish, darvoza o\'zgartirish (admin rad etiladi)', async () => {
    await expectErr(call('adminRequestAccountDeletion', { phone: U, reason: 'chat orqali' }, ADMIN), 'permission-denied');
    await expectErr(call('adminRetryAccountDeletion', { uid: U, reason: 'qayta' }, ADMIN), 'permission-denied');
    await expectErr(call('adminSetAccountDeletionGate', { enabled: false, reason: 'to\'xtatish' }, ADMIN), 'permission-denied');
    assert.strictEqual((await get(`account_deletions/${U}`)).exists, false);
    assert.strictEqual((await get('settings/account_deletion')).data().enabled, true);
  });

  await check('Q1 qo\'lda so\'rov (superadmin): PENDING, manba=admin, audit (kim/sabab/kimga); takroriy — duplicate', async () => {
    const r = await call('adminRequestAccountDeletion', { phone: '+998 90 111-22-33', reason: 'email orqali so\'radi' }, SUPER);
    assert.strictEqual(r.status, 'PENDING');
    assert.strictEqual(r.duplicate, false);
    const st = (await get(`account_deletions/${U}`)).data();
    assert.strictEqual(st.source, 'admin');
    assert.strictEqual((await get(`users/${U}`)).data().deletion.status, 'PENDING');
    const a = await audits('account_deletion_admin_request');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].targetId, U);
    assert.strictEqual(a[0].reason, 'email orqali so\'radi');
    const r2 = await call('adminRequestAccountDeletion', { phone: U, reason: 'takror' }, SUPER);
    assert.strictEqual(r2.duplicate, true);
    assert.strictEqual((await audits('account_deletion_admin_request')).length, 1); // takrorda audit yo'q
  });

  await check('Q2 sabab majburiy; noma\'lum hisob, noto\'g\'ri telefon, blokirovka, yopiq darvoza — tushunarli kodlar', async () => {
    await expectErr(call('adminRequestAccountDeletion', { phone: OTHER, reason: ' ' }, SUPER), 'invalid-argument', 'REASON_REQUIRED');
    await expectErr(call('adminRequestAccountDeletion', { phone: NOBODY, reason: 'sabab' }, SUPER), 'not-found', 'ACCOUNT_NOT_FOUND');
    await expectErr(call('adminRequestAccountDeletion', { phone: '123', reason: 'sabab' }, SUPER), 'not-found', 'ACCOUNT_NOT_FOUND');
    await db.collection('orders').doc('o1').set({ userPhone: OTHER, status: 'new' });
    await assert.rejects(call('adminRequestAccountDeletion', { phone: OTHER, reason: 'sabab' }, SUPER), (e) => {
      assert.strictEqual(codeOf(e), 'ACCOUNT_DELETION_BLOCKED');
      assert.deepStrictEqual(e.details.blockers.map((b) => b.code), ['ORDER_ACTIVE']);
      return true;
    });
    await db.collection('orders').doc('o1').delete();
    await db.collection('settings').doc('account_deletion').set({ enabled: false });
    await expectErr(call('adminRequestAccountDeletion', { phone: OTHER, reason: 'sabab' }, SUPER), 'failed-precondition', 'ACCOUNT_DELETION_DISABLED');
    await db.collection('settings').doc('account_deletion').set({ enabled: true });
    assert.strictEqual((await get(`account_deletions/${OTHER}`)).exists, false);
  });

  await check('L1 ro\'yxat: standart faol holatlar; FAILED birinchi; DONE/CANCELLED so\'ralganda; noto\'g\'ri holat — rad', async () => {
    await db.doc(`account_deletions/${OTHER}`).set({ status: 'FAILED', requestedAt: ts(1000), scheduledFor: ts(2000), attempts: 5, lastError: 'auth down', source: 'app' });
    await db.doc('account_deletions/998901234500').set({ status: 'DONE', requestedAt: ts(500), completedAt: ts(900) });
    await db.doc('account_deletions/998901234501').set({ status: 'CANCELLED', requestedAt: ts(400) });
    const r = await call('adminListAccountDeletions', {}, ADMIN);
    assert.deepStrictEqual(r.rows.map((x) => x.status), ['FAILED', 'PENDING']);
    assert.strictEqual(r.rows[0].uid, OTHER);
    assert.strictEqual(r.rows[0].lastError, 'auth down');
    assert.strictEqual(r.rows[0].attempts, 5);
    assert.strictEqual(r.rows[1].uid, U);
    assert.strictEqual(r.rows[1].walletAtRequest, 30000);
    const all = await call('adminListAccountDeletions', { statuses: ['DONE', 'CANCELLED'] }, ADMIN);
    assert.deepStrictEqual(all.rows.map((x) => x.status).sort(), ['CANCELLED', 'DONE']);
    await expectErr(call('adminListAccountDeletions', { statuses: ['PENDING', 'HACK'] }, ADMIN), 'invalid-argument', 'INVALID_STATUS');
    const lim = await call('adminListAccountDeletions', { limit: 1 }, ADMIN);
    assert.strictEqual(lim.rows.length, 1);
    assert.strictEqual(lim.truncated, true);
  });

  await check('L2 ro\'yxat qatorida ortiqcha shaxsiy ma\'lumot yo\'q (fcmToken, ism, manzil, hamyon tarixi)', async () => {
    const r = await call('adminListAccountDeletions', {}, ADMIN);
    const keys = Object.keys(r.rows.find((x) => x.uid === U)).sort();
    assert.deepStrictEqual(keys, ['attempts', 'completedAtMs', 'hidePending', 'lastBlockers', 'lastError', 'nextCheckAtMs',
      'requestedAtMs', 'scheduledForMs', 'source', 'status', 'uid', 'walletAtRequest']);
    assert.ok(!JSON.stringify(r).includes('tok'));
  });

  await check('D1 tafsilot: holat, qadamlar, oxirgi voqealar (yangidan eskiga); yo\'q so\'rov va noto\'g\'ri uid', async () => {
    const d = await call('adminGetAccountDeletion', { uid: U }, ADMIN);
    assert.strictEqual(d.status, 'PENDING');
    assert.ok(d.events.length >= 1);
    assert.strictEqual(d.events[0].type, 'requested');
    assert.strictEqual(typeof d.events[0].atMs, 'number');
    assert.strictEqual(d.hiddenCount, 0);
    assert.deepStrictEqual(d.steps, {});
    await expectErr(call('adminGetAccountDeletion', { uid: NOBODY }, ADMIN), 'failed-precondition', 'ACCOUNT_DELETION_NOT_PENDING');
    await expectErr(call('adminGetAccountDeletion', { uid: 'abc' }, ADMIN), 'not-found', 'ACCOUNT_NOT_FOUND');
  });

  await check('X1 admin bekor qiladi: CANCELLED, users.deletion olinadi, audit; sabab majburiy; qayta bekor — NOT_PENDING', async () => {
    await expectErr(call('adminCancelAccountDeletion', { uid: U, reason: 'ab' }, ADMIN), 'invalid-argument', 'REASON_REQUIRED');
    assert.strictEqual((await get(`account_deletions/${U}`)).data().status, 'PENDING'); // sababsiz tegilmadi
    const r = await call('adminCancelAccountDeletion', { uid: U, reason: 'foydalanuvchi chatda fikridan qaytdi' }, ADMIN);
    assert.strictEqual(r.status, 'CANCELLED');
    assert.strictEqual((await get(`account_deletions/${U}`)).data().status, 'CANCELLED');
    assert.strictEqual((await get(`users/${U}`)).data().deletion, undefined);
    const a = await audits('account_deletion_admin_cancel');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].actor, ADMIN);
    assert.strictEqual(a[0].actorRole, 'admin');
    assert.strictEqual(a[0].targetId, U);
    assert.strictEqual(a[0].reason, 'foydalanuvchi chatda fikridan qaytdi');
    const evs = await call('adminGetAccountDeletion', { uid: U }, ADMIN);
    assert.strictEqual(evs.events[0].type, 'cancelled');
    assert.strictEqual(evs.events[0].meta.by, ADMIN);
    await expectErr(call('adminCancelAccountDeletion', { uid: U, reason: 'takror sabab' }, ADMIN), 'failed-precondition', 'ACCOUNT_DELETION_NOT_PENDING');
    assert.strictEqual((await audits('account_deletion_admin_cancel')).length, 1);
  });

  await check('X2 ijro boshlangan (EXECUTING) bo\'lsa admin ham bekor qila olmaydi; audit yozilmaydi', async () => {
    await db.doc(`account_deletions/${OTHER}`).update({ status: 'EXECUTING' });
    await expectErr(call('adminCancelAccountDeletion', { uid: OTHER, reason: 'kerak edi' }, ADMIN), 'failed-precondition', 'ACCOUNT_DELETION_IN_PROGRESS');
    assert.strictEqual((await audits('account_deletion_admin_cancel')).length, 1);
    await db.doc(`account_deletions/${OTHER}`).update({ status: 'FAILED' });
  });

  await check('R1 qayta yuritish: FAILED → POSTPONED (urinishlar 0, darhol navbat), audit; PENDING/so\'rovsiz/sabab — rad', async () => {
    await expectErr(call('adminRetryAccountDeletion', { uid: OTHER, reason: '' }, SUPER), 'invalid-argument', 'REASON_REQUIRED');
    const r = await call('adminRetryAccountDeletion', { uid: OTHER, reason: 'Auth tiklandi' }, SUPER);
    assert.strictEqual(r.status, 'POSTPONED');
    const st = (await get(`account_deletions/${OTHER}`)).data();
    assert.strictEqual(st.status, 'POSTPONED');
    assert.strictEqual(st.attempts, 0);
    assert.ok(st.nextCheckAt.toMillis() <= Date.now() + 5000);
    const a = await audits('account_deletion_admin_retry');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].reason, 'Auth tiklandi');
    // endi FAILED emas
    await expectErr(call('adminRetryAccountDeletion', { uid: OTHER, reason: 'takror' }, SUPER), 'failed-precondition', 'ACCOUNT_DELETION_NOT_FAILED');
    await expectErr(call('adminRetryAccountDeletion', { uid: NOBODY, reason: 'yo\'q' }, SUPER), 'failed-precondition', 'ACCOUNT_DELETION_NOT_PENDING');
  });

  await check('R2 kutish muddatini qisqartirib bo\'lmaydi: PENDING so\'rovni "qayta yuritish" rad etiladi, muddat o\'zgarmaydi', async () => {
    await call('adminRequestAccountDeletion', { phone: U, reason: 'yana so\'radi' }, SUPER);
    const before = (await get(`account_deletions/${U}`)).data().scheduledFor.toMillis();
    await expectErr(call('adminRetryAccountDeletion', { uid: U, reason: 'tezlatish' }, SUPER), 'failed-precondition', 'ACCOUNT_DELETION_NOT_FAILED');
    assert.strictEqual((await get(`account_deletions/${U}`)).data().scheduledFor.toMillis(), before);
  });

  await check('G1 darvoza: o\'qish (admin), yozish (superadmin) — audit sabab bilan; noto\'g\'ri qiymatlar rad', async () => {
    const g = await call('adminGetAccountDeletionGate', {}, ADMIN);
    assert.deepStrictEqual(g, { enabled: true, waitDays: 10, allow: [] });
    await expectErr(call('adminSetAccountDeletionGate', { enabled: true, waitDays: 7, reason: ' ' }, SUPER), 'invalid-argument', 'REASON_REQUIRED');
    const r = await call('adminSetAccountDeletionGate', { enabled: true, waitDays: 7, allow: ['+998 90 111-22-33'], reason: 'ichki sinov' }, SUPER);
    assert.strictEqual(r.action, 'set');
    assert.deepStrictEqual(await call('adminGetAccountDeletionGate', {}, ADMIN), { enabled: true, waitDays: 7, allow: [U] });
    const a = await audits('account_deletion_gate_changed');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].actorRole, 'superadmin');
    assert.strictEqual(a[0].source, 'admin_panel');
    assert.strictEqual(a[0].reason, 'ichki sinov');
    for (const bad of [{ waitDays: 0 }, { waitDays: 61 }, { allow: ['12345'] }, { allow: 'x' }, { enabled: 'yes' }]) {
      await expectErr(call('adminSetAccountDeletionGate', { enabled: true, reason: 'sinov', ...bad }, SUPER), 'invalid-argument', 'INVALID_GATE');
    }
    assert.deepStrictEqual(await call('adminGetAccountDeletionGate', {}, ADMIN), { enabled: true, waitDays: 7, allow: [U] });
    assert.strictEqual((await audits('account_deletion_gate_changed')).length, 1);
  });

  await check('G2 INTERNAL ro\'yxatdan tashqari qo\'lda so\'rov ham rad etiladi (darvoza admin so\'roviga ham amal qiladi)', async () => {
    await expectErr(call('adminRequestAccountDeletion', { phone: OTHER, reason: 'sinov' }, SUPER), 'failed-precondition', 'ACCOUNT_DELETION_DISABLED');
    await call('adminSetAccountDeletionGate', { enabled: false, reason: 'yopish' }, SUPER);
    assert.strictEqual((await call('adminGetAccountDeletionGate', {}, SUPER)).enabled, false);
  });

  await check('E1 g\'alati limit/statuses qiymatlari xavfsiz standartga tushadi (xato chiqmaydi)', async () => {
    const r = await call('adminListAccountDeletions', { limit: { x: 1 }, statuses: [] }, ADMIN);
    assert.ok(Array.isArray(r.rows));
    const r2 = await call('adminListAccountDeletions', { limit: 100000 }, ADMIN);
    assert.ok(r2.rows.length <= 200);
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
