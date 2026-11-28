/**
 * Qurilma xavfsizligi (ega 2026-11-28) — Cloud Functions, Firestore emulator + soxta Auth.
 *
 *   firebase emulators:exec --only firestore --project demo-devsec "node test/device_security_cf.test.js"
 *
 * Tekshiradi: tasdiqsiz token yo'q (autoApprove sozlamasi e'tiborsiz), Ҳа/Йўқ yo'llari, 24 s blok,
 * sessiyalar bekor, admin ko'rigi, imtiyozli raqamlar, rate limit, 24 s pul chiqimi bloki (har bir
 * chiqim funksiyasi), yopilgan endpoint'lar, audit.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-devsec';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();

// ── Soxta Firebase Auth (emulator'siz) ──────────────────────────────────
const authUsers = new Map(); // e164 -> {uid, phoneNumber, customClaims}
const revoked = [];
const fakeAuth = {
  async getUserByPhoneNumber(e164) {
    const u = authUsers.get(e164);
    if (!u) { const e = new Error('not found'); e.code = 'auth/user-not-found'; throw e; }
    return u;
  },
  async createUser({ phoneNumber }) {
    const u = { uid: `uid_${phoneNumber.replace(/\D/g, '')}`, phoneNumber, customClaims: {} };
    authUsers.set(phoneNumber, u);
    return u;
  },
  async setCustomUserClaims(uid, claims) {
    for (const u of authUsers.values()) if (u.uid === uid) u.customClaims = claims;
  },
  async createCustomToken(uid) { return `token_for_${uid}`; },
  async revokeRefreshTokens(uid) { revoked.push(uid); },
};
// `admin.auth()` bir xil Auth nusxasini qaytaradi — metodlarni nusxaning o'zida almashtiramiz.
Object.assign(admin.auth(), fakeAuth);

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e && e.stack ? e.stack.split('\n').slice(0, 3).join(' | ') : e}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();
const H = (c) => c.repeat(64).slice(0, 64);
let ipSeq = 0;
const anon = () => ({ rawRequest: { headers: { 'x-forwarded-for': `10.0.0.${(ipSeq += 1)}` }, ip: '127.0.0.1' } });
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } }, rawRequest: { headers: {} } });
const FP = (over = {}) => ({
  platform: 'android', androidId: 'andr0id0001', firebaseInstallationId: 'fid_install_0001',
  hardwareId: 'SER1', model: 'SM-A515F', brand: 'samsung', device: 'a51', product: 'a51', fingerprint: 'os-1',
  ...over,
});
const check_ = (data, ctx) => fns.checkDeviceBinding.run(data, ctx || anon());
const events = async (phone) => (await db.collection('device_binding_events').where('phone', '==', phone).get())
  .docs.map((d) => d.data());
const expectCode = (httpsCode, code) => (e) => {
  assert.strictEqual(e.code, httpsCode, `${e.code} != ${httpsCode} (${e.message})`);
  if (code) assert.strictEqual((e.details || {}).code, code);
  return true;
};

/** Raqam + bog'langan qurilma + Auth foydalanuvchisi (ilgari kirgan hisob). */
async function seedBound(phone, hash, fp = FP(), role = 'user', extra = {}) {
  await db.doc(`users/${phone}`).set({ role, name: 'Test User', bonusBalance: 100000, ...extra });
  await db.doc(`device_bindings/${hash}`).set({ phone, deviceFingerprintHash: hash, fingerprint: fp });
  await db.doc(`device_aliases/${phone}`).set({ phone, deviceFingerprintHash: hash });
  authUsers.set(`+${phone}`, { uid: `uid_${phone}`, phoneNumber: `+${phone}`, customClaims: {} });
}

