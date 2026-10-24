/**
 * `functions/tools/set_account_deletion.js` — dry-run, audit, idempotentlik, chegaralar.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-gate \
 *     "node test/account_deletion_gate_tool.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-gate';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { setAccountDeletion } = require('../tools/set_account_deletion');
const { createAccountDeletion } = require('../account_deletion');

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
const gate = async () => (await db.collection('settings').doc('account_deletion').get()).data();
const audits = async () => (await db.collection('admin_audit').where('kind', '==', 'account_deletion_gate_changed').get()).docs.map((d) => d.data());

async function main() {
  await clearEmulator();

  await check('G1 dry-run: hech narsa yozilmaydi, would_set', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: true, waitDays: 7 });
    assert.strictEqual(r.action, 'would_set');
    assert.deepStrictEqual(r.from, { enabled: false, waitDays: 10, allow: [] });
    assert.deepStrictEqual(r.to, { enabled: true, waitDays: 7, allow: [] });
    assert.strictEqual(await gate(), undefined);
    assert.strictEqual((await audits()).length, 0);
  });

  await check('G2 apply: sozlama + audit bir vaqtda; xizmat darvozani ochiq ko\'radi', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: true, waitDays: 7, apply: true });
    assert.strictEqual(r.action, 'set');
    const g = await gate();
    assert.strictEqual(g.enabled, true);
    assert.strictEqual(g.waitDays, 7);
    const a = await audits();
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual(a[0].changes[0].to, { enabled: true, waitDays: 7, allow: [] });
    assert.strictEqual(a[0].actor, 'script:set_account_deletion');
    const svc = createAccountDeletion({ db, admin, auth: {}, log: () => {} });
    assert.deepStrictEqual(await svc.readConfig(), { enabled: true, waitDays: 7, allow: [] });
  });

  await check('G3 idempotent: o\'zgarish yo\'q bo\'lsa — already, qo\'shimcha audit yo\'q', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: true, waitDays: 7, apply: true });
    assert.strictEqual(r.action, 'already');
    assert.strictEqual((await audits()).length, 1);
  });

  await check('G4 waitDays berilmasa joriy qiymat saqlanadi; yopish: enabled=false', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: false, apply: true });
    assert.strictEqual(r.action, 'set');
    assert.deepStrictEqual(r.to, { enabled: false, waitDays: 7, allow: [] });
    const svc = createAccountDeletion({ db, admin, auth: {}, log: () => {} });
    assert.strictEqual((await svc.readConfig()).enabled, false);
    assert.strictEqual((await audits()).length, 2);
  });

  await check('G6 INTERNAL: allow ro\'yxati — normallashadi (9 xonali, +, bo\'shliq, takror), saqlanadi va audit\'ga tushadi', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: true, allow: ['+998 90 111-22-33', '901112233', '998907776655'], apply: true });
    assert.strictEqual(r.action, 'set');
    assert.deepStrictEqual(r.to.allow, ['998901112233', '998907776655']);
    assert.deepStrictEqual((await gate()).allow, ['998901112233', '998907776655']);
    const svc = createAccountDeletion({ db, admin, auth: {}, log: () => {} });
    assert.deepStrictEqual((await svc.readConfig()).allow, ['998901112233', '998907776655']);
    // allow berilmasa — joriy ro'yxat saqlanadi
    const same = await setAccountDeletion(db, admin, { enabled: true, apply: true });
    assert.strictEqual(same.action, 'already');
  });

  await check('G7 PUBLIC: allow=[] ro\'yxatni tozalaydi; noto\'g\'ri telefon/tur rad etiladi', async () => {
    const r = await setAccountDeletion(db, admin, { enabled: true, allow: [], apply: true });
    assert.deepStrictEqual(r.to.allow, []);
    await assert.rejects(setAccountDeletion(db, admin, { enabled: true, allow: ['12345'], apply: true }), /allow/);
    await assert.rejects(setAccountDeletion(db, admin, { enabled: true, allow: 'x', apply: true }), /allow/);
    assert.deepStrictEqual((await gate()).allow, []);
  });

  await check('G5 noto\'g\'ri kiritish rad etiladi (enabled turi, waitDays 0/61/kasr/matn) — hech narsa yozilmaydi', async () => {
    const before = await gate();
    for (const bad of [{ enabled: 'true' }, { enabled: undefined }, { enabled: true, waitDays: 0 }, { enabled: true, waitDays: 61 },
      { enabled: true, waitDays: 2.5 }, { enabled: true, waitDays: 'x' }]) {
      await assert.rejects(setAccountDeletion(db, admin, { ...bad, apply: true }), /enabled|waitDays/);
    }
    assert.deepStrictEqual(await gate(), before);
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
