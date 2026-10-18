/**
 * Telegram hamyon boti — admin ko'rib chiqishi, webhook siri va bog'lash
 * kodi (hamyon auditi Y-9). HAQIQIY ledger bilan (Firestore Emulator).
 *
 *   firebase emulators:exec --only firestore --project demo-wallet-audit \
 *     "node functions/test/wallet_bot_review_cf.test.js"
 *
 * - finance o'z to'ldirish/yechish so'rovini o'zi tasdiqlay olmaydi;
 *   superadmin (ega) mumkin, admin_audit'ga yoziladi;
 * - parallel tasdiq + rad etish: «rad etildi, lekin pul yozildi» bo'lmaydi;
 * - webhook siri bo'sh bo'lsa so'rov qabul qilinmaydi (avval fail-open);
 * - bog'lash kodini taxmin qilish: 5 xatodan keyin qulf; bitta kod ikki
 *   Telegram'ga bog'lanmaydi.
 * Telegram API'ga tarmoq so'rovi ketmaydi (`fetch` almashtirilgan).
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-audit';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.TELEGRAM_WALLET_BOT_TOKEN = 'test-token';
const sent = [];
global.fetch = async (url, opts) => {
  sent.push({ url: String(url), body: opts && opts.body });
  return { ok: true, json: async () => ({ ok: true, result: {} }) };
};

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const USER = '998901000001';
const FIN = '998905000001';
const SUPER = '998905000009';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function reset() {
  await Promise.all(['users', 'settings', 'admin_audit', 'wallet_withdraw_requests',
    'wallet_topup_requests', 'telegram_links', 'telegram_link_codes', 'telegram_link_attempts',
    'telegram_bot_sessions', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  for (const [uid, role, bal] of [[USER, 'user', 100000], [FIN, 'finance', 50000], [SUPER, 'superadmin', 0]]) {
    await db.collection('users').doc(uid).set({ role, phone: uid, name: 'T', bonusBalance: bal });
    if (bal) {
      await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(uid))
          .set({ type: 'liability', ownerUid: uid, balance: bal });
    }
  }
}
const bal = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const topup = (id, uid, amount, over = {}) => db.collection('wallet_topup_requests').doc(id)
    .set({ uid, amount, status: 'awaiting_review', ...over });
const withdraw = (id, uid, amount, over = {}) => db.collection('wallet_withdraw_requests').doc(id)
    .set({ uid, amount, status: 'pending', payoutCardNumber: '8600123412341234', ...over });
const reviewTopUp = (who, data) => fns.adminReviewWalletTopUp.run(data, ctxOf(who));
const reviewWithdraw = (who, data) => fns.adminReviewWalletWithdraw.run(data, ctxOf(who));
async function rejects(promise, code, errorCode) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    if (errorCode) assert.strictEqual((e.details || {}).errorCode, errorCode);
    return;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli bajarildi`);
}

/** Webhook'ni soxta req/res bilan chaqirish. */
async function hook({ secretEnv, header, key, body }) {
  if (secretEnv === undefined) delete process.env.TELEGRAM_WALLET_WEBHOOK_SECRET;
  else process.env.TELEGRAM_WALLET_WEBHOOK_SECRET = secretEnv;
  const headers = { 'x-telegram-bot-api-secret-token': header || '' };
  const req = { method: 'POST', query: key ? { key } : {}, get: (h) => headers[h.toLowerCase()], body: body || {} };
  const res = { code: 0, body: '', status(c) { this.code = c; return this; }, send(b) { this.body = b; return this; } };
  await fns.telegramWalletBotWebhook(req, res);
  return res;
}
const SECRET = 'S3cr3t-value-for-test';
const linkMsg = (tgId, code) => ({ message: { chat: { id: tgId }, from: { id: tgId, username: `u${tgId}` }, text: `/link ${code}` } });

