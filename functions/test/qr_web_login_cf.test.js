/**
 * Kompyuterda QR orqali kirish (ega 2026-11-28) — Cloud Functions, Firestore emulator + soxta Auth.
 *
 *   firebase emulators:exec --only firestore --project demo-qrweb "node test/qr_web_login_cf.test.js"
 *
 * Tekshiradi: bosqich (OFF/internal/public), faqat bog'langan telefon tasdiqlaydi, begona telefon,
 * replay, muddat, bir vaqtda ikki tasdiq / ikki consume (bitta g'olib), noto'g'ri sir, telefon
 * bog'lanishi o'zgarmaydi, 24 s pul chiqimi bloki, renew, «Чиқиш» (telefon / web o'zi), limitlar, audit.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-qrweb';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const { QR_WEB } = require('../qr_web_login');
const admin = require('firebase-admin');

const db = admin.firestore();

const authUsers = new Map();
const revoked = [];
let failTokens = false;
Object.assign(admin.auth(), {
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
  async createCustomToken(uid) {
    if (failTokens) throw new Error('boom');
    return `token_for_${uid}`;
  },
  async revokeRefreshTokens(uid) { revoked.push(uid); },
});

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
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
let ipSeq = 0;
const web = (ip) => ({ rawRequest: { headers: { 'user-agent': UA, 'x-forwarded-for': ip || `10.1.0.${(ipSeq += 1) % 250}` }, ip: '127.0.0.1' } });
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } }, rawRequest: { headers: {} } });
const FP = (over = {}) => ({
  platform: 'android', androidId: 'andr0id0001', firebaseInstallationId: 'fid_install_0001',
  model: 'SM-A515F', brand: 'samsung', ...over,
});
const events = async (phone) => (await db.collection('device_binding_events').where('phone', '==', phone).get())
  .docs.map((d) => d.data());
const expectCode = (httpsCode, code) => (e) => {
  assert.strictEqual(e.code, httpsCode, `${e.code} != ${httpsCode} (${e.message})`);
  if (code) assert.strictEqual((e.details || {}).code, code, `${(e.details || {}).code} != ${code}`);
  return true;
};

async function seedBound(phone, hash, role = 'user') {
  await db.doc(`users/${phone}`).set({ role, name: 'Test', bonusBalance: 100000 });
  await db.doc(`device_bindings/${hash}`).set({ phone, deviceFingerprintHash: hash, fingerprint: FP() });
  await db.doc(`device_aliases/${phone}`).set({ phone, deviceFingerprintHash: hash });
  authUsers.set(`+${phone}`, { uid: `uid_${phone}`, phoneNumber: `+${phone}`, customClaims: {} });
  BOUND[phone] = hash;
}
const setStage = (stage, testerIds = []) => db.doc('server_config/qr_web_login').set({ stage, testerIds });
const start = (ip) => fns.qrLoginStart.run({}, web(ip));
const WEB_FP = { platform: 'web', device: 'chrome', product: 'Win32' };
// Bog'langan qurilma FP() bilan; boshqa hash — web fingerprint (aks holda «bir xil o'rnatma» deb taniladi).
const fpFor = (phone, hash) => (hash === BOUND[phone] ? FP() : WEB_FP);
const BOUND = {};
const peek = (sid, phone, hash) => fns.qrLoginPeek.run({ sid, deviceFingerprintHash: hash, fingerprint: fpFor(phone, hash) }, ctxOf(phone));
const approve = (sid, phone, hash, yes = true) => fns.qrLoginApprove.run({ sid, approve: yes, deviceFingerprintHash: hash, fingerprint: fpFor(phone, hash) }, ctxOf(phone));
const consume = (s, ip) => fns.qrLoginConsume.run({ sid: s.sid, secret: s.secret }, web(ip));
async function approvedSession(phone, hash) {
  const s = await start();
  await peek(s.sid, phone, hash);
  await approve(s.sid, phone, hash);
  return s;
}

async function main() {
  await clearEmulator();
  const A = '998941000001';
  const HA = H('a1');
  const B = '998941000002';
  const HB = H('b2');
  const ADM = '998941000009';
  const HADM = H('ad');
  await seedBound(A, HA);
  await seedBound(B, HB);
  await seedBound(ADM, HADM, 'admin');

  await check('Q1 bosqich hujjati yo\'q = OFF: probe enabled=false, start QR_LOGIN_DISABLED, ro\'yxat ishlaydi', async () => {
    assert.deepStrictEqual(await fns.qrLoginStart.run({ probe: true }, web()), { enabled: false });
    await assert.rejects(start(), expectCode('failed-precondition', 'QR_LOGIN_DISABLED'));
    const l = await fns.qrWebSessionsList.run({ deviceFingerprintHash: HA }, ctxOf(A));
    assert.strictEqual(l.enabled, false);
    assert.strictEqual(l.canManage, true);
    assert.deepStrictEqual(l.items, []);
  });

  await check('Q2 internal: start → kuzatuv hujjatida faqat status/expiresAt; sessiyada sir EMAS, hash', async () => {
    await setStage('internal', [A]);
    const s = await start();
    assert.ok(/^[a-f0-9]{32}$/.test(s.sid) && /^[a-f0-9]{64}$/.test(s.secret) && /^[a-f0-9]{64}$/.test(s.watchId));
    assert.strictEqual(s.qrPayload, `AVAQR1:${s.sid}`);
    assert.ok(!s.qrPayload.includes(s.secret) && !s.qrPayload.includes(s.watchId));
    const w = await get(`qr_login_watch/${s.watchId}`);
    assert.deepStrictEqual(Object.keys(w).sort(), ['expireAt', 'expiresAt', 'status']);
    assert.ok(w.expireAt.toMillis() > w.expiresAt.toMillis(), 'TTL maydoni muddatdan keyin');
    assert.strictEqual(w.status, 'pending');
    const x = await get(`qr_login_sessions/${s.sid}`);
    assert.ok(x.secretHash && x.secretHash !== s.secret);
    assert.ok(!JSON.stringify(x).includes(s.secret));
    assert.strictEqual(x.browserLabel, 'Chrome · Windows');
    assert.ok(x.expiresAt.toMillis() - Date.now() <= 120000 && x.expiresAt.toMillis() - Date.now() > 100000);
  });

  await check('Q3 internal: tester bo\'lmagan raqam skanerlay olmaydi', async () => {
    const s = await start();
    await assert.rejects(peek(s.sid, B, HB), expectCode('failed-precondition', 'QR_LOGIN_DISABLED'));
    assert.strictEqual((await get(`qr_login_sessions/${s.sid}`)).status, 'pending');
  });

  await setStage('public');

  await check('Q4 bog\'lanmagan qurilma (masalan web sessiya) tasdiqlay olmaydi — DEVICE_NOT_BOUND', async () => {
    const s = await start();
    await assert.rejects(peek(s.sid, A, H('99')), expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    await assert.rejects(approve(s.sid, A, H('99')), expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    await assert.rejects(fns.qrLoginApprove.run({ sid: s.sid, approve: true }, ctxOf(A)), expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    await assert.rejects(fns.qrLoginPeek.run({ sid: s.sid }, {}), expectCode('unauthenticated'));
    assert.strictEqual((await get(`qr_login_sessions/${s.sid}`)).status, 'pending');
  });

  let S1;
  await check('Q5 skaner: scanned, kuzatuv scanned, brauzer ma\'lumoti, audit qr_scanned; QR matni bilan ham', async () => {
    S1 = await start();
    const p = await fns.qrLoginPeek.run({ qr: S1.qrPayload, deviceFingerprintHash: HA, fingerprint: FP() }, ctxOf(A));
    assert.strictEqual(p.status, 'scanned');
    assert.strictEqual(p.browserLabel, 'Chrome · Windows');
    assert.strictEqual(p.outflowBlockHours, 24);
    assert.ok(p.expiresAtMs > Date.now());
    assert.strictEqual((await get(`qr_login_watch/${S1.watchId}`)).status, 'scanned');
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).scannedBy, A);
    assert.ok((await events(A)).some((e) => e.action === 'qr_scanned' && e.requestId === S1.sid));
    const again = await peek(S1.sid, A, HA); // takroriy skaner — o'sha egasi
    assert.strictEqual(again.status, 'scanned');
  });

  await check('Q6 begona telefon: skaner va tasdiq — QR_SESSION_OTHER_USER', async () => {
    await assert.rejects(peek(S1.sid, B, HB), expectCode('permission-denied', 'QR_SESSION_OTHER_USER'));
    await assert.rejects(approve(S1.sid, B, HB), expectCode('permission-denied', 'QR_SESSION_OTHER_USER'));
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).status, 'scanned');
  });

  await check('Q7 tasdiqdan oldin consume — token YO\'Q', async () => {
    await assert.rejects(consume(S1), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).status, 'scanned');
  });

  await check('Q8 bir vaqtda ikki tasdiq — bitta g\'olib', async () => {
    const r = await Promise.allSettled([approve(S1.sid, A, HA), approve(S1.sid, A, HA)]);
    const ok = r.filter((x) => x.status === 'fulfilled');
    const bad = r.filter((x) => x.status === 'rejected');
    assert.strictEqual(ok.length, 1, JSON.stringify(r.map((x) => x.status)));
    assert.strictEqual(bad[0].reason.details.code, 'QR_SESSION_NOT_PENDING');
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).status, 'approved');
    assert.strictEqual((await get(`qr_login_watch/${S1.watchId}`)).status, 'approved');
    assert.strictEqual((await events(A)).filter((e) => e.action === 'qr_approved' && e.requestId === S1.sid).length, 1);
  });

  await check('Q9 noto\'g\'ri sir — QR_SESSION_INVALID, audit, holat o\'zgarmaydi', async () => {
    await assert.rejects(fns.qrLoginConsume.run({ sid: S1.sid, secret: 'f'.repeat(64) }, web()),
      expectCode('permission-denied', 'QR_SESSION_INVALID'));
    await assert.rejects(fns.qrLoginConsume.run({ sid: S1.sid, secret: 'short' }, web()),
      expectCode('permission-denied', 'QR_SESSION_INVALID'));
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).status, 'approved');
    const bad = await db.collection('device_binding_events').where('action', '==', 'qr_consume_bad_secret').get();
    assert.ok(bad.size >= 1);
  });

  let WS1;
  await check('Q10 consume: token, web sessiya active, telefon bog\'lanishi O\'ZGARMAYDI, 24 s blok, xabar, audit', async () => {
    WS1 = await consume(S1);
    assert.strictEqual(WS1.customToken, `token_for_uid_${A}`);
    assert.strictEqual(WS1.phone, A);
    assert.ok(/^[a-f0-9]{32}$/.test(WS1.webSessionId) && /^[a-f0-9]{64}$/.test(WS1.renewSecret));
    const ws = await get(`qr_web_sessions/${WS1.webSessionId}`);
    assert.strictEqual(ws.status, 'active');
    assert.strictEqual(ws.phone, A);
    assert.ok(!JSON.stringify(ws).includes(WS1.renewSecret));
    assert.strictEqual((await get(`qr_login_sessions/${S1.sid}`)).status, 'consumed');
    assert.strictEqual((await get(`qr_login_watch/${S1.watchId}`)).status, 'consumed');
    assert.strictEqual((await get(`device_aliases/${A}`)).deviceFingerprintHash, HA, 'telefon bog\'lanishi joyida');
    assert.strictEqual((await get(`device_bindings/${HA}`)).phone, A);
    const u = await get(`users/${A}`);
    assert.strictEqual(u.security.deviceTrustMode, 'limited');
    assert.strictEqual(u.security.deviceTrustReason, 'qr_web_login');
    assert.ok(u.security.deviceTrustUntil.toMillis() > Date.now() + 23 * 3600 * 1000);
    const news = await db.collection('admin_news').where('targetUserId', '==', A).where('source', '==', 'qr_web_login').get();
    assert.ok(news.size >= 1 && news.docs[0].data().i18n.ru, 'xabar 3 tilda');
    assert.ok((await events(A)).some((e) => e.action === 'qr_consumed' && e.requestId === WS1.webSessionId));
  });

  await check('Q10b 24 s blok amalda: requestWalletWithdraw device_trust_limited', async () => {
    await db.doc(`users/${A}`).set({ birthDate: '1990-01-01', payoutKycVerified: true }, { merge: true });
    await assert.rejects(fns.requestWalletWithdraw.run({ amount: 10000, payoutCardNumber: '8600123412341234', payoutCardHolder: 'TEST' }, ctxOf(A)),
      (e) => (e.details || {}).code === 'device_trust_limited');
  });

  await check('Q11 replay: ikkinchi consume — token YO\'Q (consumed)', async () => {
    await assert.rejects(consume(S1), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
    const n = (await db.collection('qr_web_sessions').where('qrSessionId', '==', S1.sid).get()).size;
    assert.strictEqual(n, 1);
  });

  await check('Q11b bir vaqtda ikki consume — bitta token, bitta web sessiya', async () => {
    const s = await approvedSession(A, HA);
    const r = await Promise.allSettled([consume(s), consume(s)]);
    assert.strictEqual(r.filter((x) => x.status === 'fulfilled').length, 1, JSON.stringify(r.map((x) => x.status)));
    assert.strictEqual((await db.collection('qr_web_sessions').where('qrSessionId', '==', s.sid).get()).size, 1);
  });

  await check('Q12 muddat: o\'tgan QR — skaner/tasdiq rad, expired; tasdiqdan keyin oyna o\'tsa consume rad', async () => {
    const s = await start();
    await db.doc(`qr_login_sessions/${s.sid}`).set({ expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1) }, { merge: true });
    await assert.rejects(peek(s.sid, A, HA), expectCode('failed-precondition', 'QR_SESSION_INVALID'));
    assert.strictEqual((await get(`qr_login_sessions/${s.sid}`)).status, 'expired');
    assert.strictEqual((await get(`qr_login_watch/${s.watchId}`)).status, 'expired');
    await assert.rejects(approve(s.sid, A, HA), expectCode('failed-precondition', 'QR_SESSION_INVALID'));

    const s2 = await approvedSession(A, HA);
    const x2 = await get(`qr_login_sessions/${s2.sid}`);
    assert.ok(x2.expiresAt.toMillis() >= Date.now() + 55000, 'tasdiqdan keyin ≥60 s consume oynasi');
    await db.doc(`qr_login_sessions/${s2.sid}`).set({ expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1) }, { merge: true });
    await assert.rejects(consume(s2), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
  });

  await check('Q13 rad etish: rejected, kuzatuv rejected, consume rad; OFF bo\'lsa ham rad etish mumkin', async () => {
    const s = await start();
    await peek(s.sid, A, HA);
    const r = await approve(s.sid, A, HA, false);
    assert.strictEqual(r.status, 'rejected');
    assert.strictEqual((await get(`qr_login_watch/${s.watchId}`)).status, 'rejected');
    await assert.rejects(consume(s), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
    await assert.rejects(approve(s.sid, A, HA), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
    assert.ok((await events(A)).some((e) => e.action === 'qr_rejected' && e.requestId === s.sid));
  });

  await check('Q14 renew: to\'g\'ri sir → token; noto\'g\'ri → rad; ro\'yxatda ko\'rinadi (telefon/sir chiqmaydi)', async () => {
    const r = await fns.qrWebSessionRenew.run({ webSessionId: WS1.webSessionId, renewSecret: WS1.renewSecret }, web());
    assert.strictEqual(r.customToken, `token_for_uid_${A}`);
    await assert.rejects(fns.qrWebSessionRenew.run({ webSessionId: WS1.webSessionId, renewSecret: 'e'.repeat(64) }, web()),
      expectCode('permission-denied', 'QR_WEB_SESSION_INVALID'));
    const l = await fns.qrWebSessionsList.run({ deviceFingerprintHash: HA, fingerprint: FP() }, ctxOf(A));
    assert.strictEqual(l.enabled, true);
    assert.strictEqual(l.canManage, true);
    const it = l.items.find((i) => i.webSessionId === WS1.webSessionId);
    assert.ok(it && it.browserLabel === 'Chrome · Windows');
    assert.ok(!JSON.stringify(l).includes(A) && !JSON.stringify(l).includes('renewSecretHash'));
    const lw = await fns.qrWebSessionsList.run({}, ctxOf(A));
    assert.strictEqual(lw.canManage, false, 'web sessiya (bog\'lanmagan) boshqara olmaydi');
    const lb = await fns.qrWebSessionsList.run({ deviceFingerprintHash: HB }, ctxOf(B));
    assert.ok(!lb.items.some((i) => i.webSessionId === WS1.webSessionId), 'begona ro\'yxatida yo\'q');
  });

  await check('Q15 begona telefon boshqa birovning sessiyasidan chiqara olmaydi', async () => {
    await assert.rejects(fns.qrWebSessionRevoke.run({ webSessionId: WS1.webSessionId, deviceFingerprintHash: HB, fingerprint: FP() }, ctxOf(B)),
      expectCode('permission-denied'));
    await assert.rejects(fns.qrWebSessionRevoke.run({ webSessionId: WS1.webSessionId }, ctxOf(A)),
      expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    assert.strictEqual((await get(`qr_web_sessions/${WS1.webSessionId}`)).status, 'active');
  });

  await check('Q16 telefondan «Чиқиш»: revoked, refresh token\'lar bekor, renew rad, takror — revoked 0', async () => {
    const before = revoked.length;
    const r = await fns.qrWebSessionRevoke.run({ webSessionId: WS1.webSessionId, deviceFingerprintHash: HA, fingerprint: FP() }, ctxOf(A));
    assert.strictEqual(r.revoked, 1);
    assert.strictEqual(r.reauthRequired, true);
    assert.strictEqual(revoked.length, before + 1);
    assert.strictEqual(revoked[revoked.length - 1], `uid_${A}`);
    assert.strictEqual((await get(`qr_web_sessions/${WS1.webSessionId}`)).status, 'revoked');
    await assert.rejects(fns.qrWebSessionRenew.run({ webSessionId: WS1.webSessionId, renewSecret: WS1.renewSecret }, web()),
      expectCode('permission-denied', 'QR_WEB_SESSION_INVALID'));
    const again = await fns.qrWebSessionRevoke.run({ webSessionId: WS1.webSessionId, deviceFingerprintHash: HA }, ctxOf(A));
    assert.strictEqual(again.revoked, 0);
    assert.strictEqual(revoked.length, before + 1, 'takror — token qayta bekor qilinmaydi');
    assert.ok((await events(A)).some((e) => e.action === 'qr_web_revoked' && e.requestId === WS1.webSessionId));
  });

  await check('Q17 web o\'zi chiqadi (renewSecret): faqat shu sessiya, token bekor qilinmaydi', async () => {
    const s = await approvedSession(A, HA);
    const w = await consume(s);
    const before = revoked.length;
    await assert.rejects(fns.qrWebSessionRevoke.run({ webSessionId: w.webSessionId, renewSecret: 'd'.repeat(64) }, web()),
      expectCode('permission-denied', 'QR_WEB_SESSION_INVALID'));
    const r = await fns.qrWebSessionRevoke.run({ webSessionId: w.webSessionId, renewSecret: w.renewSecret }, web());
    assert.deepStrictEqual(r, { revoked: 1, reauthRequired: false });
    assert.strictEqual(revoked.length, before);
    assert.strictEqual((await get(`qr_web_sessions/${w.webSessionId}`)).status, 'revoked');
  });

  await check('Q18 «Барчасидан чиқиш» (all) + faol sessiyalar limiti (5)', async () => {
    await fns.qrWebSessionRevoke.run({ all: true, deviceFingerprintHash: HA }, ctxOf(A));
    await db.doc(`device_binding_rate/qa_p_${A}`).delete(); // 20/soat chegarasi alohida (Q21-turi) tekshiriladi
    for (let i = 0; i < 5; i += 1) await consume(await approvedSession(A, HA));
    const s = await start();
    await peek(s.sid, A, HA);
    await assert.rejects(approve(s.sid, A, HA), expectCode('failed-precondition', 'QR_WEB_SESSION_LIMIT'));
    const r = await fns.qrWebSessionRevoke.run({ all: true, deviceFingerprintHash: HA }, ctxOf(A));
    assert.strictEqual(r.revoked, 5);
    const l = await fns.qrWebSessionsList.run({ deviceFingerprintHash: HA }, ctxOf(A));
    assert.strictEqual(l.items.length, 0);
    assert.strictEqual((await approve(s.sid, A, HA)).status, 'approved');
  });

  await check('Q19 admin raqami — xuddi shu qoidalar: bog\'lanmagan qurilma rad, bog\'langan — 24 s blok ham', async () => {
    const s = await start();
    await assert.rejects(peek(s.sid, ADM, HA), expectCode('permission-denied', 'DEVICE_NOT_BOUND'));
    await peek(s.sid, ADM, HADM);
    await approve(s.sid, ADM, HADM);
    const w = await consume(s);
    assert.strictEqual(w.phone, ADM);
    assert.strictEqual((await get(`users/${ADM}`)).security.deviceTrustMode, 'limited');
  });

  await check('Q20 token yaratilmasa: web sessiya failed, xato QR_TOKEN_FAILED (token oqib chiqmaydi)', async () => {
    const s = await approvedSession(B, HB);
    failTokens = true;
    try {
      await assert.rejects(consume(s), expectCode('internal', 'QR_TOKEN_FAILED'));
    } finally { failTokens = false; }
    const ws = await db.collection('qr_web_sessions').where('qrSessionId', '==', s.sid).get();
    assert.strictEqual(ws.docs[0].data().status, 'failed');
    await assert.rejects(consume(s), expectCode('failed-precondition', 'QR_SESSION_NOT_PENDING'));
  });

  await check(`Q21 rate limit: bir IP'dan soatiga ${QR_WEB.RATE_START_PER_IP} ta QR, keyingisi QR_RATE_LIMITED (3 til)`, async () => {
    const ip = '10.9.9.9';
    for (let i = 0; i < QR_WEB.RATE_START_PER_IP; i += 1) await start(ip);
    await assert.rejects(start(ip), (e) => {
      expectCode('resource-exhausted', 'QR_RATE_LIMITED')(e);
      for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l]);
      return true;
    });
  });

  await check('Q22 OFF ga qaytarilsa: renew/start/consume yopiq, ro\'yxat va «Чиқиш» ishlaydi (kill switch)', async () => {
    const s = await approvedSession(B, HB);
    const w = await consume(s);
    await setStage('off');
    await assert.rejects(fns.qrWebSessionRenew.run({ webSessionId: w.webSessionId, renewSecret: w.renewSecret }, web()),
      expectCode('failed-precondition', 'QR_LOGIN_DISABLED'));
    await assert.rejects(start(), expectCode('failed-precondition', 'QR_LOGIN_DISABLED'));
    const l = await fns.qrWebSessionsList.run({ deviceFingerprintHash: HB }, ctxOf(B));
    assert.strictEqual(l.enabled, false);
    assert.strictEqual(l.items.length, 1);
    const r = await fns.qrWebSessionRevoke.run({ webSessionId: w.webSessionId, deviceFingerprintHash: HB }, ctxOf(B));
    assert.strictEqual(r.revoked, 1);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