async function main() {
  await clearEmulator();
  await db.doc('settings/app').set({ deviceBindingAutoApprove: true }); // prod holati — e'tiborsiz bo'lishi kerak
  await db.doc('users/998900000001').set({ role: 'admin', name: 'Admin' });
  await db.doc('users/998900000002').set({ role: 'superadmin', name: 'Super' });
  await db.doc('users/998900000003').set({ role: 'finance', name: 'Fin' });
  const ADMIN = '998900000001';
  const SUPER = '998900000002';
  const FIN = '998900000003';

  // ── Tasdiqsiz token yo'q ───────────────────────────────────────────────
  await check('K1 autoApprove=true + raqam boshqa qurilmada → phone_bound_other_device, token YO\'Q, alias o\'zgarmaydi', async () => {
    const A = '998911000001';
    await seedBound(A, H('a'));
    const r = await check_({ phone: A, deviceFingerprintHash: H('b'), fingerprint: FP({ firebaseInstallationId: 'fid_attacker_99', androidId: 'x99999999' }) });
    assert.strictEqual(r.status, 'phone_bound_other_device');
    assert.strictEqual(r.customToken, undefined);
    assert.strictEqual(r.selfServeAvailable, true);
    assert.strictEqual(r.adminReviewAvailable, true);
    assert.strictEqual((await get(`device_aliases/${A}`)).deviceFingerprintHash, H('a'));
    assert.strictEqual(await get(`device_bindings/${H('b')}`), undefined);
    const ev = await events(A);
    assert.ok(ev.some((e) => e.action === 'attempt_new_device' && e.hashPrefix === H('b').slice(0, 12)));
    const news = await db.collection('admin_news').where('targetUserId', '==', A).get();
    assert.ok(news.docs.some((d) => d.data().source === 'device_security' && d.data().i18n.ru), 'urinish haqida xabar (3 til)');
  });

  await check('K2 autoApprove=true + qurilma boshqa raqamga bog\'langan → device_bound_other_phone, qayta bog\'lanmaydi', async () => {
    const A = '998911000002';
    const B = '998911000003';
    await seedBound(A, H('c'));
    const r = await check_({ phone: B, deviceFingerprintHash: H('c'), fingerprint: FP() });
    assert.strictEqual(r.status, 'device_bound_other_phone');
    assert.strictEqual(r.customToken, undefined);
    assert.strictEqual((await get(`device_bindings/${H('c')}`)).phone, A);
  });

  await check('K3 yangi raqam + yangi qurilma → birinchi bog\'lash + token, audit first_bind', async () => {
    const N = '998911000004';
    const r = await check_({ phone: N, deviceFingerprintHash: H('d'), fingerprint: FP() });
    assert.strictEqual(r.status, 'trusted_device');
    assert.ok(r.customToken);
    assert.strictEqual((await get(`device_aliases/${N}`)).deviceFingerprintHash, H('d'));
    assert.ok((await events(N)).some((e) => e.action === 'first_bind' && e.method === 'fingerprint_first_bind'));
  });

  await check('K4 hisob bor (users), alias yo\'q → admin ko\'rigi kerak, token YO\'Q, bog\'lanmaydi', async () => {
    const U = '998911000005';
    await db.doc(`users/${U}`).set({ role: 'user', name: 'Old' });
    const r = await check_({ phone: U, deviceFingerprintHash: H('e'), fingerprint: FP() });
    assert.strictEqual(r.status, 'phone_bound_other_device');
    assert.strictEqual(r.reason, 'account_unbound');
    assert.strictEqual(r.selfServeAvailable, false);
    assert.strictEqual(r.adminReviewAvailable, true);
    assert.strictEqual(r.customToken, undefined);
    assert.strictEqual(await get(`device_aliases/${U}`), undefined);
  });

  await check('K4b faqat Auth foydalanuvchisi bor (users yo\'q) → ham admin ko\'rigi', async () => {
    const U = '998911000006';
    authUsers.set(`+${U}`, { uid: `uid_${U}`, phoneNumber: `+${U}`, customClaims: {} });
    const r = await check_({ phone: U, deviceFingerprintHash: H('f'), fingerprint: FP() });
    assert.strictEqual(r.reason, 'account_unbound');
    assert.strictEqual(r.customToken, undefined);
  });

  await check('K5 bir xil o\'rnatma (OS yangilanishi) → token; admin raqamida — YO\'Q', async () => {
    const A = '998911000007';
    await seedBound(A, H('1'), FP({ firebaseInstallationId: 'fid_drift_00007', androidId: 'andr_drift_07' }));
    const r = await check_({ phone: A, deviceFingerprintHash: H('2'), fingerprint: FP({ firebaseInstallationId: 'fid_drift_00007', androidId: 'andr_drift_07', fingerprint: 'os-2' }) });
    assert.strictEqual(r.status, 'trusted_device');
    assert.ok(r.customToken);
    assert.strictEqual((await get(`device_aliases/${A}`)).deviceFingerprintHash, H('2'));
    assert.ok((await events(A)).some((e) => e.action === 'same_install_drift'));

    const P = '998911000008';
    await seedBound(P, H('3'), FP({ firebaseInstallationId: 'fid_drift_00008', androidId: 'andr_drift_08' }), 'admin');
    const r2 = await check_({ phone: P, deviceFingerprintHash: H('4'), fingerprint: FP({ firebaseInstallationId: 'fid_drift_00008', androidId: 'andr_drift_08', fingerprint: 'os-2' }) });
    assert.strictEqual(r2.status, 'phone_bound_other_device');
    assert.strictEqual(r2.customToken, undefined);
  });

  // ── Rate limit ─────────────────────────────────────────────────────────
  await check('K6 rate limit: bir raqamga 5 urinish/soat, 6-chi DEVICE_BINDING_RATE_LIMITED (3 til); ishonchli qurilma cheklanmaydi', async () => {
    const A = '998911000009';
    await seedBound(A, H('5'));
    const hashes = ['6', '7', '8', '9', '0'].map(H);
    for (const h of hashes) {
      const r = await check_({ phone: A, deviceFingerprintHash: h, fingerprint: FP({ firebaseInstallationId: `fid_x_${h.slice(0, 6)}` }) });
      assert.strictEqual(r.status, 'phone_bound_other_device');
    }
    await assert.rejects(check_({ phone: A, deviceFingerprintHash: H('ab'), fingerprint: FP() }), (e) => {
      expectCode('resource-exhausted', 'DEVICE_BINDING_RATE_LIMITED')(e);
      assert.ok(e.details.retryAfterMs > 0);
      for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l]);
      return true;
    });
    const ok = await check_({ phone: A, deviceFingerprintHash: H('5'), fingerprint: FP() });
    assert.strictEqual(ok.status, 'trusted_device');
  });

  await check('K6b rate limit: bitta qurilmadan 5 xil raqam, 6-chi rad (qurilma kaliti)', async () => {
    const dev = H('cd');
    for (let i = 0; i < 5; i += 1) {
      const p = `99892200000${i}`;
      await db.doc(`users/${p}`).set({ role: 'user' });
      await check_({ phone: p, deviceFingerprintHash: dev, fingerprint: FP() });
    }
    await assert.rejects(check_({ phone: '998922000009', deviceFingerprintHash: dev, fingerprint: FP() }),
      expectCode('resource-exhausted', 'DEVICE_BINDING_RATE_LIMITED'));
  });

  // ── Peer «Бу сизми?» — Ҳа ──────────────────────────────────────────────
  const A = '998933000001';
  const OLD = H('e1');
  const NEW = H('e2');
  const OLD_FP = FP({ firebaseInstallationId: 'fid_peer_old_01', androidId: 'andr_peer_01' });
  await seedBound(A, OLD, OLD_FP);
  let reqId = '';

  await check('K7 peer: so\'rov → bog\'langan qurilma ro\'yxatida (qurilma, platforma) → Ҳа → ko\'chdi, 24 s cheklov, audit', async () => {
    const r = await fns.requestDeviceTransfer.run({ phone: A, deviceFingerprintHash: NEW, fingerprint: FP({ firebaseInstallationId: 'fid_peer_new_01', model: 'Redmi 12', brand: 'Xiaomi' }) }, anon());
    assert.strictEqual(r.status, 'pending');
    reqId = r.requestId;
    const news = await db.collection('admin_news').where('targetUserId', '==', A).where('source', '==', 'device_transfer').get();
    assert.ok(news.docs.some((d) => d.data().requestId === reqId && d.data().i18n.uz_Latn), '«Бу сизми?» xabari (3 til, requestId)');

    const list = await fns.listMyPendingDeviceTransfers.run({ deviceFingerprintHash: OLD }, ctxOf(A));
    const item = list.items.find((x) => x.requestId === reqId);
    assert.ok(item);
    assert.strictEqual(item.newDeviceLabel, 'Xiaomi Redmi 12');
    assert.strictEqual(item.platform, 'android');

    const wrong = await fns.listMyPendingDeviceTransfers.run({ deviceFingerprintHash: H('99') }, ctxOf(A));
    assert.strictEqual(wrong.items.length, 0, 'bog\'lanmagan qurilma ro\'yxatni ko\'rmaydi');
    await assert.rejects(fns.respondDeviceTransfer.run({ requestId: reqId, approve: true, deviceFingerprintHash: H('99') }, ctxOf(A)),
      expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    await assert.rejects(fns.respondDeviceTransfer.run({ requestId: reqId, approve: true, deviceFingerprintHash: OLD }, ctxOf('998933000099')),
      expectCode('permission-denied'));

    // Yangi qurilma tasdiqgacha token ololmaydi.
    await assert.rejects(fns.createPhoneSession.run({ phone: A, deviceFingerprintHash: NEW }, anon()), expectCode('failed-precondition'));

    const ok = await fns.respondDeviceTransfer.run({ requestId: reqId, approve: true, deviceFingerprintHash: OLD }, ctxOf(A));
    assert.strictEqual(ok.status, 'approved');
    assert.ok(ok.limitedUntilMs > Date.now() + 23 * 3600 * 1000);
    assert.strictEqual((await get(`device_aliases/${A}`)).deviceFingerprintHash, NEW);
    assert.strictEqual((await get(`device_bindings/${NEW}`)).verifiedMethod, 'peer_device_transfer');
    assert.strictEqual((await get(`device_bindings/${OLD}`)).phone, '');
    assert.strictEqual((await get(`users/${A}`)).security.deviceTrustMode, 'limited');
    const st = await fns.getDeviceTransferStatus.run({ phone: A, deviceFingerprintHash: NEW, requestId: reqId }, anon());
    assert.strictEqual(st.status, 'approved');
    const s = await fns.createPhoneSession.run({ phone: A, deviceFingerprintHash: NEW }, anon());
    assert.ok(s.customToken);
    const ev = await events(A);
    assert.ok(ev.some((e) => e.action === 'peer_requested'));
    assert.ok(ev.some((e) => e.action === 'peer_approved' && e.method === 'peer_device_transfer' && e.prevHashPrefix === OLD.slice(0, 12)));
  });

  await check('K7b qayta Ҳа (retry) — ikkinchi marta bog\'lamaydi (idempotent)', async () => {
    const before = (await events(A)).length;
    const again = await fns.respondDeviceTransfer.run({ requestId: reqId, approve: true, deviceFingerprintHash: NEW }, ctxOf(A));
    assert.strictEqual(again.status, 'approved');
    assert.strictEqual((await events(A)).length, before);
  });

  // ── Peer — Йўқ ─────────────────────────────────────────────────────────
  const BAD = H('e3');
  await check('K8 Йўқ → 24 s blok, sessiyalar bekor, admin xabari, audit; o\'sha qurilma kira olmaydi; bog\'langan qurilma jim qayta kiradi', async () => {
    const r = await fns.requestDeviceTransfer.run({ phone: A, deviceFingerprintHash: BAD, fingerprint: FP({ firebaseInstallationId: 'fid_bad_000001' }) }, anon());
    revoked.length = 0;
    const no = await fns.respondDeviceTransfer.run({ requestId: r.requestId, approve: false, deviceFingerprintHash: NEW }, ctxOf(A));
    assert.strictEqual(no.status, 'rejected');
    assert.strictEqual(no.sessionsRevoked, true);
    assert.ok(no.deniedUntilMs > Date.now() + 23 * 3600 * 1000);
    assert.deepStrictEqual(revoked, [`uid_${A}`]);
    assert.ok(await get(`device_binding_denials/${A}__${BAD}`));
    const adminNews = await db.collection('admin_news').where('targetUserId', '==', ADMIN).where('source', '==', 'device_security_admin').get();
    assert.ok(adminNews.size >= 1, 'adminlarga xabar');
    assert.ok((await events(A)).some((e) => e.action === 'peer_rejected' && e.revoked === true));

    const blocked = await check_({ phone: A, deviceFingerprintHash: BAD, fingerprint: FP() });
    assert.strictEqual(blocked.status, 'blocked');
    assert.strictEqual(blocked.code, 'DEVICE_DENIED_24H');
    assert.strictEqual(blocked.customToken, undefined);
    await assert.rejects(fns.requestDeviceTransfer.run({ phone: A, deviceFingerprintHash: BAD, fingerprint: FP() }, anon()),
      expectCode('failed-precondition', 'DEVICE_DENIED_24H'));
    await assert.rejects(fns.requestDeviceAdminReview.run({ phone: A, deviceFingerprintHash: BAD, fingerprint: FP() }, anon()),
      expectCode('failed-precondition', 'DEVICE_DENIED_24H'));

    // Bog'langan qurilma (NEW) token bekor qilingach o'z bog'lanishi bilan jim qayta kiradi.
    const relogin = await check_({ phone: A, deviceFingerprintHash: NEW, fingerprint: FP() });
    assert.strictEqual(relogin.status, 'trusted_device');
    assert.ok(relogin.customToken);
  });

  await check('K9 siljigan hash\'li bog\'langan qurilma (yangi klient, fingerprint bilan) ko\'radi va javob beradi; eski klient (faqat hash) — yo\'q', async () => {
    const P = '998933000002';
    const P_OLD = H('f1');
    const P_FP = FP({ firebaseInstallationId: 'fid_p_drift_002', androidId: 'andr_p_02' });
    await seedBound(P, P_OLD, P_FP);
    const r = await fns.requestDeviceTransfer.run({ phone: P, deviceFingerprintHash: H('f2'), fingerprint: FP({ firebaseInstallationId: 'fid_p_new_0002' }) }, anon());
    const drifted = H('f3');
    const oldClient = await fns.listMyPendingDeviceTransfers.run({ deviceFingerprintHash: drifted }, ctxOf(P));
    assert.strictEqual(oldClient.items.length, 0);
    const newClient = await fns.listMyPendingDeviceTransfers.run({ deviceFingerprintHash: drifted, fingerprint: { ...P_FP, fingerprint: 'os-9' } }, ctxOf(P));
    assert.strictEqual(newClient.items.length, 1);
    const no = await fns.respondDeviceTransfer.run({ requestId: r.requestId, approve: false, deviceFingerprintHash: drifted, fingerprint: { ...P_FP, fingerprint: 'os-9' } }, ctxOf(P));
    assert.strictEqual(no.status, 'rejected');
    // alias joriy (siljigan) hash'ga tuzatildi → jim qayta kirish ishonchli
    assert.strictEqual((await get(`device_aliases/${P}`)).deviceFingerprintHash, drifted);
    const relogin = await check_({ phone: P, deviceFingerprintHash: drifted, fingerprint: P_FP });
    assert.strictEqual(relogin.status, 'trusted_device');
  });

  // ── Admin ko'rigi («Эски телефоним йўқ») ───────────────────────────────
  await check('K10 admin ko\'rigi: so\'rov (idempotent) → ro\'yxat (admin) → tasdiq → bog\'landi, 24 s cheklov, admin_audit', async () => {
    const U = '998944000001';
    await db.doc(`users/${U}`).set({ role: 'user', name: 'Lost Phone' });
    const dev = H('a1');
    const r = await fns.requestDeviceAdminReview.run({ phone: U, deviceFingerprintHash: dev, fingerprint: FP({ firebaseInstallationId: 'fid_rev_000001' }), note: 'telefonim o\'g\'irlandi' }, anon());
    assert.strictEqual(r.status, 'pending');
    assert.strictEqual(r.channel, 'admin_review');
    const again = await fns.requestDeviceAdminReview.run({ phone: U, deviceFingerprintHash: dev, fingerprint: FP() }, anon());
    assert.strictEqual(again.requestId, r.requestId);
    await assert.rejects(fns.adminListDeviceApprovals.run({}, ctxOf(U)), expectCode('permission-denied'));
    await assert.rejects(fns.adminListDeviceApprovals.run({}, ctxOf(FIN)), expectCode('permission-denied'));
    const list = await fns.adminListDeviceApprovals.run({}, ctxOf(ADMIN));
    const it = list.items.find((x) => x.requestId === r.requestId);
    assert.ok(it);
    assert.strictEqual(it.canDecide, true);
    assert.strictEqual(it.note, 'telefonim o\'g\'irlandi');
    assert.strictEqual(it.name, 'Lost Phone');
    const ok = await fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true, identityCheck: 'pasport ko\'rildi' }, ctxOf(ADMIN));
    assert.strictEqual(ok.status, 'approved');
    assert.strictEqual((await get(`device_aliases/${U}`)).deviceFingerprintHash, dev);
    assert.strictEqual((await get(`users/${U}`)).security.deviceTrustMode, 'limited');
    const audit = await db.collection('admin_audit').where('requestId', '==', r.requestId).get();
    assert.strictEqual(audit.docs[0].data().kind, 'device_approval_approved');
    assert.strictEqual(audit.docs[0].data().identityCheck, 'pasport ko\'rildi');
    assert.ok((await events(U)).some((e) => e.action === 'admin_approved' && e.actor === `admin:${ADMIN}`));
    const st = await fns.getDeviceTransferStatus.run({ phone: U, deviceFingerprintHash: dev, requestId: r.requestId }, anon());
    assert.strictEqual(st.status, 'approved');
    await assert.rejects(fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true }, ctxOf(ADMIN)),
      expectCode('failed-precondition', 'REQUEST_NOT_PENDING'));
  });

  await check('K11 admin raqami: admin tasdiqlay olmaydi (ADMIN_TARGET_NEEDS_SUPERADMIN), superadmin — ha; eski admin tugmasi ham', async () => {
    const P = '998944000002';
    await seedBound(P, H('b1'), FP(), 'dispatcher');
    const r = await fns.requestDeviceAdminReview.run({ phone: P, deviceFingerprintHash: H('b2'), fingerprint: FP({ firebaseInstallationId: 'fid_priv_00002' }) }, anon());
    const list = await fns.adminListDeviceApprovals.run({}, ctxOf(ADMIN));
    const it = list.items.find((x) => x.requestId === r.requestId);
    assert.strictEqual(it.privileged, true);
    assert.strictEqual(it.canDecide, false);
    await assert.rejects(fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true }, ctxOf(ADMIN)),
      expectCode('permission-denied', 'ADMIN_TARGET_NEEDS_SUPERADMIN'));
    await assert.rejects(fns.adminManualApproveDeviceBinding.run({ phone: P, deviceFingerprintHash: H('b3') }, ctxOf(ADMIN)),
      expectCode('permission-denied', 'ADMIN_TARGET_NEEDS_SUPERADMIN'));
    const ok = await fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true }, ctxOf(SUPER));
    assert.strictEqual(ok.status, 'approved');
  });

  await check('K12 admin rad etadi → rejected + audit, bog\'lanmaydi', async () => {
    const U = '998944000003';
    await db.doc(`users/${U}`).set({ role: 'user' });
    const r = await fns.requestDeviceAdminReview.run({ phone: U, deviceFingerprintHash: H('c1'), fingerprint: FP() }, anon());
    const no = await fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: false, note: 'shubhali' }, ctxOf(ADMIN));
    assert.strictEqual(no.status, 'rejected');
    assert.strictEqual(await get(`device_aliases/${U}`), undefined);
    const audit = await db.collection('admin_audit').where('requestId', '==', r.requestId).get();
    assert.strictEqual(audit.docs[0].data().kind, 'device_approval_rejected');
  });

  await check('K12b bog\'langan qurilma admin ko\'rigi so\'rovini ham ko\'radi va «Йўқ» deya oladi', async () => {
    const P = '998944000004';
    await seedBound(P, H('d1'));
    const r = await fns.requestDeviceAdminReview.run({ phone: P, deviceFingerprintHash: H('d2'), fingerprint: FP({ firebaseInstallationId: 'fid_rv_000004' }) }, anon());
    const list = await fns.listMyPendingDeviceTransfers.run({ deviceFingerprintHash: H('d1') }, ctxOf(P));
    assert.ok(list.items.some((x) => x.requestId === r.requestId && x.channel === 'admin_review'));
    const no = await fns.respondDeviceTransfer.run({ requestId: r.requestId, approve: false, deviceFingerprintHash: H('d1') }, ctxOf(P));
    assert.strictEqual(no.status, 'rejected');
    // Egasi rad etgan qurilmani admin ham tasdiqlay olmaydi (24 s), rad etish — hal qilingan.
    await assert.rejects(fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true }, ctxOf(ADMIN)),
      expectCode('failed-precondition', 'DEVICE_DENIED_24H'));
    await assert.rejects(fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: false }, ctxOf(ADMIN)),
      expectCode('failed-precondition', 'REQUEST_NOT_PENDING'));
  });

  await check('K16 eski APK (tugma yo\'q): muddati o\'tgan peer so\'rovni admin raqam bo\'yicha topib tasdiqlaydi; 72 soatdan eski — yo\'q', async () => {
    const P = '998944000005';
    await seedBound(P, H('e5'));
    const r = await fns.requestDeviceTransfer.run({ phone: P, deviceFingerprintHash: H('e6'), fingerprint: FP({ firebaseInstallationId: 'fid_oldapk_0005' }) }, anon());
    await db.doc(`device_transfer_requests/${r.requestId}`).set({
      status: 'expired', expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
    }, { merge: true });
    const pendingOnly = await fns.adminListDeviceApprovals.run({}, ctxOf(ADMIN));
    assert.ok(!pendingOnly.items.some((x) => x.requestId === r.requestId), 'umumiy navbatda peer so\'rov yo\'q');
    const found = await fns.adminListDeviceApprovals.run({ phone: P }, ctxOf(ADMIN));
    const it = found.items.find((x) => x.requestId === r.requestId);
    assert.ok(it);
    assert.strictEqual(it.channel, 'old_device_push');
    assert.strictEqual(it.decidable, true);
    const ok = await fns.adminDecideDeviceApproval.run({ requestId: r.requestId, approve: true, identityCheck: 'qo\'ng\'iroq' }, ctxOf(ADMIN));
    assert.strictEqual(ok.status, 'approved');
    const relogin = await check_({ phone: P, deviceFingerprintHash: H('e6'), fingerprint: FP() });
    assert.strictEqual(relogin.status, 'trusted_device');

    const old = await fns.requestDeviceTransfer.run({ phone: P, deviceFingerprintHash: H('e7'), fingerprint: FP({ firebaseInstallationId: 'fid_oldapk_0007' }) }, anon());
    await db.doc(`device_transfer_requests/${old.requestId}`).set({
      status: 'expired', createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 73 * 3600 * 1000),
    }, { merge: true });
    await assert.rejects(fns.adminDecideDeviceApproval.run({ requestId: old.requestId, approve: true }, ctxOf(ADMIN)),
      expectCode('failed-precondition', 'REQUEST_NOT_PENDING'));
  });

  // ── 24 s pul chiqimi bloki ─────────────────────────────────────────────
  await check('K13 cheklangan hisob: requestPayout / confirmPayout / requestWalletWithdraw / adminReviewWalletWithdraw / walletToCash — device_trust_limited', async () => {
    const L = '998955000001';
    const until = admin.firestore.Timestamp.fromMillis(Date.now() + 3600 * 1000);
    await db.doc(`users/${L}`).set({
      role: 'user', name: 'Limited User', birthDate: '1990-01-01', payoutKycVerified: true, bonusBalance: 500000,
      security: { deviceTrustMode: 'limited', deviceTrustUntil: until },
    });
    const limited = (e) => {
      assert.strictEqual(e.code, 'failed-precondition', e.message);
      assert.strictEqual(e.details.code, 'device_trust_limited');
      return true;
    };
    // requestPayout W-2 (fix/dup-audit-p1) bilan ENDPOINT_RETIRED — baribir rad (pul chiqmaydi).
    await assert.rejects(fns.requestPayout.run({ userPhone: L, amount: 10000, idempotencyKey: 'k13_payout' }, ctxOf(L)),
      (e) => e.details && e.details.code === 'ENDPOINT_RETIRED');
    await db.doc('payout_requests/k13_pr').set({ userPhone: L, amount: 10000, status: 'pending' });
    await assert.rejects(fns.confirmPayout.run({ requestId: 'k13_pr' }, ctxOf(FIN)), limited);
    assert.strictEqual((await get('payout_requests/k13_pr')).status, 'pending');
    await assert.rejects(fns.requestWalletWithdraw.run({ amount: 10000, payoutCardNumber: '8600123412341234', payoutCardHolder: 'TEST' }, ctxOf(L)), limited);
    await db.doc('wallet_withdraw_requests/k13_w').set({ uid: L, amount: 10000, status: 'pending', source: 'telegram' });
    await assert.rejects(fns.adminReviewWalletWithdraw.run({ requestId: 'k13_w', accept: true }, ctxOf(SUPER)), limited);
    assert.strictEqual((await get('wallet_withdraw_requests/k13_w')).status, 'pending');
    await assert.rejects(fns.walletToCash.run({ phone: L, amount: 10000, opId: 'k13_cash_1' }, ctxOf(FIN)), limited);
    assert.strictEqual((await get(`users/${L}`)).bonusBalance, 500000, 'balans o\'zgarmadi');
  });

  await check('K13b cheklov muddati o\'tgach — walletToCash ishlaydi (regression)', async () => {
    const L = '998955000002';
    await db.doc(`users/${L}`).set({
      role: 'user', name: 'Free', bonusBalance: 50000,
      security: { deviceTrustMode: 'limited', deviceTrustUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) },
    });
    await db.doc(`ledger_accounts/passenger_credit:${L}`).set({ balance: 50000 }, { merge: true });
    const r = await fns.walletToCash.run({ phone: L, amount: 1000, opId: 'k13b_cash_1' }, ctxOf(FIN)).catch((e) => e);
    if (r instanceof Error) assert.notStrictEqual((r.details || {}).code, 'device_trust_limited', r.message);
  });

  // ── Yopilgan endpoint'lar, sozlama auditi ──────────────────────────────
  await check('K14 pending-code endpoint\'lari ENDPOINT_RETIRED; trigger hech narsa yozmaydi', async () => {
    for (const n of ['requestPendingCode', 'getPendingCodeStatus', 'verifyPendingCodeAndRegister']) {
      await assert.rejects(fns[n].run({ phone: '998966000001', deviceFingerprintHash: H('aa'), code: '123456' }, anon()),
        expectCode('unimplemented', 'ENDPOINT_RETIRED'));
    }
    await db.doc('pending_codes/998966000001').set({ status: 'pending' });
    const snap = await db.doc('pending_codes/998966000001').get();
    const out = await fns.autoApprovePendingCode.run(snap, { params: { phone: '998966000001' } });
    assert.strictEqual(out, null);
    const after = await get('pending_codes/998966000001');
    assert.strictEqual(after.status, 'pending');
    assert.strictEqual(after.code, undefined);
  });

  await check('K15 adminSetDeviceBindingAutoApprove — audit + serverIgnored; sozlama baribir e\'tiborsiz', async () => {
    const r = await fns.adminSetDeviceBindingAutoApprove.run({ enabled: true }, ctxOf(ADMIN));
    assert.strictEqual(r.serverIgnored, true);
    const audit = await db.collection('admin_audit').where('kind', '==', 'device_auto_approve_setting').get();
    assert.ok(audit.size >= 1);
    const X = '998977000001';
    await seedBound(X, H('7a'));
    const att = await check_({ phone: X, deviceFingerprintHash: H('7b'), fingerprint: FP({ firebaseInstallationId: 'fid_k15_000001' }) });
    assert.strictEqual(att.customToken, undefined);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