(async () => {
  // ─── Maker–checker ──────────────────────────────────────────────────
  await reset();
  await check('V1 finance O\'Z to\'ldirish so\'rovini tasdiqlay olmaydi', async () => {
    await topup('T1', FIN, 30000);
    await rejects(reviewTopUp(FIN, { requestId: 'T1', accept: true }), 'permission-denied', 'SELF_REVIEW_FORBIDDEN');
    assert.strictEqual(await bal(FIN), 50000);
    assert.strictEqual((await db.collection(ledger.COL_JOURNAL).get()).size, 0);
  });

  await reset();
  await check('V2 superadmin (ega) o\'z so\'rovini tasdiqlaydi — admin_audit\'ga yoziladi', async () => {
    await topup('T2', SUPER, 30000);
    const r = await reviewTopUp(SUPER, { requestId: 'T2', accept: true });
    assert.strictEqual(r.status, 'credited');
    assert.strictEqual(await bal(SUPER), 30000);
    const a = await db.collection('admin_audit').where('kind', '==', 'wallet_self_review').get();
    assert.strictEqual(a.size, 1);
  });

  await reset();
  await check('V3 finance BOSHQA foydalanuvchi so\'rovini tasdiqlaydi — ishlaydi', async () => {
    await topup('T3', USER, 30000);
    const r = await reviewTopUp(FIN, { requestId: 'T3', accept: true });
    assert.strictEqual(r.status, 'credited');
    assert.strictEqual(await bal(USER), 130000);
  });

  // ─── Parallel tasdiq / rad etish ───────────────────────────────────
  await reset();
  await check('V4 parallel tasdiq + rad: «rad etildi, lekin pul yozildi» YO\'Q', async () => {
    await topup('T4', USER, 30000);
    await Promise.allSettled([
      reviewTopUp(FIN, { requestId: 'T4', accept: true }),
      reviewTopUp(SUPER, { requestId: 'T4', accept: false, rejectReason: 'x' }),
    ]);
    const st = (await db.collection('wallet_topup_requests').doc('T4').get()).data().status;
    const credited = (await bal(USER)) === 130000;
    if (st === 'rejected') assert.strictEqual(credited, false, 'rad etilgan, lekin pul yozilgan');
    else assert.strictEqual(st, 'credited');
    if (st === 'credited') assert.strictEqual(credited, true);
  });

  await reset();
  await check('V5 ikki parallel tasdiq — pul BIR marta', async () => {
    await topup('T5', USER, 30000);
    await Promise.allSettled([
      reviewTopUp(FIN, { requestId: 'T5', accept: true }),
      reviewTopUp(SUPER, { requestId: 'T5', accept: true }),
    ]);
    assert.strictEqual(await bal(USER), 130000);
  });

  await reset();
  await check('V6 tasdiq jarayonida (ijara faol) rad etish — REQUEST_IN_PROGRESS', async () => {
    await topup('T6', USER, 30000, { processingAt: admin.firestore.Timestamp.now(), processingBy: FIN });
    await rejects(reviewTopUp(SUPER, { requestId: 'T6', accept: false }), 'failed-precondition', 'REQUEST_IN_PROGRESS');
  });

  await reset();
  await check('V7 yechish: finance o\'z yechishini tasdiqlay olmaydi; boshqasinikini — ha', async () => {
    await withdraw('W1', FIN, 20000);
    await rejects(reviewWithdraw(FIN, { requestId: 'W1', accept: true }), 'permission-denied', 'SELF_REVIEW_FORBIDDEN');
    assert.strictEqual(await bal(FIN), 50000);
    await withdraw('W2', USER, 20000);
    const r = await reviewWithdraw(FIN, { requestId: 'W2', accept: true });
    assert.strictEqual(r.status, 'approved');
    assert.strictEqual(await bal(USER), 80000);
  });

  await reset();
  await check('V8 yechish muvaffaqiyatsiz (hamyon yetmaydi) — ijara bo\'shaydi, rad etish mumkin', async () => {
    await withdraw('W3', USER, 500000);
    await rejects(reviewWithdraw(FIN, { requestId: 'W3', accept: true }), 'failed-precondition');
    const d = (await db.collection('wallet_withdraw_requests').doc('W3').get()).data();
    assert.strictEqual(d.status, 'pending');
    assert.strictEqual(d.processingAt, undefined);
    const r = await reviewWithdraw(SUPER, { requestId: 'W3', accept: false, rejectReason: 'yetmaydi' });
    assert.strictEqual(r.status, 'rejected');
  });

  // ─── Webhook siri ───────────────────────────────────────────────────
  await reset();
  await check('W1 sir sozlanmagan — 503, update ishlanmaydi (avval fail-open)', async () => {
    const r = await hook({ secretEnv: undefined, header: '', body: linkMsg(111, '123456') });
    assert.strictEqual(r.code, 503);
    assert.strictEqual((await db.collection('telegram_link_attempts').get()).size, 0);
  });
  await check('W2 noto\'g\'ri sir — 403', async () => {
    const r = await hook({ secretEnv: SECRET, header: 'wrong' });
    assert.strictEqual(r.code, 403);
  });
  await check('W3 header\'da to\'g\'ri sir — 200', async () => {
    const r = await hook({ secretEnv: SECRET, header: SECRET });
    assert.strictEqual(r.code, 200);
  });
  await check('W4 eski ?key= hali qabul qilinadi (moslik), 200', async () => {
    const r = await hook({ secretEnv: SECRET, key: SECRET });
    assert.strictEqual(r.code, 200);
  });

  // ─── Bog'lash kodi ─────────────────────────────────────────────────
  await reset();
  await check('L1 5 ta noto\'g\'ri kod → 6-urinishda TO\'G\'RI kod ham qabul qilinmaydi (qulf)', async () => {
    await db.collection('telegram_link_codes').doc('654321').set({
      uid: USER, used: false, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
    });
    for (let i = 0; i < 5; i += 1) {
      await hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(222, String(100000 + i)) });
    }
    await hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(222, '654321') });
    assert.strictEqual((await db.collection('telegram_links').doc('222').get()).exists, false);
    assert.strictEqual((await db.collection('telegram_link_codes').doc('654321').get()).data().used, false);
  });

  await reset();
  await check('L2 to\'g\'ri kod chegaradan oldin — bog\'lanadi, hisoblagich tozalanadi', async () => {
    await db.collection('telegram_link_codes').doc('654321').set({
      uid: USER, used: false, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
    });
    await hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(333, '111111') });
    await hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(333, '654321') });
    const l = await db.collection('telegram_links').doc('333').get();
    assert.strictEqual(l.exists, true);
    assert.strictEqual(l.data().uid, USER);
    assert.strictEqual((await db.collection('telegram_link_attempts').doc('333').get()).exists, false);
  });

  await reset();
  await check('L3 bitta kod ikki Telegram\'dan parallel — faqat BITTASI bog\'lanadi', async () => {
    await db.collection('telegram_link_codes').doc('777777').set({
      uid: USER, used: false, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
    });
    await Promise.allSettled([
      hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(444, '777777') }),
      hook({ secretEnv: SECRET, header: SECRET, body: linkMsg(555, '777777') }),
    ]);
    const a = (await db.collection('telegram_links').doc('444').get()).exists;
    const b = (await db.collection('telegram_links').doc('555').get()).exists;
    assert.strictEqual(Number(a) + Number(b), 1, `bog'langan: 444=${a} 555=${b}`);
  });

  // ─── Sweeper'dan keyingi kech kelgan chek ───────────────────────────
  // Sweeper 24 soatdan keyin so'rovni `expired` qiladi; pulni o'z vaqtida
  // o'tkazgan foydalanuvchining kechroq yuborgan cheki RAD ETILMASLIGI kerak.
  // Storage emulyatori yo'q: fetch stub'i `file_path` qaytarmaydi, shuning
  // uchun holat tekshiruvidan O'TGAN so'rov «Чекни юклаб бўлмади» deydi,
  // o'tmaganlari esa «Сўров ҳолати: …».
  const receiptMsg = (tgId) => ({
    message: { chat: { id: tgId }, from: { id: tgId, username: `u${tgId}` }, photo: [{ file_id: 'f1' }] },
  });
  async function receiptReply(status) {
    await reset();
    await db.collection('telegram_links').doc('900').set({ uid: USER, status: 'active' });
    await topup('R1', USER, 30000, { status });
    await db.collection('telegram_bot_sessions').doc('900').set({ expect: 'deposit_receipt', topupRequestId: 'R1' });
    sent.length = 0;
    await hook({ secretEnv: SECRET, header: SECRET, body: receiptMsg(900) });
    return sent.map((x) => String(x.body || '')).join('\n');
  }
  await check('E1 muddati o\'tgan (expired) so\'rovga kech kelgan chek holat tekshiruvidan o\'tadi', async () => {
    const out = await receiptReply('expired');
    assert.ok(!out.includes('Сўров ҳолати'), `rad etildi: ${out}`);
  });
  await check('E2 awaiting_transfer so\'rovga chek ham o\'tadi (o\'zgarmagan yo\'l)', async () => {
    const out = await receiptReply('awaiting_transfer');
    assert.ok(!out.includes('Сўров ҳолати'), `rad etildi: ${out}`);
  });
  await check('E3 allaqachon credited so\'rovga chek RAD etiladi', async () => {
    const out = await receiptReply('credited');
    assert.ok(out.includes('Сўров ҳолати'), `rad etilmadi: ${out}`);
  });

  // ─── Ilovadan summali havola: /start deposit_N ──────────────────────
  // Ilova botni `?start=deposit_150000` bilan ochadi; bot lagit/limitni o'zi
  // tekshiradi, takror bosishda ikkinchi so'rov OCHMAYDI.
  const CARD = '8600 0000 0000 0007';
  const startMsg = (tgId, payload) => ({
    message: { chat: { id: tgId }, from: { id: tgId, username: `u${tgId}` }, text: `/start ${payload}` },
  });
  const openTopUps = async () => (await db.collection('wallet_topup_requests')
      .where('status', '==', 'awaiting_transfer').get()).docs.map((d) => d.data());
  async function depositSetup(settings = {}) {
    await reset();
    await db.doc('settings/wallet_bot').set({ enabled: true, depositCardNumber: CARD, maxTopUp: 500000, ...settings });
    await db.collection('telegram_links').doc('910').set({ uid: USER, status: 'active' });
    sent.length = 0;
  }
  const said = () => sent.map((x) => String(x.body || '')).join('\n');

  await check('D1 start=deposit_150000 — so\'rov shu summaga ochiladi, karta ko\'rsatiladi', async () => {
    await depositSetup();
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_150000') });
    const open = await openTopUps();
    assert.strictEqual(open.length, 1);
    assert.strictEqual(open[0].amount, 150000);
    assert.strictEqual(open[0].uid, USER);
    assert.ok(said().includes('8600 0000 0000 0007'), 'karta ko\'rsatilmadi');
    // Qaysi kartaga to'lash aytilgani (karta almashsa moliya chekni solishtiradi) — faqat oxirgi 4 raqam.
    assert.strictEqual(open[0].depositCardLast4, '0007');
    assert.ok(!JSON.stringify(open[0]).includes('8600000000000007'), 'to\'liq karta so\'rovga yozilmasligi kerak');
  });

  await check('D2 takror bosish — ikkinchi so\'rov ochilmaydi, shu so\'rov qayta ko\'rsatiladi', async () => {
    await depositSetup();
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_150000') });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_150000') });
    assert.strictEqual((await openTopUps()).length, 1);
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_200000') });
    assert.strictEqual((await openTopUps()).length, 2, 'boshqa summa — yangi so\'rov');
  });

  await check('D3 summa maxTopUp\'dan katta — so\'rov OCHILMAYDI (server lagitni o\'zi tekshiradi)', async () => {
    await depositSetup({ maxTopUp: 200000 });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_999999') });
    assert.strictEqual((await openTopUps()).length, 0);
  });

  await check('D4 hamyoni bog\'lanmagan Telegram — so\'rov OCHILMAYDI', async () => {
    await depositSetup();
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(911, 'deposit_150000') });
    assert.strictEqual((await openTopUps()).length, 0);
  });

  await check('D5 notog\'ri payload (deposit_abc, deposit_-5) — so\'rov OCHILMAYDI', async () => {
    await depositSetup();
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_abc') });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_-5') });
    assert.strictEqual((await openTopUps()).length, 0);
  });

  await check('D6 karta sozlanmagan — so\'rov OCHILMAYDI', async () => {
    await depositSetup({ depositCardNumber: '' });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(910, 'deposit_150000') });
    assert.strictEqual((await openTopUps()).length, 0);
  });

  await check('D7 birinchi marta: kod bilan birga summa — bog\'langach so\'rov shu summaga ochiladi', async () => {
    await depositSetup();
    await db.collection('telegram_links').doc('910').delete();
    await db.collection('telegram_link_codes').doc('135790').set({
      uid: USER, used: false, pendingTopUpAmount: 120000,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
    });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(920, 'link_135790') });
    assert.strictEqual((await db.collection('telegram_links').doc('920').get()).exists, true);
    const open = await openTopUps();
    assert.strictEqual(open.length, 1);
    assert.strictEqual(open[0].amount, 120000);
  });

  await check('D8 kodsiz bog\'lash (summa yo\'q) — so\'rov OCHILMAYDI, eski xatti-harakat', async () => {
    await depositSetup();
    await db.collection('telegram_links').doc('910').delete();
    await db.collection('telegram_link_codes').doc('246810').set({
      uid: USER, used: false, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 600000),
    });
    await hook({ secretEnv: SECRET, header: SECRET, body: startMsg(921, 'link_246810') });
    assert.strictEqual((await openTopUps()).length, 0);
  });

  const passed = results.filter(Boolean).length;
  const failed = results.length - passed;
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error('FATAL', e);
  process.exit(1);
});
