/**
 * Сотувчининг ўз Telegram канали — ҲАҚИҚИЙ `functions/index.js`, Firestore Emulator, Telegram HTTP СОХТА
 * (`axios.post` алмаштирилади — ташқи сўров йўқ).
 *
 *   firebase emulators:exec --only firestore --project demo-seller-tg "node test/seller_tg_channel_cf.test.js"
 *
 * Инвариантлар: уланиш — фақат бот админ + «Хабар жойлаш» + эгалик коди канал тавсифида; бир канал = бир сотувчи
 * (бир вақтда икки сотувчи — битта ғолиб); бегона канални «эгаллаб» бўлмайди; узиш; жойлаш — ўша розилик билан,
 * алоҳида ҳолат, такрор жойламайди; бот ҳуқуқини йўқотса — `needs_reconnect`.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-seller-tg';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');
delete process.env.TELEGRAM_CHANNEL_BOT_TOKEN;
delete process.env.TELEGRAM_CHANNEL_ID;

const axios = require('axios');
const fns = require('../index');
const admin = require('firebase-admin');
const tgMod = require('../seller_tg_channel');
const { requestedNetworks } = require('../tv_social_publish');

const db = admin.firestore();
const TOKEN = 'TEST_BOT_TOKEN';
const SELLER = '998914300001';
const OTHER = '998914300002';
const ADMIN = '998914300009';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data || {}, who ? ctxOf(who) : {});

// ── Сохта Telegram ──────────────────────────────────────────────────────────
const tg = {};
function tgReset() {
  tg.calls = [];
  tg.bot = { id: 777, is_bot: true, username: 'ava_test_bot' };
  tg.chats = {
    '-1001': { id: -1001, type: 'channel', title: 'Нон дўкони', username: 'non_shop', description: 'Иссиқ нон' },
    '-1002': { id: -1002, type: 'channel', title: 'Бегона канал', username: 'alien_shop', description: '' },
    '-1003': { id: -1003, type: 'supergroup', title: 'Гуруҳ', username: 'some_group', description: '' },
    '-1009': { id: -1009, type: 'channel', title: 'AVA', username: 'ava_official', description: '' },
  };
  tg.members = {
    '-1001': { status: 'administrator', can_post_messages: true },
    '-1002': { status: 'administrator', can_post_messages: true },
    '-1003': { status: 'administrator', can_post_messages: true },
    '-1009': { status: 'administrator', can_post_messages: true },
  };
  tg.sendFail = null;
  tg.methodFail = {};
  tg.nextMessageId = 100;
}
const axiosErr = (status, description) => Object.assign(new Error(`Request failed with status code ${status}`), {
  response: { status, data: { ok: false, error_code: status, description } },
});
const findChat = (id) => {
  const s = String(id);
  if (s.startsWith('@')) return Object.values(tg.chats).find((c) => c.username && `@${c.username}`.toLowerCase() === s.toLowerCase());
  return tg.chats[s];
};
axios.post = async (url, params) => {
  const m = /\/bot([^/]+)\/(\w+)$/.exec(String(url));
  if (!m) throw new Error(`kutilmagan URL ${url}`);
  const [, token, method] = m;
  tg.calls.push({ method, params });
  if (token !== TOKEN) throw axiosErr(401, 'Unauthorized');
  if (tg.methodFail[method]) throw axiosErr(...tg.methodFail[method]);
  if (method === 'getMe') return { data: { ok: true, result: tg.bot } };
  if (method === 'getChat') {
    const c = findChat(params.chat_id);
    if (!c) throw axiosErr(400, 'Bad Request: chat not found');
    return { data: { ok: true, result: { ...c } } };
  }
  if (method === 'getChatMember') {
    const c = findChat(params.chat_id);
    const mem = c && tg.members[String(c.id)];
    if (!c || !mem || params.user_id !== tg.bot.id) throw axiosErr(400, 'Bad Request: member list is inaccessible');
    return { data: { ok: true, result: { user: tg.bot, ...mem } } };
  }
  if (method === 'sendVideo') {
    if (tg.sendFail) throw axiosErr(tg.sendFail[0], tg.sendFail[1]);
    const c = findChat(params.chat_id);
    if (!c) throw axiosErr(400, 'Bad Request: chat not found');
    tg.nextMessageId += 1;
    return { data: { ok: true, result: { message_id: tg.nextMessageId, chat: { id: c.id } } } };
  }
  throw new Error(`kutilmagan metod ${method}`);
};
const sends = () => tg.calls.filter((c) => c.method === 'sendVideo');

// ── Ёрдамчилар ─────────────────────────────────────────────────────────────
const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => {
    const got = (e.details && e.details.code) || e.code || e.message;
    assert.strictEqual(got, code, `kod ${got}: ${e.message}`);
    return true;
  });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function reset({ token = TOKEN } = {}) {
  await clearEmulator();
  tgReset();
  await db.doc('settings/tv_social').set(token ? { telegramBotToken: token, telegramChannelId: '@ava_official' } : {});
  await db.doc(`users/${ADMIN}`).set({ role: 'admin', phone: ADMIN });
  await db.doc(`users/${SELLER}`).set({ role: 'user', phone: SELLER });
  await db.doc(`users/${OTHER}`).set({ role: 'user', phone: OTHER });
}
const chanDoc = async (p) => (await db.doc(`${tgMod.CHANNELS}/${p}`).get()).data();
const chatIdx = async (id) => db.doc(`${tgMod.CHATS}/${id}`).get();
/** Канални тўлиқ улаш (код тавсифга ёзилади). */
async function connect(who, username, chatId) {
  const r = await call('sellerTgChannelPrepare', { username }, who);
  tg.chats[chatId].description = `${tg.chats[chatId].description} ${r.channel.code}`;
  return call('sellerTgChannelConnect', {}, who);
}
const clip = (o = {}) => ({
  ownerPhone: SELLER, ownerName: 'Али', category: 'product', status: 'active', videoUrl: 'https://x/v.mp4',
  title: 'Иссиқ нон', price: 35000, description: 'Тандир нон, ҳар куни эрталаб', districtLabel: 'Гурлан',
  socialConsent: true, socialNetworks: ['seller_telegram'], socialConsentVersion: 2,
  socialConsentAt: admin.firestore.Timestamp.fromMillis(1761400000000), ...o,
});
const publish = (clipId) => call('adminPublishTvClipSocial', { clipId }, ADMIN);
const clipData = async (id) => (await db.doc(`tv_clips/${id}`).get()).data();

