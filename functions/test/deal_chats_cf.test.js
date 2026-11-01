/**
 * Улгуржи/Хитой «Буюртма ёзиш» чати — callable'лар, HAQIQIY `functions/index.js`, Firestore Emulator.
 * FCM — stub (тармоққа чиқмайди), юборилган push'лар саналади.
 *
 *   firebase emulators:exec --only firestore --project demo-deal-chat \
 *     "node test/deal_chats_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-deal-chat';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const { dealChatId, normalizeText, previewOf, rateGate, LIMITS } = require('../deal_chats');

const sent = [];
let failNext = false;
Object.defineProperty(admin, 'messaging', {
  configurable: true,
  value: () => ({
    send: async (m) => {
      if (failNext) { failNext = false; throw new Error('stub: token invalid'); }
      sent.push(m);
      return 'stub-id';
    },
  }),
});

const db = admin.firestore();
const SELLER = '998913000001';
const BUYER = '998913000002';
const BUYER2 = '998913000003';
const STRANGER = '998913000004';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const anonCtx = { auth: { uid: 'anon_1', token: {} } };
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
const chatDoc = async (id) => (await db.collection('deal_chats').doc(id).get()).data();
const msgs = async (id) => (await db.collection('deal_chats').doc(id).collection('messages').orderBy('at').get()).docs.map((d) => d.data());
let seq = 0;
const cid = () => `client-${String(++seq).padStart(6, '0')}`;

async function main() {
  await clearEmulator();
  await db.collection('users').doc(SELLER).set({ role: 'user', fcmToken: 'tok-seller', appLang: 'ru' });
  await db.collection('users').doc(BUYER).set({ role: 'user', fcmToken: 'tok-buyer', appLang: 'uz_Latn' });
  await db.collection('users').doc(BUYER2).set({ role: 'user' });
  await db.collection('users').doc(STRANGER).set({ role: 'user', fcmToken: 'tok-x' });
  // sellerId 9 хонали (эски ёзув шакли) — сервер 998 + 9 га келтиради.
  await db.collection('wholesale_products').doc('p_ok').set({
    sellerId: SELLER.slice(3), status: 'active', market: 'china', title: 'Samokat X1',
    imageUrls: ['https://img/1.jpg', 'https://img/2.jpg'],
  });
  await db.collection('wholesale_products').doc('p_pending').set({ sellerId: SELLER, status: 'pending', title: 'P' });
  await db.collection('wholesale_products').doc('p_noseller').set({ sellerId: '', status: 'active', title: 'N' });

  await check('P1 sof funksiyalar: matn chegarasi (1000), preview, chatId, daqiqalik chegara', () => {
    assert.strictEqual(normalizeText('  salom  '), 'salom');
    assert.strictEqual(normalizeText('   '), null);
    assert.strictEqual(normalizeText(''), null);
    assert.strictEqual(normalizeText(42), null);
    assert.strictEqual(normalizeText('x'.repeat(LIMITS.textMax)).length, 1000);
    assert.strictEqual(normalizeText('x'.repeat(LIMITS.textMax + 1)), null);
    assert.strictEqual(previewOf('a\n\n b   c'), 'a b c');
    assert.strictEqual(previewOf('y'.repeat(500)).length, LIMITS.previewMax);
    assert.strictEqual(dealChatId('p1', BUYER), `p1_${BUYER}`);
    const now = 60000 * 1000;
    assert.deepStrictEqual(rateGate(null, now), { allowed: true, next: { minuteKey: 1000, minuteCount: 1 } });
    assert.strictEqual(rateGate({ minuteKey: 1000, minuteCount: 19 }, now).allowed, true);
    assert.strictEqual(rateGate({ minuteKey: 1000, minuteCount: 20 }, now).allowed, false);
    assert.deepStrictEqual(rateGate({ minuteKey: 999, minuteCount: 20 }, now).next, { minuteKey: 1000, minuteCount: 1 });
  });

  await check('A1 auth: login yo\'q / anonim (telefonsiz) — rad', async () => {
    await assert.rejects(fns.openDealChat.run({ productId: 'p_ok' }, {}), (e) => e.code === 'unauthenticated');
    await expectCode(fns.openDealChat.run({ productId: 'p_ok' }, anonCtx), 'PHONE_REQUIRED');
  });

  await check('O1 ochish: noto\'g\'ri id, yo\'q/aktiv emas/sotuvchisiz mahsulot, o\'z mahsuloti — rad', async () => {
    await expectCode(call('openDealChat', { productId: '' }, BUYER), 'PRODUCT_INVALID');
    await expectCode(call('openDealChat', { productId: 'a/b' }, BUYER), 'PRODUCT_INVALID');
    await expectCode(call('openDealChat', { productId: 'no_such' }, BUYER), 'PRODUCT_UNAVAILABLE');
    await expectCode(call('openDealChat', { productId: 'p_pending' }, BUYER), 'PRODUCT_UNAVAILABLE');
    await expectCode(call('openDealChat', { productId: 'p_noseller' }, BUYER), 'PRODUCT_UNAVAILABLE');
    await expectCode(call('openDealChat', { productId: 'p_ok' }, SELLER), 'OWN_PRODUCT');
    assert.strictEqual((await db.collection('deal_chats').get()).size, 0);
  });

  const CHAT = dealChatId('p_ok', BUYER);
  await check('O2 ochish: chat yaratiladi (a\'zolar, kanon sellerId, nom/rasm, lastAt YO\'Q); takror — o\'sha chat', async () => {
    const r = await call('openDealChat', { productId: 'p_ok' }, BUYER);
    assert.deepStrictEqual(r, { ok: true, chatId: CHAT, created: true });
    const d = await chatDoc(CHAT);
    assert.deepStrictEqual(d.members, [BUYER, SELLER]);
    assert.deepStrictEqual([d.buyerId, d.sellerId, d.productId, d.market], [BUYER, SELLER, 'p_ok', 'china']);
    assert.deepStrictEqual([d.productTitle, d.productPhoto], ['Samokat X1', 'https://img/1.jpg']);
    assert.deepStrictEqual(d.unread, { [BUYER]: 0, [SELLER]: 0 });
    assert.ok(!('lastAt' in d), 'xabarsiz chat ro\'yxatga tushmasin');
    const again = await call('openDealChat', { productId: 'p_ok' }, BUYER);
    assert.deepStrictEqual(again, { ok: true, chatId: CHAT, created: false });
    assert.strictEqual((await db.collection('deal_chats').get()).size, 1);
    assert.strictEqual(sent.length, 0, 'ochishda push yo\'q');
  });

  await check('O3 parallel ikki ochish — bitta chat, bittasi created', async () => {
    const [a, b] = await Promise.all([
      call('openDealChat', { productId: 'p_ok' }, BUYER2),
      call('openDealChat', { productId: 'p_ok' }, BUYER2),
    ]);
    assert.strictEqual(a.chatId, b.chatId);
    assert.strictEqual([a.created, b.created].filter(Boolean).length, 1);
    assert.strictEqual((await db.collection('deal_chats').get()).size, 2);
  });

  await check('S1 yuborish: validatsiya (chatId, matn bo\'sh/1001, clientId)', async () => {
    await expectCode(call('sendDealMessage', { chatId: 'bad id', text: 'x', clientId: cid() }, BUYER), 'CHAT_INVALID');
    await expectCode(call('sendDealMessage', { chatId: CHAT, text: '   ', clientId: cid() }, BUYER), 'TEXT_INVALID');
    await expectCode(call('sendDealMessage', { chatId: CHAT, text: 'x'.repeat(1001), clientId: cid() }, BUYER), 'TEXT_INVALID');
    await expectCode(call('sendDealMessage', { chatId: CHAT, text: 'salom', clientId: 'short' }, BUYER), 'CLIENT_ID_INVALID');
    assert.strictEqual((await msgs(CHAT)).length, 0);
  });

  await check('S2 begona a\'zo emas: yuborish/o\'qildi — CHAT_NOT_FOUND; yo\'q chat ham xuddi shunday', async () => {
    await expectCode(call('sendDealMessage', { chatId: CHAT, text: 'salom', clientId: cid() }, STRANGER), 'CHAT_NOT_FOUND');
    await expectCode(call('markDealChatRead', { chatId: CHAT }, STRANGER), 'CHAT_NOT_FOUND');
    await expectCode(call('sendDealMessage', { chatId: `p_ok_${STRANGER}`, text: 'salom', clientId: cid() }, STRANGER), 'CHAT_NOT_FOUND');
  });

  await check('S3 харидор ёзади → sotuvchiga push (matnsiz, ru), unread seller=1, last*, lastAt paydo', async () => {
    sent.length = 0;
    const r = await call('sendDealMessage', { chatId: CHAT, text: '  100 dona kerak, narxi?  ', clientId: 'buyer-msg-0001' }, BUYER);
    assert.deepStrictEqual([r.ok, r.duplicate, r.messageId], [true, false, `${BUYER}-buyer-msg-0001`]);
    const m = await msgs(CHAT);
    assert.strictEqual(m.length, 1);
    assert.deepStrictEqual([m[0].from, m[0].text, m[0].clientId], [BUYER, '100 dona kerak, narxi?', 'buyer-msg-0001']);
    const d = await chatDoc(CHAT);
    assert.deepStrictEqual(d.unread, { [BUYER]: 0, [SELLER]: 1 });
    assert.deepStrictEqual([d.lastMessage, d.lastFrom], ['100 dona kerak, narxi?', BUYER]);
    assert.ok(d.lastAt && typeof d.lastAt.toMillis === 'function');
    assert.strictEqual(sent.length, 1);
    const p = sent[0];
    assert.strictEqual(p.token, 'tok-seller');
    assert.deepStrictEqual(p.data, { type: 'deal_chat', screen: 'deal_chat', tab: 'messages', chatId: CHAT });
    assert.ok(p.notification.title.includes('Samokat X1'), p.notification.title);
    assert.ok(/Новое сообщение/.test(p.notification.title), 'sotuvchi tili ru');
    assert.ok(!p.notification.body.includes('100 dona'), 'push matnida xabar matni YO\'Q');
  });

  await check('S4 clientId takrori — dublikat: yangi xabar, unread++ va push YO\'Q', async () => {
    sent.length = 0;
    const r = await call('sendDealMessage', { chatId: CHAT, text: '100 dona kerak, narxi?', clientId: 'buyer-msg-0001' }, BUYER);
    assert.deepStrictEqual([r.duplicate, r.messageId], [true, `${BUYER}-buyer-msg-0001`]);
    assert.strictEqual((await msgs(CHAT)).length, 1);
    assert.strictEqual((await chatDoc(CHAT)).unread[SELLER], 1);
    assert.strictEqual(sent.length, 0);
  });

  await check('S5 sotuvchi javobi → xaridorga push (uz_Latn), unread: buyer=1, seller=0 (yozgan — o\'qigan)', async () => {
    sent.length = 0;
    await call('sendDealMessage', { chatId: CHAT, text: 'Dona 45 000, 100 dan ko\'p bo\'lsa chegirma', clientId: 'seller-msg-0001' }, SELLER);
    const d = await chatDoc(CHAT);
    assert.deepStrictEqual(d.unread, { [BUYER]: 1, [SELLER]: 0 });
    assert.strictEqual(d.lastFrom, SELLER);
    assert.strictEqual(sent.length, 1);
    assert.strictEqual(sent[0].token, 'tok-buyer');
    assert.ok(/Yangi xabar/.test(sent[0].notification.title));
    assert.strictEqual((await msgs(CHAT)).length, 2);
  });

  await check('S6 push yiqilsa ham xabar saqlanadi, funksiya xato bermaydi; token yo\'q — push yo\'q', async () => {
    failNext = true;
    const r = await call('sendDealMessage', { chatId: CHAT, text: 'Kelishdik', clientId: 'buyer-msg-0002' }, BUYER);
    assert.strictEqual(r.ok, true);
    assert.strictEqual((await msgs(CHAT)).length, 3);
    sent.length = 0;
    const chat2 = dealChatId('p_ok', BUYER2);
    await call('sendDealMessage', { chatId: chat2, text: 'salom', clientId: 'buyer2-msg-001' }, BUYER2);
    await call('sendDealMessage', { chatId: chat2, text: 'javob', clientId: 'seller-msg-0002' }, SELLER);
    assert.strictEqual(sent.length, 1, 'BUYER2 da fcmToken yo\'q — faqat sotuvchiga');
  });

  await check('R1 o\'qildi: o\'z unread 0 ga; takror — o\'zgarishsiz; boshqa tomonniki tegilmaydi', async () => {
    const before = await chatDoc(CHAT);
    assert.strictEqual(before.unread[SELLER], 1);
    const r = await call('markDealChatRead', { chatId: CHAT }, SELLER);
    assert.deepStrictEqual(r, { ok: true, changed: true });
    const d = await chatDoc(CHAT);
    assert.strictEqual(d.unread[SELLER], 0);
    assert.strictEqual(d.unread[BUYER], before.unread[BUYER]);
    assert.deepStrictEqual(await call('markDealChatRead', { chatId: CHAT }, SELLER), { ok: true, changed: false });
  });

  await check('C1 parallel ikki yuborish (bitta foydalanuvchi): ikkala xabar, unread +2', async () => {
    const d0 = await chatDoc(CHAT);
    const n0 = (await msgs(CHAT)).length;
    await Promise.all([
      call('sendDealMessage', { chatId: CHAT, text: 'bir', clientId: 'par-msg-00001' }, BUYER),
      call('sendDealMessage', { chatId: CHAT, text: 'ikki', clientId: 'par-msg-00002' }, BUYER),
    ]);
    const d = await chatDoc(CHAT);
    assert.strictEqual(d.unread[SELLER], d0.unread[SELLER] + 2);
    assert.strictEqual((await msgs(CHAT)).length, n0 + 2);
  });

  await check('C2 parallel bir xil clientId — bitta xabar, unread +1', async () => {
    const d0 = await chatDoc(CHAT);
    const n0 = (await msgs(CHAT)).length;
    const rs = await Promise.all([
      call('sendDealMessage', { chatId: CHAT, text: 'uch', clientId: 'same-msg-00001' }, BUYER),
      call('sendDealMessage', { chatId: CHAT, text: 'uch', clientId: 'same-msg-00001' }, BUYER),
    ]);
    assert.strictEqual(rs.filter((r) => r.duplicate).length, 1);
    assert.strictEqual((await chatDoc(CHAT)).unread[SELLER], d0.unread[SELLER] + 1);
    assert.strictEqual((await msgs(CHAT)).length, n0 + 1);
  });

  await check('L1 daqiqalik chegara: 20-chi o\'tadi, 21-chi RATE_LIMITED; boshqa foydalanuvchi alohida', async () => {
    // Joriy daqiqa hisobini 19 ga qo'yamiz (daqiqa chegarasida test beqaror bo'lmasin).
    const key = Math.floor(Date.now() / 60000);
    await db.collection('deal_chat_usage').doc(BUYER).set({ minuteKey: key, minuteCount: 19 });
    const ok = await call('sendDealMessage', { chatId: CHAT, text: '20-chi', clientId: 'rate-msg-00020' }, BUYER);
    assert.strictEqual(ok.ok, true);
    const u = (await db.collection('deal_chat_usage').doc(BUYER).get()).data();
    if (u.minuteKey === key) {
      assert.strictEqual(u.minuteCount, 20);
      await expectCode(call('sendDealMessage', { chatId: CHAT, text: '21-chi', clientId: 'rate-msg-00021' }, BUYER), 'RATE_LIMITED');
      assert.ok(!(await db.doc(`deal_chats/${CHAT}/messages/${BUYER}-rate-msg-00021`).get()).exists);
    }
    const s = await call('sendDealMessage', { chatId: CHAT, text: 'sotuvchi', clientId: 'rate-msg-s0001' }, SELLER);
    assert.strictEqual(s.ok, true);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
