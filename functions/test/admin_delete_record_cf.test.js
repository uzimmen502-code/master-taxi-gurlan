/**
 * ADMIN — yozuvni o'chirish callable (`adminDeleteRecord`): risk_event, admin_news, support_message, support_chat.
 * HAQIQIY `functions/index.js`, Firestore Emulator. Rol, validatsiya, audit snapshot (PII yo'q), idempotentlik,
 * 400 tadan batch (450 xabar), `partial` chegarasi, oxirgi xabar o'chirilganda `lastMessage` yangilanishi.
 *
 *   firebase emulators:exec --only firestore --project demo-admin-delete \
 *     "node functions/test/admin_delete_record_cf.test.js"
 *
 * (Emulator porti `FIRESTORE_EMULATOR_HOST` bilan beriladi; berilmasa 127.0.0.1:18095.)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18095';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-admin-delete';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { attachAdminDeleteRecord } = require('../admin_delete_record');

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;
const ADMIN = '998915000001';
const SUPER = '998915000002';
const DISPATCHER = '998915000003';
const USER = '998912000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.adminDeleteRecord.run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
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
const auditsOf = async (recordId) => (await db.collection('admin_audit').where('recordId', '==', recordId).get()).docs.map((d) => d.data());
const exists = async (path) => (await db.doc(path).get()).exists;

async function seedMessages(chatId, n, { startMs = 1_700_000_000_000 } = {}) {
  for (let i = 0; i < n; i += 400) {
    const batch = db.batch();
    for (let j = i; j < Math.min(n, i + 400); j += 1) {
      batch.set(db.collection('support_chats').doc(chatId).collection('messages').doc(`m${String(j).padStart(4, '0')}`), {
        text: `maxfiy matn ${j}`, fromAdmin: j % 2 === 1, fromPhone: j % 2 === 1 ? '' : chatId, createdAt: Timestamp.fromMillis(startMs + j * 1000), read: false,
      });
    }
    await batch.commit();
  }
}

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  await check('A1 oddiy foydalanuvchi, dispatcher va kirmagan rad etiladi; yozuv saqlanadi, audit yo\'q', async () => {
    await db.collection('risk_events').doc('r_auth').set({ type: 'x', severity: 'low', status: 'open', userId: USER });
    await assert.rejects(call({ kind: 'risk_event', id: 'r_auth' }, USER), (e) => e.code === 'permission-denied');
    await assert.rejects(call({ kind: 'risk_event', id: 'r_auth' }, DISPATCHER), (e) => e.code === 'permission-denied');
    await assert.rejects(fns.adminDeleteRecord.run({ kind: 'risk_event', id: 'r_auth' }, {}), (e) => e.code === 'unauthenticated');
    assert.ok(await exists('risk_events/r_auth'));
    assert.strictEqual((await auditsOf('r_auth')).length, 0);
  });

  await check('A2 validatsiya: noma\'lum kind, bo\'sh/yo\'lli id, chatId yo\'q, uzun sabab', async () => {
    await expectCode(call({ kind: 'wallet', id: 'a' }, ADMIN), 'KIND_INVALID');
    await expectCode(call({ id: 'a' }, ADMIN), 'KIND_INVALID');
    await expectCode(call({ kind: 'risk_event', id: '' }, ADMIN), 'ID_INVALID');
    await expectCode(call({ kind: 'risk_event', id: 'a/b' }, ADMIN), 'ID_INVALID');
    await expectCode(call({ kind: 'risk_event', id: 5 }, ADMIN), 'ID_INVALID');
    await expectCode(call({ kind: 'support_message', id: 'm1' }, ADMIN), 'CHAT_ID_INVALID');
    await expectCode(call({ kind: 'support_message', id: 'm1', chatId: 'x/y' }, ADMIN), 'CHAT_ID_INVALID');
    await expectCode(call({ kind: 'risk_event', id: 'r_auth', reason: 'x'.repeat(301) }, ADMIN), 'REASON_TOO_LONG');
    assert.ok(await exists('risk_events/r_auth'));
  });

  await check('R1 risk_event: o\'chadi, bitta audit (to\'liq nusxa); superadmin ham mumkin; takroriy — deleted:false, audit ko\'paymaydi', async () => {
    await db.collection('risk_events').doc('r1').set({
      type: 'same_device_new_phone', severity: 'high', status: 'open', userId: USER, deviceId: 'dev-1', message: 'Qurilma bir', meta: { a: 1 }, createdAt: Timestamp.fromMillis(1_700_000_000_000),
    });
    const r = await call({ kind: 'risk_event', id: 'r1', reason: 'eski signal' }, SUPER);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists('risk_events/r1')));
    const a = await auditsOf('r1');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].kind, 'admin_record_deleted');
    assert.strictEqual(a[0].recordKind, 'risk_event');
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].reason, 'eski signal');
    assert.ok(a[0].at);
    assert.deepStrictEqual([a[0].snapshot.type, a[0].snapshot.severity, a[0].snapshot.status, a[0].snapshot.userId, a[0].snapshot.deviceId, a[0].snapshot.message, a[0].snapshot.meta],
      ['same_device_new_phone', 'high', 'open', USER, 'dev-1', 'Qurilma bir', { a: 1 }]);
    assert.ok(a[0].snapshot.createdAt);
    const again = await call({ kind: 'risk_event', id: 'r1' }, ADMIN);
    assert.deepStrictEqual(again, { ok: true, deleted: false });
    assert.strictEqual((await auditsOf('r1')).length, 1);
  });

  await check('N1 admin_news: o\'chadi; audit snapshot sarlavha/kategoriya/auditoriya BOR, matn (body) YO\'Q; takroriy — o\'zgarishsiz', async () => {
    await db.collection('admin_news').doc('n1').set({
      title: 'Aksiya', body: 'MAXFIY-BODY-MATNI', category: 'promo', audience: 'user', targetUserId: USER, source: 'admin', createdAt: Timestamp.fromMillis(1_700_000_000_000), priority: 3,
    });
    const r = await call({ kind: 'admin_news', id: 'n1' }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists('admin_news/n1')));
    const a = await auditsOf('n1');
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual([a[0].snapshot.title, a[0].snapshot.category, a[0].snapshot.audience, a[0].snapshot.targetUserId, a[0].snapshot.source],
      ['Aksiya', 'promo', 'user', USER, 'admin']);
    assert.ok(!JSON.stringify(a[0]).includes('MAXFIY-BODY-MATNI'), 'body audit\'ga tushmasligi kerak');
    assert.strictEqual(a[0].reason, '');
    assert.deepStrictEqual(await call({ kind: 'admin_news', id: 'n1' }, ADMIN), { ok: true, deleted: false });
    assert.strictEqual((await auditsOf('n1')).length, 1);
  });

  await check('M1 support_message: o\'chadi; audit\'da matn YO\'Q (faqat uzunlik); takroriy — deleted:false', async () => {
    const chat = '998901110001';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, lastMessage: 'oxirgi', lastFromAdmin: false });
    await seedMessages(chat, 3); // m0000 (mijoz), m0001 (admin), m0002 (mijoz)
    const r = await call({ kind: 'support_message', chatId: chat, id: 'm0000' }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists(`support_chats/${chat}/messages/m0000`)));
    assert.ok(await exists(`support_chats/${chat}/messages/m0001`));
    const a = await auditsOf('m0000');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].recordKind, 'support_message');
    assert.strictEqual(a[0].chatId, chat);
    assert.deepStrictEqual([a[0].snapshot.fromAdmin, a[0].snapshot.fromPhone, a[0].snapshot.textLength], [false, chat, 'maxfiy matn 0'.length]);
    assert.ok(a[0].snapshot.createdAt);
    assert.ok(!JSON.stringify(a[0]).includes('maxfiy matn'), 'xabar matni audit\'ga tushmasligi kerak');
    assert.deepStrictEqual(await call({ kind: 'support_message', chatId: chat, id: 'm0000' }, ADMIN), { ok: true, deleted: false });
    assert.strictEqual((await auditsOf('m0000')).length, 1);
    // yangi bo'lmagan xabar o'chirilganda chat hujjati o'zgarmaydi
    const chatDoc = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.strictEqual(chatDoc.lastMessage, 'oxirgi');
  });

  await check('M2 eng yangi xabar o\'chirilsa lastMessage qolgan eng yangisiga o\'tadi; lastFromAdmin false → true bo\'lmaydi; awaitingAdmin tegilmaydi', async () => {
    const chat = '998901110002';
    const awaitAt = Timestamp.fromMillis(1_700_000_001_000);
    await db.collection('support_chats').doc(chat).set({
      userPhone: chat, lastMessage: 'maxfiy matn 2', lastFromAdmin: false, awaitingAdmin: true, awaitingAdminMsgAt: awaitAt,
    });
    await seedMessages(chat, 3); // m0001 admin
    await call({ kind: 'support_message', chatId: chat, id: 'm0002' }, ADMIN);
    let c = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.strictEqual(c.lastMessage, 'maxfiy matn 1');
    assert.strictEqual(c.lastFromAdmin, false, 'mijoz o\'qigan chatda yolg\'on "o\'qilmagan" belgisi yonmasin');
    assert.strictEqual(c.awaitingAdmin, true);
    assert.ok(c.awaitingAdminMsgAt.isEqual(awaitAt));
    // lastFromAdmin true bo'lsa va qolgan eng yangisi admin xabari bo'lsa — true qoladi; keyin mijoz xabari qolsa — false
    await db.doc(`support_chats/${chat}`).update({ lastFromAdmin: true });
    await call({ kind: 'support_message', chatId: chat, id: 'm0001' }, ADMIN); // qolgan: m0000 (mijoz)
    c = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.deepStrictEqual([c.lastMessage, c.lastFromAdmin], ['maxfiy matn 0', false]);
    // oxirgisi ham o'chirilsa — bo'sh
    await call({ kind: 'support_message', chatId: chat, id: 'm0000' }, ADMIN);
    c = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.deepStrictEqual([c.lastMessage, c.lastFromAdmin], ['', false]);
    assert.strictEqual(c.awaitingAdmin, true);
  });

  await check('M3 lastFromAdmin true va qolgan eng yangisi admin xabari — true saqlanadi', async () => {
    const chat = '998901110003';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, lastMessage: 'x', lastFromAdmin: true });
    await seedMessages(chat, 3); // m0002 mijoz (eng yangi), m0001 admin
    await call({ kind: 'support_message', chatId: chat, id: 'm0002' }, ADMIN);
    const c = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.deepStrictEqual([c.lastMessage, c.lastFromAdmin], ['maxfiy matn 1', true]);
  });

  await check('C1 support_chat: 450 xabar (400 + 50 batch) va chat hujjati o\'chadi; bitta audit (messageCount, matn yo\'q); takroriy — deleted:false', async () => {
    const chat = '998901110004';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, lastMessage: 'MAXFIY-OXIRGI', lastFromAdmin: false, awaitingAdmin: true, updatedAt: Timestamp.fromMillis(1_700_000_000_000) });
    await seedMessages(chat, 450);
    const r = await call({ kind: 'support_chat', id: chat, reason: 'mijoz so\'radi' }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists(`support_chats/${chat}`)));
    assert.strictEqual((await db.collection('support_chats').doc(chat).collection('messages').count().get()).data().count, 0);
    const a = await auditsOf(chat);
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].recordKind, 'support_chat');
    assert.strictEqual(a[0].snapshot.messageCount, 450);
    assert.strictEqual(a[0].snapshot.userPhone, chat);
    assert.strictEqual(a[0].reason, 'mijoz so\'radi');
    assert.ok(!JSON.stringify(a[0]).includes('MAXFIY'), 'chat matni audit\'ga tushmasligi kerak');
    assert.deepStrictEqual(await call({ kind: 'support_chat', id: chat }, ADMIN), { ok: true, deleted: false });
    assert.strictEqual((await auditsOf(chat)).length, 1);
  });

  await check('C2 chat hujjati yo\'q, lekin xabarlar qolgan (yetim) — xabarlar o\'chadi', async () => {
    const chat = '998901110005';
    await seedMessages(chat, 5);
    const r = await call({ kind: 'support_chat', id: chat }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.strictEqual((await db.collection('support_chats').doc(chat).collection('messages').count().get()).data().count, 0);
    assert.strictEqual((await auditsOf(chat)).length, 1);
  });

  await check('C3 chegara: maxBatches=1 va 450 xabar → partial:true, chat hujjati qoladi; qayta bosilsa tugaydi (2-audit qolgan 50 uchun)', async () => {
    const local = {};
    attachAdminDeleteRecord(local, { functions, db, admin, requireCallerRoles: async () => ADMIN, maxBatches: 1 });
    const chat = '998901110006';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, lastMessage: 'x', lastFromAdmin: false });
    await seedMessages(chat, 450);
    const r1 = await local.adminDeleteRecord.run({ kind: 'support_chat', id: chat }, ctxOf(ADMIN));
    assert.deepStrictEqual(r1, { ok: true, deleted: true, partial: true });
    assert.ok(await exists(`support_chats/${chat}`), 'chat hujjati partial\'da saqlanadi');
    assert.strictEqual((await db.collection('support_chats').doc(chat).collection('messages').count().get()).data().count, 50);
    const r2 = await local.adminDeleteRecord.run({ kind: 'support_chat', id: chat }, ctxOf(ADMIN));
    assert.deepStrictEqual(r2, { ok: true, deleted: true });
    assert.ok(!(await exists(`support_chats/${chat}`)));
    const a = await auditsOf(chat);
    assert.deepStrictEqual(a.map((x) => x.snapshot.messageCount).sort((x, y) => y - x), [450, 50]);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error('Error:', e); process.exit(1); });
