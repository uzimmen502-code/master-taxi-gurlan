/**
 * `support_chats` va uning `messages` subkolleksiyasi — Firestore rules.
 *
 * Muammo:
 *   messages:  read: if true          — 18 ta shaxsiy yordam suhbati ochiq
 *              create: AUTH YO'Q      — har kim xabar qo'sha oladi
 *              update: if true        — har kim ISTALGAN xabarni qayta yoza oladi
 *
 * Ildiz sababi ota qoidada: `request.auth.uid == chatId`. Lekin `chatId` —
 * foydalanuvchi TELEFON raqami (izohning o'zi shunday deydi), `auth.uid` esa
 * Phone Auth'da Firebase bergan tasodifiy satr. Ya'ni shart oddiy
 * foydalanuvchi uchun hech qachon bajarilmaydi — shuning uchun subkolleksiya
 * butunlay ochib qo'yilgan.
 *
 * Tuzatish: ota qoidaga `isOwner(chatId)` QO'SHILADI (eski
 * `auth.uid == chatId` yo'li SAQLANADI — orqaga moslik, 26-qoida), va
 * subkolleksiya ham shu egalikka bog'lanadi.
 *
 * Oqim (lib/repositories/chat_repository.dart:44): klient avval ota
 * hujjatga `set(merge)` yozadi (`lastMessage`, `lastFromAdmin`), keyin
 * `messages` ga qo'shadi. Xabarda `fromAdmin: false` — `true` ni faqat
 * Admin SDK yozadi (`appendSystemSupportChatMessage`, functions/index.js:710).
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-rules-test \
 *     "node functions/test/support_chat_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN_PHONE = '998901112233';
const OWNER = '998905556677';
const STRANGER = '998904445566';
const MSG_ID = 'msg1';

function msg() {
  return {
    text: 'Salom, yordam kerak',
    fromAdmin: false,
    fromPhone: OWNER,
    fromName: 'Aziz',
    createdAt: new Date(),
    read: false,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-support-chat',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({name, pass, detail});
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  }

  async function check(name, fn) {
    try {
      await fn();
      record(name, true);
    } catch (e) {
      record(name, false, e.message);
    }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN_PHONE).set({role: 'admin'});
    await db.collection('support_chats').doc(OWNER).set({
      userPhone: OWNER, lastMessage: 'Salom', lastFromAdmin: false,
      updatedAt: new Date(),
    });
    await db.collection('support_chats').doc(OWNER)
        .collection('messages').doc(MSG_ID).set(msg());
  });

  function ctxFor(phone) {
    return testEnv.authenticatedContext(`uid_${phone}`, {
      phone_number: '+' + phone,
    });
  }
  /** Eski yo'l: auth.uid AYNAN chatId (orqaga moslik tekshiruvi). */
  const legacyCtx = testEnv.authenticatedContext(OWNER);

  const chat = (db) => db.collection('support_chats').doc(OWNER);
  const msgs = (db) => chat(db).collection('messages');

  const unauth = testEnv.unauthenticatedContext().firestore();
  const stranger = ctxFor(STRANGER).firestore();
  const owner = ctxFor(OWNER).firestore();
  const adminDb = ctxFor(ADMIN_PHONE).firestore();
  const legacy = legacyCtx.firestore();

  // ── Teshik: shaxsiy suhbatlar ochiq edi ─────────────────────────────
  await check(
      'autentifikatsiyasiz xabarlarni o\'qiy olmaydi',
      () => assertFails(msgs(unauth).doc(MSG_ID).get()));

  await check(
      'begona foydalanuvchi birovning suhbatini o\'qiy olmaydi',
      () => assertFails(msgs(stranger).orderBy('createdAt').get()));

  await check(
      'begona foydalanuvchi ota chat hujjatini o\'qiy olmaydi',
      () => assertFails(chat(stranger).get()));

  await check(
      'autentifikatsiyasiz xabar qo\'sha olmaydi',
      () => assertFails(msgs(unauth).doc('x1').set(msg())));

  await check(
      'begona foydalanuvchi birovning suhbatiga xabar qo\'sha olmaydi',
      () => assertFails(msgs(stranger).doc('x2').set(msg())));

  await check(
      'begona foydalanuvchi mavjud xabarni QAYTA YOZA olmaydi',
      () => assertFails(msgs(stranger).doc(MSG_ID).update({text: 'buzilgan'})));

  await check(
      'autentifikatsiyasiz xabarni qayta yoza olmaydi',
      () => assertFails(msgs(unauth).doc(MSG_ID).update({text: 'buzilgan'})));

  // ── Egasi va admin oqimi ────────────────────────────────────────────
  await check(
      'egasi o\'z suhbatini o\'qiydi',
      () => assertSucceeds(msgs(owner).orderBy('createdAt').get()));

  await check(
      'egasi ota chat hujjatini o\'qiydi (watchUnreadFromAdmin)',
      () => assertSucceeds(chat(owner).get()));

  await check(
      'egasi ota hujjatga set(merge) yozadi (sendMessage:52)',
      () => assertSucceeds(chat(owner).set({
        userPhone: OWNER, lastMessage: 'Yangi', lastFromAdmin: false,
        updatedAt: new Date(),
      }, {merge: true})));

  await check(
      'egasi xabar qo\'shadi (sendMessage:59)',
      () => assertSucceeds(msgs(owner).doc('own_msg').set(msg())));

  await check(
      'egasi xabarni o\'qilgan deb belgilaydi',
      () => assertSucceeds(msgs(owner).doc(MSG_ID).update({read: true})));

  await check(
      'admin suhbatni o\'qiydi',
      () => assertSucceeds(msgs(adminDb).orderBy('createdAt').get()));

  await check(
      'admin javob yozadi',
      () => assertSucceeds(msgs(adminDb).doc('admin_msg').set(msg())));

  await check(
      'ORQAGA MOSLIK: auth.uid == chatId bo\'lgan eski yo\'l hamon ishlaydi',
      () => assertSucceeds(msgs(legacy).doc(MSG_ID).get()));

  // ── Chegara holatlari ───────────────────────────────────────────────
  await check(
      'egasi fromAdmin: true bilan yoza olmaydi',
      () => assertFails(msgs(owner).doc('x3').set({...msg(), fromAdmin: true})));

  await check(
      'bo\'sh matn bilan yoza olmaydi',
      () => assertFails(msgs(owner).doc('x4').set({...msg(), text: ''})));

  await check(
      'hech kim xabarni o\'chira olmaydi',
      () => assertFails(msgs(adminDb).doc(MSG_ID).delete()));

  await testEnv.cleanup();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} support_chats rules checks passed.`);
  if (failed.length) {
    console.log('FAILED:', failed.map((f) => f.name).join(', '));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('FATAL', e);
  process.exitCode = 1;
});