(async () => {
  // ── Соф функциялар ──
  await check('U1 kanal nomi: @, t.me, https; yopiq taklif va yaroqsiz nom ajratiladi', async () => {
    assert.deepStrictEqual(tgMod.parseChannelInput('@Non_Shop'), { username: 'Non_Shop', private: false });
    assert.strictEqual(tgMod.parseChannelInput('https://t.me/non_shop/12').username, 'non_shop');
    assert.strictEqual(tgMod.parseChannelInput(' t.me/non_shop ').username, 'non_shop');
    assert.strictEqual(tgMod.parseChannelInput('https://t.me/+AbCdEf').private, true);
    assert.strictEqual(tgMod.parseChannelInput('t.me/joinchat/AbCdEf').private, true);
    for (const bad of ['', '@ab', '1abc', 'non shop', '@' + 'a'.repeat(40), '<script>']) {
      assert.strictEqual(tgMod.parseChannelInput(bad).username, '', bad);
    }
  });
  await check('U2 kod: AVA-XXXXXX, tavsifda katta-kichik harf farqsiz topiladi; boshqa kod/bo\'sh — yo\'q', async () => {
    const c = tgMod.newCode();
    assert.match(c, /^AVA-[A-Z2-9]{6}$/);
    assert.ok(tgMod.descriptionHasCode(`Nonlar. ${c.toLowerCase()} :)`, c));
    assert.ok(!tgMod.descriptionHasCode('Nonlar AVA-AAAAAA', c === 'AVA-AAAAAA' ? 'AVA-BBBBBB' : c));
    assert.ok(!tgMod.descriptionHasCode('', c));
    assert.ok(!tgMod.descriptionHasCode('anything', ''));
  });
  await check('U3 caption: sarlavha, butun so\'m narx, tavsif, havola; telefon/ism/hudud yo\'q; limitda faqat tavsif qisqaradi', async () => {
    const cap = tgMod.buildSellerCaption(clip(), 'https://ava/s/AbCdEfGhJk');
    assert.strictEqual(cap, 'Иссиқ нон\n35 000 сўм\nТандир нон, ҳар куни эрталаб\n🛒 https://ava/s/AbCdEfGhJk');
    assert.ok(!cap.includes('Али') && !cap.includes('Гурлан') && !cap.includes(SELLER));
    const long = tgMod.buildSellerCaption(clip({ description: 'x'.repeat(5000) }), 'https://ava/s/AbCdEfGhJk');
    assert.ok(long.length <= 1000 && long.endsWith('🛒 https://ava/s/AbCdEfGhJk'));
    assert.ok(!tgMod.buildSellerCaption(clip({ price: 12.5 }), '').includes('сўм'), 'kasr narx chiqmaydi');
    assert.ok(!tgMod.buildSellerCaption(clip({ price: 0 }), '').includes('сўм'));
  });
  await check('U4 qayta ulash kerakligi: 403, «not enough rights», «chat not found» — ha; 429/500/tarmoq — yo\'q', async () => {
    const E = tgMod.TgError;
    assert.ok(tgMod.needsReconnectError(new E(403, 'Forbidden: bot was kicked from the channel chat')));
    assert.ok(tgMod.needsReconnectError(new E(400, 'Bad Request: not enough rights to send videos to the chat')));
    assert.ok(tgMod.needsReconnectError(new E(400, 'Bad Request: chat not found')));
    assert.ok(!tgMod.needsReconnectError(new E(429, 'Too Many Requests: retry after 5')));
    assert.ok(!tgMod.needsReconnectError(new E(500, 'Internal Server Error')));
    assert.ok(!tgMod.needsReconnectError(new E(400, 'Bad Request: wrong file identifier/HTTP URL specified')));
    assert.ok(!tgMod.needsReconnectError(new Error('ECONNRESET')));
  });
  await check('U5 requestedNetworks: seller_telegram faqat rozilik bilan, faqat tovar/xizmat; reklama o\'zgarmaydi; eski klip o\'zgarmaydi', async () => {
    assert.deepStrictEqual(requestedNetworks(clip()), ['seller_telegram']);
    assert.deepStrictEqual(requestedNetworks(clip({ socialNetworks: ['seller_telegram', 'telegram'] })), ['telegram', 'seller_telegram']);
    assert.deepStrictEqual(requestedNetworks(clip({ category: 'service' })), ['seller_telegram']);
    assert.deepStrictEqual(requestedNetworks(clip({ socialConsent: false })), []);
    assert.deepStrictEqual(requestedNetworks(clip({ category: 'news' })), [], 'yangilik — kanalga emas, AVA tarmoqlariga ham tushmaydi');
    assert.deepStrictEqual(requestedNetworks(clip({ category: 'ad' })), ['instagram', 'facebook', 'telegram']);
    assert.deepStrictEqual(requestedNetworks(clip({ socialNetworks: [] })), ['instagram', 'facebook', 'youtube', 'telegram'], 'legacy');
  });
  await check('U6 (M1) faqat aniq «seller_telegram» va rozilik v>=2: katta-kichik harf variantlari, v1, versiyasiz, matnli versiya — e\'tiborsiz', async () => {
    for (const odd of ['SELLER_TELEGRAM', 'Seller_Telegram', ' seller_telegram']) {
      assert.deepStrictEqual(requestedNetworks(clip({ socialNetworks: [odd] })), [], odd);
      assert.deepStrictEqual(requestedNetworks(clip({ socialNetworks: [odd, 'telegram'] })), ['telegram'], odd);
    }
    assert.deepStrictEqual(requestedNetworks(clip({ socialConsentVersion: 1 })), []);
    assert.deepStrictEqual(requestedNetworks(clip({ socialConsentVersion: '2' })), []);
    const noVer = clip();
    delete noVer.socialConsentVersion;
    assert.deepStrictEqual(requestedNetworks(noVer), []);
    assert.deepStrictEqual(requestedNetworks(clip({ socialConsentVersion: 1, socialNetworks: ['telegram', 'seller_telegram'] })), ['telegram'],
      'AVA tarmog\'i v1 bilan avvalgidek');
  });

  // ── Улаш ──
  await reset({ token: '' });
  await check('S1 bot sozlanmagan: holat available=false; tayyorlash TG_BOT_UNAVAILABLE; Telegramga so\'rov yo\'q', async () => {
    const s = await call('sellerTgChannelStatus', {}, SELLER);
    assert.deepStrictEqual([s.available, s.botUsername, s.channel.status], [false, '', 'none']);
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'TG_BOT_UNAVAILABLE');
    assert.strictEqual(tg.calls.length, 0);
  });

  await reset();
  await check('S2 holat: bot nomi getMe dan (hardcode yo\'q), kanal yo\'q; login siz — unauthenticated', async () => {
    const s = await call('sellerTgChannelStatus', {}, SELLER);
    assert.deepStrictEqual([s.available, s.botUsername, s.channel.status], [true, 'ava_test_bot', 'none']);
    await assert.rejects(call('sellerTgChannelStatus', {}, null), (e) => e.code === 'unauthenticated');
    await assert.rejects(call('sellerTgChannelPrepare', { username: '@non_shop' }, null), (e) => e.code === 'unauthenticated');
  });

  await check('C1 tayyorlashdagi xatolar: nom, yopiq kanal, topilmadi, guruh, AVA rasmiy kanali, bot admin emas, joylash huquqi yo\'q', async () => {
    await expectCode(call('sellerTgChannelPrepare', { username: 'a b' }, SELLER), 'INVALID_USERNAME');
    await expectCode(call('sellerTgChannelPrepare', { username: 'https://t.me/+xyz' }, SELLER), 'PRIVATE_CHANNEL_UNSUPPORTED');
    await expectCode(call('sellerTgChannelPrepare', { username: '@no_such_chan' }, SELLER), 'CHANNEL_NOT_FOUND');
    await expectCode(call('sellerTgChannelPrepare', { username: '@some_group' }, SELLER), 'NOT_A_CHANNEL');
    await expectCode(call('sellerTgChannelPrepare', { username: '@ava_official' }, SELLER), 'CHANNEL_NOT_ALLOWED');
    tg.members['-1001'] = { status: 'left' };
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'BOT_NOT_ADMIN');
    delete tg.members['-1001'];
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'BOT_NOT_ADMIN');
    tg.members['-1001'] = { status: 'administrator', can_post_messages: false };
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'BOT_NO_POST_RIGHT');
    assert.ok(!(await db.doc(`${tgMod.CHANNELS}/${SELLER}`).get()).exists, 'hech narsa yozilmadi');
  });

  await reset();
  await check('C2 kod beriladi; qayta chaqiruv — o\'sha kod (idempotent); holat pending, chatId ilovaga qaytmaydi', async () => {
    const a = await call('sellerTgChannelPrepare', { username: 'https://t.me/non_shop' }, SELLER);
    const b = await call('sellerTgChannelPrepare', { username: '@NON_SHOP' }, SELLER);
    assert.match(a.channel.code, /^AVA-[A-Z2-9]{6}$/);
    assert.strictEqual(b.channel.code, a.channel.code);
    assert.ok(a.channel.expiresAtMs > Date.now() + 25 * 60 * 1000);
    assert.ok(!('chatId' in a.channel));
    const d = await chanDoc(SELLER);
    assert.deepStrictEqual([d.status, d.chatId, d.username, d.ownerPhone], ['pending', '-1001', 'non_shop', SELLER]);
    const s = await call('sellerTgChannelStatus', {}, SELLER);
    assert.deepStrictEqual([s.channel.status, s.channel.code, s.channel.username], ['pending', a.channel.code, 'non_shop']);
  });

  await check('C3 kod tavsifda yo\'q — CODE_NOT_FOUND, ulanmaydi; kod yozilgach — ulanadi, indeks, kod o\'chadi; takror — o\'sha natija', async () => {
    await expectCode(call('sellerTgChannelConnect', {}, SELLER), 'CODE_NOT_FOUND');
    assert.strictEqual((await chanDoc(SELLER)).status, 'pending');
    assert.ok(!(await chatIdx('-1001')).exists);
    const code = (await chanDoc(SELLER)).code;
    tg.chats['-1001'].description = `Иссиқ нон\n${code}`;
    const r = await call('sellerTgChannelConnect', {}, SELLER);
    assert.deepStrictEqual(r.channel, { status: 'connected', username: 'non_shop', title: 'Нон дўкони' });
    const d = await chanDoc(SELLER);
    assert.strictEqual(d.status, 'connected');
    assert.ok(!('code' in d) && !('codeExpiresAt' in d));
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, SELLER);
    const again = await call('sellerTgChannelConnect', {}, SELLER);
    assert.strictEqual(again.channel.status, 'connected');
  });

  await check('C4 egallash urinishi: boshqa sotuvchi ulangan kanalga kod oladi, lekin kodni tavsifga yoza olmasa — ulanmaydi, egasi o\'zgarmaydi; o\'z kanali bor sotuvchi boshqasini — SELLER_HAS_CHANNEL', async () => {
    const att = await call('sellerTgChannelPrepare', { username: '@non_shop' }, OTHER);
    assert.strictEqual(att.channel.status, 'pending');
    await expectCode(call('sellerTgChannelConnect', {}, OTHER), 'CODE_NOT_FOUND');
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, SELLER);
    assert.strictEqual((await chanDoc(SELLER)).status, 'connected');
    await expectCode(call('sellerTgChannelPrepare', { username: '@alien_shop' }, SELLER), 'SELLER_HAS_CHANNEL');
  });

  await reset();
  await check('C5 egallash: bot admin bo\'lgan BEGONA kanal — kodsiz (yoki egasining boshqa kodi bilan) ulanmaydi', async () => {
    // Haqiqiy egasi kod oldi va tavsifga yozdi, lekin hali ulamadi; tajovuzkor o'z kodini ololadi, lekin tavsifga yoza olmaydi.
    const victim = await call('sellerTgChannelPrepare', { username: '@alien_shop' }, SELLER);
    tg.chats['-1002'].description = victim.channel.code;
    const att = await call('sellerTgChannelPrepare', { username: '@alien_shop' }, OTHER);
    assert.notStrictEqual(att.channel.code, victim.channel.code);
    await expectCode(call('sellerTgChannelConnect', {}, OTHER), 'CODE_NOT_FOUND');
    assert.ok(!(await chatIdx('-1002')).exists);
    const ok = await call('sellerTgChannelConnect', {}, SELLER);
    assert.strictEqual(ok.channel.status, 'connected');
    assert.strictEqual((await chatIdx('-1002')).data().ownerPhone, SELLER);
    await expectCode(call('sellerTgChannelConnect', {}, OTHER), 'CODE_NOT_FOUND');
    assert.strictEqual((await chatIdx('-1002')).data().ownerPhone, SELLER);
  });

  await reset();
  await check('C6 bir vaqtda ikki sotuvchi bitta kanal (ikkala kod ham tavsifda) — faqat BITTA g\'olib', async () => {
    const a = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    const b = await call('sellerTgChannelPrepare', { username: '@non_shop' }, OTHER);
    tg.chats['-1001'].description = `${a.channel.code} ${b.channel.code}`;
    const out = await Promise.allSettled([
      call('sellerTgChannelConnect', {}, SELLER),
      call('sellerTgChannelConnect', {}, OTHER),
    ]);
    // Ikkalasi ham hozirgi egalikni isbotladi (M3: keyingisi o'tkazib oladi) — lekin oxirida BITTA ulangan, indeks unga.
    for (const x of out) if (x.status === 'rejected') throw x.reason;
    const owner = (await chatIdx('-1001')).data().ownerPhone;
    const loser = owner === SELLER ? OTHER : SELLER;
    assert.strictEqual((await chanDoc(owner)).status, 'connected');
    const l = await chanDoc(loser);
    assert.deepStrictEqual([l.status, l.lastErrorCode], ['disconnected', 'CHANNEL_TRANSFERRED']);
  });

  await reset();
  await check('C10 (M3) eskirgan ulanish haqiqiy egani to\'smaydi: yangi sotuvchi kodni tavsifga yozsa — kanal unga o\'tadi, eskisi disconnected/CHANNEL_TRANSFERRED; eskisi kodsiz tiklay olmaydi, posti ketmaydi', async () => {
    await connect(SELLER, '@non_shop', '-1001');
    await db.doc(`${tgMod.CHANNELS}/${SELLER}`).update({ status: 'needs_reconnect' });
    tg.chats['-1001'].description = 'Yangi egasi';
    const r = await connect(OTHER, '@non_shop', '-1001');
    assert.strictEqual(r.channel.status, 'connected');
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, OTHER);
    const old = await chanDoc(SELLER);
    assert.deepStrictEqual([old.status, old.lastErrorCode], ['disconnected', 'CHANNEL_TRANSFERRED']);
    assert.strictEqual((await call('sellerTgChannelStatus', {}, SELLER)).channel.status, 'none');
    // Eski sotuvchi «Qayta tekshirish» qilsa — kodsiz tiklash YO'Q, faqat yangi kod (isbot kerak).
    const again = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    assert.strictEqual(again.channel.status, 'pending');
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, OTHER);
    await db.doc('tv_clips/m3').set(clip());
    const n = sends().length;
    await publish('m3');
    assert.strictEqual((await clipData('m3')).socialPost.networks.seller_telegram.error, 'SELLER_CHANNEL_NOT_CONNECTED');
    assert.strictEqual(sends().length, n);
  });

  await reset();
  await check('C11 (M3) needs_reconnect: indeks boshqaga o\'tgan bo\'lsa kodsiz tiklash ishlamaydi (holat qo\'lda buzilgan bo\'lsa ham)', async () => {
    await connect(SELLER, '@non_shop', '-1001');
    await db.doc(`${tgMod.CHANNELS}/${SELLER}`).update({ status: 'needs_reconnect' });
    await db.doc(`${tgMod.CHATS}/-1001`).set({ ownerPhone: OTHER, chatId: '-1001' });
    const r = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    assert.strictEqual(r.channel.status, 'pending');
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, OTHER);
  });

  await reset();
  await check('C12 (M2) chastota: Prepare soatiga 10 tadan ortiq — SELLER_TG_RATE_LIMIT, Telegramga so\'rov yo\'q; Connect alohida hisob; boshqa sotuvchiga ta\'sir yo\'q', async () => {
    assert.strictEqual(tgMod.RATE_MAX, 10);
    for (let i = 0; i < 10; i += 1) {
      await expectCode(call('sellerTgChannelPrepare', { username: 'a b' }, SELLER), 'INVALID_USERNAME');
    }
    const before = tg.calls.length;
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'SELLER_TG_RATE_LIMIT');
    assert.strictEqual(tg.calls.length, before);
    await expectCode(call('sellerTgChannelConnect', {}, SELLER), 'NO_PENDING_CODE');
    const ok = await call('sellerTgChannelPrepare', { username: '@non_shop' }, OTHER);
    assert.strictEqual(ok.channel.status, 'pending');
    // Oyna o'tgach — yana ruxsat.
    await db.doc(`${tgMod.RATE}/${SELLER}`).set({ prepare: { start: Date.now() - 61 * 60 * 1000, n: 10 } }, { merge: true });
    assert.strictEqual((await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER)).channel.status, 'pending');
  });

  await reset();
  await check('C13 (LOW) Telegram 429/5xx/tarmoq — TG_TRY_LATER («topilmadi/admin emas» emas)', async () => {
    tg.methodFail.getChat = [429, 'Too Many Requests: retry after 3'];
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'TG_TRY_LATER');
    tg.methodFail = { getChatMember: [502, 'Bad Gateway'] };
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'TG_TRY_LATER');
    tg.methodFail = {};
    const a = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    tg.chats['-1001'].description = a.channel.code;
    tg.methodFail.getChat = [500, 'Internal Server Error'];
    await expectCode(call('sellerTgChannelConnect', {}, SELLER), 'TG_TRY_LATER');
    assert.strictEqual((await chanDoc(SELLER)).status, 'pending');
  });

  await reset();
  await check('C7 kod muddati o\'tgan — CODE_EXPIRED; kodsiz ulash — NO_PENDING_CODE; yangi tayyorlash yangi kod beradi', async () => {
    await expectCode(call('sellerTgChannelConnect', {}, SELLER), 'NO_PENDING_CODE');
    const a = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    await db.doc(`${tgMod.CHANNELS}/${SELLER}`).update({ codeExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) });
    tg.chats['-1001'].description = a.channel.code;
    await expectCode(call('sellerTgChannelConnect', {}, SELLER), 'CODE_EXPIRED');
    const s = await call('sellerTgChannelStatus', {}, SELLER);
    assert.strictEqual(s.channel.status, 'none', 'eskirgan kod ko\'rsatilmaydi');
    const b = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    assert.notStrictEqual(b.channel.code, a.channel.code);
  });

  await reset();
  await check('C8 bloklangan do\'kon ulay olmaydi — SHOP_BLOCKED', async () => {
    await db.doc(`tv_shops/${SELLER}`).set({ ownerPhone: SELLER, status: 'blocked', name: 'X' });
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'SHOP_BLOCKED');
  });

  await reset();
  await check('C9 uzish: holat none, indeks o\'chadi; takror — xatosiz; keyin boshqa sotuvchi o\'z kodi bilan ulay oladi', async () => {
    await connect(SELLER, '@non_shop', '-1001');
    const r1 = await call('sellerTgChannelDisconnect', {}, SELLER);
    const r2 = await call('sellerTgChannelDisconnect', {}, SELLER);
    assert.deepStrictEqual([r1.channel.status, r2.channel.status], ['none', 'none']);
    assert.strictEqual((await chanDoc(SELLER)).status, 'disconnected');
    assert.ok(!(await chatIdx('-1001')).exists);
    assert.strictEqual((await call('sellerTgChannelStatus', {}, SELLER)).channel.status, 'none');
    const r = await connect(OTHER, '@non_shop', '-1001');
    assert.strictEqual(r.channel.status, 'connected');
    await call('sellerTgChannelDisconnect', {}, SELLER);
    assert.strictEqual((await chatIdx('-1001')).data().ownerPhone, OTHER, 'eski egasining uzishi yangi egani o\'chirmaydi');
  });

  // ── Жойлаш ──
  await reset();
  await check('P1 ulangan kanalga joylash: chat_id, matn (narx, havola /s/<publicId>, telefon yo\'q), alohida holat va havola', async () => {
    await connect(SELLER, '@non_shop', '-1001');
    await db.doc('tv_clips/p1').set(clip());
    const r = await publish('p1');
    assert.strictEqual(r.result.status, 'posted');
    const s = sends();
    assert.strictEqual(s.length, 1);
    assert.strictEqual(s[0].params.chat_id, '-1001');
    assert.strictEqual(s[0].params.video, 'https://x/v.mp4');
    const shop = (await db.doc(`tv_shops/${SELLER}`).get()).data();
    assert.match(shop.publicId, /^[A-Za-z0-9]{10}$/, 'do\'kon havolasi server tomonda berildi');
    assert.strictEqual(s[0].params.caption,
      `Иссиқ нон\n35 000 сўм\nТандир нон, ҳар куни эрталаб\n🛒 https://master-taxi-gurlan.web.app/s/${shop.publicId}`);
    assert.ok(!s[0].params.caption.includes(SELLER));
    const c = await clipData('p1');
    assert.deepStrictEqual([c.socialPost.networks.seller_telegram.status, c.socialPost.networks.seller_telegram.url],
      ['posted', `https://t.me/non_shop/${tg.nextMessageId}`]);
    assert.deepStrictEqual([c.socialPost.consent.basis, c.socialPost.consent.version, c.socialPost.consent.networks],
      ['explicit', 2, ['seller_telegram']]);
    assert.ok(c.socialPostedAt);
  });

  await check('P2 idempotent: qayta chaqiruv va trigger (active ga o\'tish takrori) — ikkinchi post YO\'Q; do\'kon havolasi o\'zgarmaydi', async () => {
    const before = (await db.doc(`tv_shops/${SELLER}`).get()).data().publicId;
    const r = await publish('p1');
    assert.strictEqual(r.result.skipped, 'already_posted');
    const after = await clipData('p1');
    await fns.onTvClipSocialPublish.run({
      before: { exists: true, data: () => ({ ...after, status: 'pending' }) },
      after: { exists: true, data: () => after },
    }, { params: { clipId: 'p1' } });
    assert.strictEqual(sends().length, 1);
    assert.strictEqual((await db.doc(`tv_shops/${SELLER}`).get()).data().publicId, before);
  });

  await check('P3 rozilik yo\'q / yangilik / ulanmagan sotuvchi — kanalga yuborilmaydi', async () => {
    await db.doc('tv_clips/p3a').set(clip({ socialConsent: false }));
    await db.doc('tv_clips/p3b').set(clip({ category: 'news' }));
    await db.doc('tv_clips/p3c').set(clip({ ownerPhone: OTHER }));
    assert.strictEqual((await publish('p3a')).result.skipped, 'no_networks');
    assert.strictEqual((await publish('p3b')).result.skipped, 'no_networks');
    const r = await publish('p3c');
    assert.strictEqual(r.result.status, 'error');
    const c = await clipData('p3c');
    assert.strictEqual(c.socialPost.networks.seller_telegram.error, 'SELLER_CHANNEL_NOT_CONNECTED');
    assert.strictEqual(sends().length, 1, 'yangi sendVideo yo\'q');
  });

  await check('P4 trigger: klip active bo\'lganda o\'zi joylaydi (AVA rasmiy Telegram + sotuvchi kanali, alohida holatlar)', async () => {
    const d = clip({ socialNetworks: ['telegram', 'seller_telegram'] });
    await db.doc('tv_clips/p4').set(d);
    await fns.onTvClipSocialPublish.run({
      before: { exists: true, data: () => ({ ...d, status: 'pending' }) },
      after: { exists: true, data: () => d },
    }, { params: { clipId: 'p4' } });
    const c = await clipData('p4');
    assert.strictEqual(c.socialPost.status, 'posted');
    assert.strictEqual(c.socialPost.networks.telegram.status, 'posted');
    assert.strictEqual(c.socialPost.networks.seller_telegram.status, 'posted');
    const s = sends().slice(-2);
    assert.deepStrictEqual(s.map((x) => x.params.chat_id), ['@ava_official', '-1001']);
    assert.ok(s[0].params.caption.includes('#AVA'), 'AVA kanali o\'z matni bilan');
  });

  await check('P5 vaqtinchalik xato (429) — kanal ulangan qoladi; admin qayta urinishi joylaydi', async () => {
    await db.doc('tv_clips/p5').set(clip());
    tg.sendFail = [429, 'Too Many Requests: retry after 5'];
    const r = await publish('p5');
    assert.strictEqual(r.result.status, 'error');
    assert.match((await clipData('p5')).socialPost.networks.seller_telegram.error, /^TG_SEND_FAILED/);
    assert.strictEqual((await chanDoc(SELLER)).status, 'connected');
    tg.sendFail = null;
    const r2 = await publish('p5');
    assert.strictEqual(r2.result.status, 'posted');
  });

  await check('P6 bot huquqini yo\'qotdi (403) — kanal needs_reconnect; keyingi joylash Telegramga bormaydi; qayta ulash (kodsiz, ega isbotlangan) — keyin joylanadi', async () => {
    await db.doc('tv_clips/p6').set(clip());
    tg.sendFail = [403, 'Forbidden: bot was kicked from the channel chat'];
    await publish('p6');
    assert.match((await clipData('p6')).socialPost.networks.seller_telegram.error, /^SELLER_CHANNEL_NEEDS_RECONNECT/);
    const d = await chanDoc(SELLER);
    assert.deepStrictEqual([d.status, d.lastErrorCode], ['needs_reconnect', 'TG_RIGHTS_LOST']);
    assert.strictEqual((await call('sellerTgChannelStatus', {}, SELLER)).channel.status, 'needs_reconnect');
    tg.sendFail = null;
    const n = sends().length;
    await publish('p6');
    assert.strictEqual(sends().length, n, 'needs_reconnect da sendVideo yo\'q');
    assert.strictEqual((await clipData('p6')).socialPost.networks.seller_telegram.error, 'SELLER_CHANNEL_NEEDS_RECONNECT');
    // Bot hali ham admin emas — qayta ulash rad etiladi.
    tg.members['-1001'] = { status: 'left' };
    await expectCode(call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER), 'BOT_NOT_ADMIN');
    tg.members['-1001'] = { status: 'administrator', can_post_messages: true };
    const re = await call('sellerTgChannelPrepare', { username: '@non_shop' }, SELLER);
    assert.deepStrictEqual(re.channel, { status: 'connected', username: 'non_shop', title: 'Нон дўкони' });
    assert.ok(!('lastErrorCode' in (await chanDoc(SELLER))));
    assert.strictEqual((await publish('p6')).result.status, 'posted');
  });

  await check('P7 do\'kon bloklangan — SHOP_BLOCKED, yuborilmaydi; uzilgan kanal — SELLER_CHANNEL_NOT_CONNECTED', async () => {
    await db.doc(`tv_shops/${SELLER}`).set({ status: 'blocked' }, { merge: true });
    await db.doc('tv_clips/p7').set(clip());
    const n = sends().length;
    await publish('p7');
    assert.strictEqual((await clipData('p7')).socialPost.networks.seller_telegram.error, 'SHOP_BLOCKED');
    await db.doc(`tv_shops/${SELLER}`).set({ status: 'active' }, { merge: true });
    await call('sellerTgChannelDisconnect', {}, SELLER);
    await publish('p7');
    assert.strictEqual((await clipData('p7')).socialPost.networks.seller_telegram.error, 'SELLER_CHANNEL_NOT_CONNECTED');
    assert.strictEqual(sends().length, n);
  });

  await reset();
  await check('P8 (LOW) mahsulot belgisi faqat AVA tarmoqlaridan: kanal xatosi AVA joylashini «buzmaydi»; faqat kanal — belgi yo\'q; status/socialPostedAt — barcha tarmoqlardan (avvalgidek)', async () => {
    await db.doc('tv_shop_items/i1').set({ ownerPhone: SELLER, title: 'Non', status: 'active' });
    await db.doc('tv_shop_items/i2').set({ ownerPhone: SELLER, title: 'Non', status: 'active' });
    await db.doc('tv_clips/p8a').set(clip({ socialNetworks: ['telegram', 'seller_telegram'], shopItemId: 'i1' }));
    await publish('p8a'); // kanal ulanmagan — kanal xato, AVA Telegram posted
    const a = await clipData('p8a');
    assert.deepStrictEqual([a.socialPost.status, a.socialPost.networks.telegram.status], ['partial', 'posted']);
    assert.ok(!a.socialPostedAt, 'klip belgisi avvalgidek: hammasi chiqmaguncha yo\'q (admin qayta urinadi)');
    assert.ok((await db.doc('tv_shop_items/i1').get()).data().socialPostedAt, 'mahsulot: AVA sahifalariga chiqdi');
    await connect(SELLER, '@non_shop', '-1001');
    await db.doc('tv_clips/p8b').set(clip({ shopItemId: 'i2' }));
    await publish('p8b');
    assert.strictEqual((await clipData('p8b')).socialPost.status, 'posted');
    assert.ok(!(await db.doc('tv_shop_items/i2').get()).data().socialPostedAt, 'faqat kanal — AVA belgisi yo\'q');
  });

  await check('X1 bot tokeni hech qayerga yozilmaydi (sotuvchi hujjati, klip)', async () => {
    const all = JSON.stringify([
      (await db.collection(tgMod.CHANNELS).get()).docs.map((x) => x.data()),
      (await db.collection('tv_clips').get()).docs.map((x) => x.data()),
    ]);
    assert.ok(!all.includes(TOKEN));
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
