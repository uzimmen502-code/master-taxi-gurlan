/**
 * Ҳамённи тўлдириш: карта текшируви, тайёрлик ҳолати ва молияга хабар —
 * ҲАҚИҚИЙ функциялар (Firestore Emulator), Telegram API stub.
 *
 *   npm run test:wallet-topup-cf   (functions/ ичидан)
 *
 *   C1  нотўғри карта сақланмайди (CARD_INVALID); тўғриси ва бўши — сақланади
 *   C2  getWalletTopUpStatus: карта йўқ / бот ўчиқ / тайёр / нотўғри-лекин-ишлаётган
 *   C3  карта рақами тайёрлик жавобида ЧИҚМАЙДИ; аноним чақира олмайди
 *   C4  ечиш аризаси келганда молия ходимига хабар (иловада + Telegram), оддий
 *       фойдаланувчи ва диспетчерга — йўқ; хабарда карта/телефон йўқ
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-topup';
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.TELEGRAM_WALLET_BOT_TOKEN = 'test-token';

const tgSent = [];
global.fetch = async (url, opts) => {
  tgSent.push({ url: String(url), body: opts && opts.body ? JSON.parse(opts.body) : null });
  return { ok: true, json: async () => ({ ok: true, result: {} }) };
};

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const ledger = require('../settlement_ledger');

const USER = '998901000001';
const FINANCE = '998905000001';
const SUPER = '998905000009';
const DISPATCHER = '998905000002';
const CARD_OK = '4111 1111 1111 1111';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const anon = { auth: { uid: 'anon_1', token: { firebase: { sign_in_provider: 'anonymous' } } } };

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
async function reset(botSettings = {}) {
  await Promise.all(['users', 'settings', 'admin_audit', 'admin_news', 'wallet_withdraw_requests',
    'wallet_topup_requests', ledger.COL_JOURNAL, ledger.COL_ACCOUNTS].map(wipe));
  tgSent.length = 0;
  await db.collection('users').doc(USER).set({ role: 'user', phone: USER, name: 'Test', bonusBalance: 100000 });
  await db.collection(ledger.COL_ACCOUNTS).doc(ledger.passengerCreditAccount(USER))
      .set({ type: 'liability', ownerUid: USER, balance: 100000 });
  await db.collection('users').doc(FINANCE).set({ role: 'finance', phone: FINANCE, telegramId: '777001' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin', phone: SUPER });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher', phone: DISPATCHER, telegramId: '777002' });
  await db.doc('settings/wallet_bot').set({ enabled: true, ...botSettings });
}
async function rejectsWith(promise, errorCode) {
  try { await promise; } catch (e) {
    assert.strictEqual((e.details || {}).errorCode, errorCode, `kutilgan ${errorCode}, keldi ${e.code}/${e.message}`);
    return;
  }
  assert.fail(`${errorCode} bilan rad etilishi kerak edi`);
}
const status = () => fns.getWalletTopUpStatus.run({}, ctxOf(USER));
const setSettings = (data) => fns.adminSetWalletBotSettings.run(data, ctxOf(FINANCE));

(async () => {
  await reset();
  await check('C1 nototog\'ri karta saqlanmaydi; to\'g\'risi (bo\'shliqli) va bo\'sh — saqlanadi', async () => {
    await rejectsWith(setSettings({ depositCardNumber: '8600000000000001' }), 'CARD_INVALID');
    await rejectsWith(setSettings({ depositCardNumber: '1234' }), 'CARD_INVALID');
    await rejectsWith(setSettings({ depositCardNumber: '4111111111111abc' }), 'CARD_INVALID');
    assert.ok(!('depositCardNumber' in ((await db.doc('settings/wallet_bot').get()).data())), 'rad etilgan qiymat yozilmasligi kerak');
    const r = await setSettings({ depositCardNumber: CARD_OK });
    assert.strictEqual(r.settings.depositCardNumber, '4111111111111111');
    const cleared = await setSettings({ depositCardNumber: '' });
    assert.strictEqual(cleared.settings.depositCardNumber, '');
  });

  await reset();
  await check('C2 tayyorlik: karta yo\'q -> tayyor emas; to\'g\'ri karta -> tayyor; bot o\'chiq -> tayyor emas', async () => {
    let s = await status();
    assert.deepStrictEqual([s.ready, s.reason], [false, 'card_missing']);
    await db.doc('settings/wallet_bot').set({ enabled: true, depositCardNumber: '4111111111111111' });
    s = await status();
    assert.deepStrictEqual([s.ready, s.reason], [true, 'ok']);
    await db.doc('settings/wallet_bot').set({ enabled: false, depositCardNumber: '4111111111111111' });
    s = await status();
    assert.deepStrictEqual([s.ready, s.reason], [false, 'bot_disabled']);
  });

  await reset({ depositCardNumber: '8600000000000001' });
  await check('C2b avval saqlangan (Luna o\'tmagan) karta tayyorlikni BLOKLAMAYDI — ishlayotgan to\'ldirish to\'xtamasin', async () => {
    const s = await status();
    assert.deepStrictEqual([s.ready, s.reason], [true, 'card_invalid']);
  });

  await reset({ depositCardNumber: '4111111111111111' });
  await check('C3 javobda karta raqami YO\'Q; limitlar bor; anonim chaqira olmaydi', async () => {
    const s = await status();
    assert.ok(!JSON.stringify(s).includes('4111'), 'karta raqami chiqmasligi kerak');
    assert.strictEqual(typeof s.maxTopUp, 'number');
    assert.strictEqual(typeof s.dailyTopUpLimit, 'number');
    let denied = false;
    try { await fns.getWalletTopUpStatus.run({}, {}); } catch (e) { denied = e.code === 'unauthenticated'; }
    assert.ok(denied, 'autentifikatsiyasiz — rad');
  });

  await reset({ depositCardNumber: '4111111111111111' });
  await check('C4 yechish arizasi: moliya + superadminga xabar (ilovada + Telegram), foydalanuvchi/dispetcherga — yo\'q', async () => {
    const r = await fns.requestWalletWithdraw.run({
      phone: USER, amount: 20000, payoutCardNumber: '4111111111111111', payoutCardHolder: 'Test User',
    }, ctxOf(USER));
    assert.strictEqual(r.status, 'pending');
    const news = (await db.collection('admin_news').get()).docs.map((d) => d.data())
        .filter((n) => n.source === 'wallet_finance_queue');
    assert.deepStrictEqual(news.map((n) => n.targetUserId).sort(), [FINANCE, SUPER].sort());
    const tg = tgSent.filter((m) => /sendMessage/.test(m.url) && m.body);
    assert.deepStrictEqual(tg.map((m) => String(m.body.chat_id)), ['777001'], 'faqat Telegram bog\'langan moliya xodimiga');
    const all = JSON.stringify([news, tg]);
    assert.ok(!all.includes('4111111111111111'), 'karta raqami xabarda bo\'lmasligi kerak');
    assert.ok(!all.includes(USER), 'foydalanuvchi telefoni xabarda bo\'lmasligi kerak');
  });

  // ── Karta o'zgarganda moliyaga ogohlantirish ─────────────────────────
  const cardNews = async () => (await db.collection('admin_news').get()).docs.map((d) => d.data())
      .filter((n) => n.source === 'wallet_finance_queue' && n.title === 'Депозит картаси ўзгартирилди');
  const cardTg = () => tgSent.filter((m) => /sendMessage/.test(m.url) && m.body && /Депозит картаси/.test(String(m.body.text)));

  await reset({ depositCardNumber: '4111111111111111' });
  await db.collection('users').doc(FINANCE).update({ name: 'Али' });
  await check('C5 karta almashtirilsa: moliya + superadminga (ilova + Telegram), dispetcherga YO\'Q; faqat oxirgi 4 raqam', async () => {
    await setSettings({ depositCardNumber: '5555 5555 5555 4444' });
    const news = await cardNews();
    assert.deepStrictEqual(news.map((n) => n.targetUserId).sort(), [FINANCE, SUPER].sort());
    const tg = cardTg();
    assert.deepStrictEqual(tg.map((m) => String(m.body.chat_id)), ['777001']);
    const all = JSON.stringify([news, tg]);
    assert.ok(all.includes('…1111') && all.includes('…4444'), 'eski va yangi oxirgi 4 raqam');
    assert.ok(!all.includes('4111111111111111') && !all.includes('5555555555554444'), 'to\'liq raqam chiqmasligi kerak');
    assert.ok(all.includes('Али'), 'kim o\'zgartirgani ko\'rinsin');
  });

  await reset({ depositCardNumber: '4111111111111111' });
  await check('C6 karta o\'zgarmasa (xuddi shu / faqat ism / limit) — ogohlantirish YO\'Q', async () => {
    await setSettings({ depositCardNumber: CARD_OK });
    await setSettings({ depositCardFirstName: 'Ali', depositCardLastName: 'Valiyev' });
    await setSettings({ maxTopUp: 300000 });
    assert.strictEqual((await cardNews()).length, 0);
  });

  await reset();
  await check('C7 karta birinchi marta kiritilsa / olib tashlansa — ogohlantirish bor; xato asosiy saqlashni BUZMAYDI', async () => {
    await setSettings({ depositCardNumber: CARD_OK });
    assert.strictEqual((await cardNews()).length, 2);
    const body = JSON.stringify(await cardNews());
    assert.ok(body.includes('йўқ') && body.includes('…1111'));
    await wipe('admin_news');
    await setSettings({ depositCardNumber: '' });
    assert.ok(JSON.stringify(await cardNews()).includes('олиб ташланди'));
  });

  await reset({ depositCardNumber: '4111111111111111' });
  await check('C8 notifyUserInApp yiqilsa ham karta o\'zgarishi SAQLANADI (best-effort)', async () => {
    const realFetch = global.fetch;
    global.fetch = async () => { throw new Error('telegram down'); };
    try {
      const r = await setSettings({ depositCardNumber: '5555555555554444' });
      assert.strictEqual(r.settings.depositCardNumber, '5555555555554444');
    } finally { global.fetch = realFetch; }
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
