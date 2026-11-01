/**
 * Улгуржи/Хитой «Буюртма ёзиш» чати — Firestore rules (functions/deal_chats.js).
 *
 *   (RULES_FILE=build/firestore_rules/firestore.rules — deploy qilinadigan izohsiz nusxa uchun)
 *   firebase emulators:exec --only firestore --project demo-deal-chat-rules \
 *     "node test/deal_chats_rules.test.js"
 *
 * Qulflanadi: chat va xabarlarni FAQAT a'zolar o'qiydi (get + `members array-contains` list);
 * begona, anonim (telefonsiz) va loginsiz — rad; filtrsiz list rad; hamma yozuv (a'zo ham) yopiq;
 * `deal_chat_usage` hech kimga ochiq emas.
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const BUYER = '998914000001';
const SELLER = '998914000002';
const OTHER = '998914000003';
const ADMIN = '998914000009';
const CHAT = `p1_${BUYER}`;

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-deal-chat-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anonSession = () => testEnv.authenticatedContext('anon_x', {}).firestore();
  const noAuth = () => testEnv.unauthenticatedContext().firestore();

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`deal_chats/${CHAT}`).set({
      members: [BUYER, SELLER], buyerId: BUYER, sellerId: SELLER, productId: 'p1',
      lastMessage: 'salom', lastFrom: BUYER, lastAt: new Date(), unread: { [BUYER]: 0, [SELLER]: 1 },
    });
    await db.doc(`deal_chats/${CHAT}/messages/m1`).set({ from: BUYER, text: 'salom', at: new Date(), clientId: 'c1' });
    await db.doc(`deal_chats/p2_${OTHER}`).set({ members: [OTHER, SELLER], lastAt: new Date() });
    await db.doc(`deal_chat_usage/${BUYER}`).set({ minuteKey: 1, minuteCount: 1 });
  });

  await check('R1 xaridor va sotuvchi chatni get qiladi', async () => {
    await assertSucceeds(as(BUYER).doc(`deal_chats/${CHAT}`).get());
    await assertSucceeds(as(SELLER).doc(`deal_chats/${CHAT}`).get());
  });

  await check('R2 list: o\'z raqami bilan array-contains + orderBy(lastAt) — o\'tadi (ikkala tomon)', async () => {
    await assertSucceeds(as(BUYER).collection('deal_chats').where('members', 'array-contains', BUYER).orderBy('lastAt', 'desc').get());
    const s = await assertSucceeds(as(SELLER).collection('deal_chats').where('members', 'array-contains', SELLER).get());
    if (s.size !== 2) throw new Error(`sotuvchi 2 chat ko'rishi kerak, ko'rdi ${s.size}`);
  });

  await check('R3 begona: get rad; boshqaning raqami bilan list rad; filtrsiz list rad', async () => {
    await assertFails(as(OTHER).doc(`deal_chats/${CHAT}`).get());
    await assertFails(as(OTHER).collection('deal_chats').where('members', 'array-contains', BUYER).get());
    await assertFails(as(BUYER).collection('deal_chats').get());
  });

  await check('R4 anonim sessiya (telefonsiz) va loginsiz — rad', async () => {
    await assertFails(anonSession().doc(`deal_chats/${CHAT}`).get());
    await assertFails(noAuth().doc(`deal_chats/${CHAT}`).get());
    await assertFails(noAuth().collection(`deal_chats/${CHAT}/messages`).get());
  });

  await check('R5 xabarlar: a\'zolar get/list (orderBy at); begona va anonim rad', async () => {
    await assertSucceeds(as(BUYER).doc(`deal_chats/${CHAT}/messages/m1`).get());
    await assertSucceeds(as(SELLER).collection(`deal_chats/${CHAT}/messages`).orderBy('at').get());
    await assertFails(as(OTHER).collection(`deal_chats/${CHAT}/messages`).get());
    await assertFails(as(OTHER).doc(`deal_chats/${CHAT}/messages/m1`).get());
    await assertFails(anonSession().collection(`deal_chats/${CHAT}/messages`).get());
  });

  await check('R6 yozuv yopiq: a\'zo ham chat/xabar yarata, o\'zgartira, o\'chira olmaydi', async () => {
    await assertFails(as(BUYER).doc(`deal_chats/${CHAT}`).update({ [`unread.${SELLER}`]: 0 }));
    await assertFails(as(SELLER).doc(`deal_chats/${CHAT}`).delete());
    await assertFails(as(BUYER).doc(`deal_chats/p9_${BUYER}`).set({ members: [BUYER] }));
    await assertFails(as(BUYER).collection(`deal_chats/${CHAT}/messages`).add({ from: BUYER, text: 'x' }));
    await assertFails(as(BUYER).doc(`deal_chats/${CHAT}/messages/m1`).update({ text: 'tahrir' }));
  });

  await check('R7 yo\'q chat xabarlari — rad (get() xatosi ruxsat bermaydi)', async () => {
    await assertFails(as(BUYER).collection(`deal_chats/p404_${BUYER}/messages`).get());
  });

  await check('R8 deal_chat_usage: egasi ham, admin ham o\'qiy/yoza olmaydi', async () => {
    await assertFails(as(BUYER).doc(`deal_chat_usage/${BUYER}`).get());
    await assertFails(as(BUYER).doc(`deal_chat_usage/${BUYER}`).set({ minuteKey: 0, minuteCount: 0 }));
    await assertFails(as(ADMIN).doc(`deal_chat_usage/${BUYER}`).get());
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
