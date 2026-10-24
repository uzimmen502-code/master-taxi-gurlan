/**
 * HISOBNI O'CHIRISH — callable qatlami, HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-callable \
 *     "node test/account_deletion_callable_cf.test.js"
 *
 * Tekshiriladi: autentifikatsiya, yopiq darvoza, foydalanuvchi uchun xato matni va kodi (stack trace yo'q),
 * blokirovka tafsilotlari klientga ID'siz boradi, faqat O'Z hisobi (token telefoni) ustida ishlaydi.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-callable';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const db = admin.firestore();

const U = '998901112233';
const OTHER = '998907776655';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data || {}, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const codeOf = (e) => (e.details && e.details.code) || e.message;

async function main() {
  await clearEmulator();
  await db.collection('users').doc(U).set({ role: 'user', phone: `+${U}`, bonusBalance: 1000 });
  await db.collection('users').doc(OTHER).set({ role: 'user', phone: `+${OTHER}`, bonusBalance: 5 });

  await check('N1 callable\'lar eksport qilingan va rejali ijro funksiyasi mavjud', () => {
    for (const n of ['previewAccountDeletion', 'requestAccountDeletion', 'cancelAccountDeletion', 'executeAccountDeletions']) {
      assert.ok(fns[n], `${n} yo'q`);
    }
  });

  await check('N2 autentifikatsiyasiz — unauthenticated', async () => {
    for (const n of ['previewAccountDeletion', 'requestAccountDeletion', 'cancelAccountDeletion']) {
      await assert.rejects(call(n, {}, null), (e) => { assert.strictEqual(e.code, 'unauthenticated', n); return true; });
    }
  });

  await check('N3 darvoza yopiq (sozlama yo\'q) — ACCOUNT_DELETION_DISABLED, foydalanuvchi matni, ichki tafsilot yo\'q', async () => {
    await assert.rejects(call('requestAccountDeletion', {}, U), (e) => {
      assert.strictEqual(e.code, 'failed-precondition');
      assert.strictEqual(codeOf(e), 'ACCOUNT_DELETION_DISABLED');
      assert.ok(!/stack|at \w+\.|node_modules/i.test(e.message));
      return true;
    });
    assert.strictEqual((await db.collection('account_deletions').doc(U).get()).exists, false);
  });

  await check('N4 preview yopiq darvozada ham ishlaydi, faqat o\'qiydi', async () => {
    const p = await call('previewAccountDeletion', {}, U);
    assert.strictEqual(p.enabled, false);
    assert.strictEqual(p.walletAmount, 1000);
    assert.deepStrictEqual(p.blockers, []);
  });

  await check('N5 darvoza ochiq: so\'rov PENDING; faqat O\'Z hisobi (mijoz yuborgan telefon e\'tiborsiz)', async () => {
    await db.collection('settings').doc('account_deletion').set({ enabled: true });
    // klient boshqa raqam yuborsa ham token telefoni ishlatiladi
    const r = await call('requestAccountDeletion', { uid: OTHER, phone: OTHER }, U);
    assert.strictEqual(r.status, 'PENDING');
    assert.strictEqual((await db.collection('account_deletions').doc(U).get()).exists, true);
    assert.strictEqual((await db.collection('account_deletions').doc(OTHER).get()).exists, false);
    assert.strictEqual((await db.collection('users').doc(OTHER).get()).data().deletion, undefined);
  });

  await check('N6 takroriy so\'rov — duplicate: true; bekor qilish ishlaydi; so\'rovsiz bekor — NOT_PENDING', async () => {
    const r2 = await call('requestAccountDeletion', {}, U);
    assert.strictEqual(r2.duplicate, true);
    await assert.rejects(call('cancelAccountDeletion', {}, OTHER), (e) => { assert.strictEqual(codeOf(e), 'ACCOUNT_DELETION_NOT_PENDING'); return true; });
    const c = await call('cancelAccountDeletion', {}, U);
    assert.strictEqual(c.status, 'CANCELLED');
  });

  await check('N7 blokirovka: kod va guruh klientga boradi, hujjat ID si yo\'q', async () => {
    await db.collection('orders').doc('o1').set({ userPhone: U, status: 'new' });
    await assert.rejects(call('requestAccountDeletion', {}, U), (e) => {
      assert.strictEqual(e.code, 'failed-precondition');
      assert.strictEqual(codeOf(e), 'ACCOUNT_DELETION_BLOCKED');
      const b = e.details.blockers;
      assert.deepStrictEqual(b.map((x) => x.code), ['ORDER_ACTIVE']);
      assert.ok(!('sample' in b[0]));
      return true;
    });
  });

  await check('N8 noma\'lum hisob — not-found va ACCOUNT_NOT_FOUND kodi', async () => {
    await assert.rejects(call('requestAccountDeletion', {}, '998909990000'), (e) => {
      assert.strictEqual(e.code, 'not-found');
      assert.strictEqual(codeOf(e), 'ACCOUNT_NOT_FOUND');
      return true;
    });
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
