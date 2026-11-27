/**
 * «Ишлаб чиқарувчи завод/фабрикалар» (эга 2026-11-28) — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator.
 *
 *   npm run test:factories-cf   (functions/ ичидан)
 *
 *   P1  соф: normalizeOptions / nextVerifyStatus; job_vacancy normalizeVacancy / salaryText чегаралари
 *   F1  эга танлови ёзилади (4 bool), қайта — noop; avaSupplierReadyAt сақланади
 *   F2  бегона / блокланган / завод эмас / бузуқ танлов — диагностик код, ёзув йўқ
 *   F3  MANUAL: сўров → pending (audit йўқ); қайта сўров — ўзгармайди
 *   F4  AUTO: сўров → approved + admin_audit (actor auto)
 *   F5  админ қарори: approved / rejected (сабаб шарт) + admin_audit; ўша қарор қайта — noop; админ эмас — рад
 *   F6  режим алмашуви: settings/app.producerVerifyAutoApprove + admin_audit; ўша қиймат — noop
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-factories-cf';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { normalizeOptions, nextVerifyStatus } = require('../factories');
const { normalizeVacancy, salaryText } = require('../job_vacancy');

const db = admin.firestore();
const OWNER = '998914000001';
const OTHER = '998914000002';
const ADMIN = '998914000009';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, ctxOf(who));
const OPTS = { sellWholesale: true, showVideos: true, publishVacancies: false, avaSupplierReady: true };

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
async function seed() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${OWNER}`).set({ role: 'user' });
  await db.doc('businesses/f1').set({ ownerId: OWNER, name: 'Завод', category: 'manufacturing', status: 'active' });
  await db.doc('businesses/f_block').set({ ownerId: OWNER, name: 'Блок', category: 'manufacturing', status: 'blocked' });
  await db.doc('businesses/shop1').set({ ownerId: OWNER, name: 'Дўкон', category: 'retail', status: 'active' });
}
const biz = async (id) => (await db.doc(`businesses/${id}`).get()).data();
const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());

async function main() {
  await check('P1 sof funksiyalar: tanlov, tasdiq holati, vakansiya chegaralari', async () => {
    assert.deepStrictEqual(normalizeOptions(OPTS), OPTS);
    assert.strictEqual(normalizeOptions({ ...OPTS, showVideos: 'yes' }), null);
    assert.strictEqual(normalizeOptions({}), null);
    assert.strictEqual(nextVerifyStatus('', false), 'pending');
    assert.strictEqual(nextVerifyStatus('rejected', true), 'approved');
    assert.strictEqual(nextVerifyStatus('pending', true), null);
    assert.strictEqual(nextVerifyStatus('approved', false), null);
    const f = (c) => new Error(c);
    const base = { position: 'Usta', salaryFrom: 1, schedule: 'shift', experience: 'none', requirements: '1234567890' };
    assert.strictEqual(normalizeVacancy(base, f).vacancy.salaryFrom, 1); // pastki chegara
    assert.throws(() => normalizeVacancy({ ...base, requirements: '123456789' }, f), /VACANCY_REQUIREMENTS_INVALID/);
    assert.throws(() => normalizeVacancy({ ...base, salaryFrom: 1000000001 }, f), /VACANCY_SALARY_INVALID/);
    assert.strictEqual(normalizeVacancy({ ...base, salaryFrom: 1000000000 }, f).vacancy.salaryFrom, 1000000000);
    assert.throws(() => normalizeVacancy({ ...base, position: 'x'.repeat(81) }, f), /VACANCY_POSITION_INVALID/);
    assert.throws(() => normalizeVacancy(null, f), /VACANCY_REQUIRED/);
    assert.throws(() => normalizeVacancy({ ...base, employerKind: 'business' }, f), /VACANCY_EMPLOYER_INVALID/);
    assert.strictEqual(salaryText({ salaryTo: 2000000 }), '2 000 000 сўмгача');
    assert.strictEqual(salaryText({ salaryFrom: 5, salaryTo: 5 }), '5 сўм');
  });

  await seed();
  await check('F1 ega tanlovi yoziladi; qayta — noop; avaSupplierReadyAt saqlanadi', async () => {
    const r = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS }, OWNER);
    assert.strictEqual(r.changed, true);
    const f = (await biz('f1')).factory;
    assert.strictEqual(f.sellWholesale, true);
    assert.strictEqual(f.publishVacancies, false);
    assert.ok(f.avaSupplierReadyAt);
    const again = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS }, OWNER);
    assert.strictEqual(again.changed, false);
    await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, publishVacancies: true }, OWNER);
    const f2 = (await biz('f1')).factory;
    assert.strictEqual(f2.avaSupplierReadyAt.toMillis(), f.avaSupplierReadyAt.toMillis());
    await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, avaSupplierReady: false }, OWNER);
    assert.strictEqual((await biz('f1')).factory.avaSupplierReadyAt, undefined);
    assert.strictEqual((await biz('f1')).producerVerification, undefined);
  });

  await seed();
  await check('F2 begona / bloklangan / zavod emas / buzuq tanlov — rad, yozuv yo\'q', async () => {
    await expectCode(call('setMyFactoryOptions', { businessId: 'f1', ...OPTS }, OTHER), 'BUSINESS_NOT_OWNER');
    await expectCode(call('setMyFactoryOptions', { businessId: 'f_block', ...OPTS }, OWNER), 'BUSINESS_BLOCKED');
    await expectCode(call('setMyFactoryOptions', { businessId: 'shop1', ...OPTS }, OWNER), 'FACTORY_NOT_MANUFACTURING');
    await expectCode(call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, showVideos: 1 }, OWNER), 'FACTORY_OPTIONS_INVALID');
    await expectCode(call('setMyFactoryOptions', { businessId: 'nope', ...OPTS }, OWNER), 'BUSINESS_NOT_FOUND');
    assert.strictEqual((await biz('f1')).factory, undefined);
  });

  await seed();
  await check('F3 MANUAL: so\'rov → pending, audit yo\'q; qayta so\'rov o\'zgarmaydi', async () => {
    const r = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, requestVerification: true }, OWNER);
    assert.strictEqual(r.verification, 'pending');
    assert.strictEqual((await biz('f1')).producerVerification.status, 'pending');
    assert.strictEqual((await audits('producer_verification')).length, 0);
    const again = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, requestVerification: true }, OWNER);
    assert.strictEqual(again.changed, false);
  });

  await seed();
  await check('F4 AUTO: so\'rov → approved + admin_audit (auto)', async () => {
    await db.doc('settings/app').set({ producerVerifyAutoApprove: true });
    const r = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, requestVerification: true }, OWNER);
    assert.strictEqual(r.verification, 'approved');
    const pv = (await biz('f1')).producerVerification;
    assert.strictEqual(pv.decidedBy, 'auto');
    const a = await audits('producer_verification');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].actor, 'auto');
  });

  await seed();
  await check('F5 admin qarori + audit; sabab shart (rad); takror noop; admin emas — rad', async () => {
    await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, requestVerification: true }, OWNER);
    await expectCode(call('adminSetProducerVerification', { businessId: 'f1', decision: 'rejected' }, ADMIN), 'REASON_REQUIRED');
    await expectCode(call('adminSetProducerVerification', { businessId: 'f1', decision: 'maybe' }, ADMIN), 'VERIFY_DECISION_INVALID');
    await expectCode(call('adminSetProducerVerification', { businessId: 'shop1', decision: 'approved' }, ADMIN), 'FACTORY_NOT_MANUFACTURING');
    await assert.rejects(call('adminSetProducerVerification', { businessId: 'f1', decision: 'approved' }, OWNER), (e) => e.code === 'permission-denied');
    const r = await call('adminSetProducerVerification', { businessId: 'f1', decision: 'approved' }, ADMIN);
    assert.strictEqual(r.changed, true);
    const pv = (await biz('f1')).producerVerification;
    assert.strictEqual(pv.status, 'approved');
    assert.strictEqual(pv.decidedBy, ADMIN);
    assert.ok(pv.requestedAt);
    assert.strictEqual((await call('adminSetProducerVerification', { businessId: 'f1', decision: 'approved' }, ADMIN)).changed, false);
    await call('adminSetProducerVerification', { businessId: 'f1', decision: 'rejected', reason: 'Ҳужжат йўқ' }, ADMIN);
    const a = await audits('producer_verification');
    assert.strictEqual(a.length, 2);
    assert.ok(a.some((x) => x.from === 'approved' && x.to === 'rejected' && x.reason === 'Ҳужжат йўқ'));
    // Rad etilgandan keyin ega qayta so'raydi → pending.
    const again = await call('setMyFactoryOptions', { businessId: 'f1', ...OPTS, requestVerification: true }, OWNER);
    assert.strictEqual(again.verification, 'pending');
  });

  await seed();
  await check('F6 rejim: settings/app + audit; o\'sha qiymat — noop; admin emas — rad', async () => {
    const r = await call('adminSetProducerAutoApprove', { enabled: true }, ADMIN);
    assert.strictEqual(r.changed, true);
    assert.strictEqual((await db.doc('settings/app').get()).data().producerVerifyAutoApprove, true);
    assert.strictEqual((await call('adminSetProducerAutoApprove', { enabled: true }, ADMIN)).changed, false);
    await call('adminSetProducerAutoApprove', { enabled: false }, ADMIN);
    const a = await audits('producer_auto_approve_set');
    assert.strictEqual(a.length, 2);
    await assert.rejects(call('adminSetProducerAutoApprove', { enabled: true }, OWNER), (e) => e.code === 'permission-denied');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
