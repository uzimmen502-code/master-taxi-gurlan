/**
 * ADMIN — HAQIQIY o'chirish callable (`adminDeleteRecord`), siyosat 2026-10-20: faqat SUPERADMIN, faqat
 *   - support_chat: shaxsiy ma'lumotni o'chirish talabi (sabab >= 10 belgi) + chat avval ARXIVGA olingan;
 *   - risk_event: status 'resolved' va resolvedAt 365 kundan eski.
 * `admin_news` / `support_message` → KIND_INVALID. HAQIQIY `functions/index.js`, Firestore Emulator.
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
const DAY = 24 * 60 * 60 * 1000;
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (data, who) => fns.adminDeleteRecord.run(data, ctxOf(who));
const REASON = 'mijoz shaxsiy malumotini ochirishni talab qildi';

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
const msgCount = async (chat) => (await db.collection('support_chats').doc(chat).collection('messages').count().get()).data().count;

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
/** Arxivlangan chat hujjati: updatedAt < adminArchivedAt. */
const archivedChat = (chat, extra = {}) => db.collection('support_chats').doc(chat).set({
  userPhone: chat, lastMessage: 'MAXFIY-OXIRGI', lastFromAdmin: false, awaitingAdmin: true,
  updatedAt: Timestamp.fromMillis(1_700_000_000_000), adminArchivedAt: Timestamp.fromMillis(1_700_000_100_000), adminArchivedBy: ADMIN, ...extra,
});

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  await check('A1 oddiy foydalanuvchi, dispatcher, kirmagan VA oddiy admin rad etiladi (faqat superadmin); yozuv saqlanadi, audit yo\'q', async () => {
    const chat = '998901119001';
    await archivedChat(chat);
    await seedMessages(chat, 2);
    for (const who of [USER, DISPATCHER]) {
      await assert.rejects(call({ kind: 'support_chat', id: chat, reason: REASON }, who), (e) => e.code === 'permission-denied');
    }
    await assert.rejects(fns.adminDeleteRecord.run({ kind: 'support_chat', id: chat, reason: REASON }, {}), (e) => e.code === 'unauthenticated');
    // oddiy admin: support_chat ham, risk_event ham — permission-denied
    await assert.rejects(call({ kind: 'support_chat', id: chat, reason: REASON }, ADMIN), (e) => e.code === 'permission-denied');
    await assert.rejects(call({ kind: 'risk_event', id: 'r_x' }, ADMIN), (e) => e.code === 'permission-denied');
    assert.ok(await exists(`support_chats/${chat}`));
    assert.strictEqual(await msgCount(chat), 2);
    assert.strictEqual((await auditsOf(chat)).length, 0);
  });

  await check('A2 validatsiya: noma\'lum kind; admin_news va support_message endi KIND_INVALID (admin va superadmin uchun ham); id; sabab', async () => {
    for (const who of [ADMIN, SUPER]) {
      await expectCode(call({ kind: 'wallet', id: 'a' }, who), 'KIND_INVALID');
      await expectCode(call({ id: 'a' }, who), 'KIND_INVALID');
      await expectCode(call({ kind: 'admin_news', id: 'n1' }, who), 'KIND_INVALID');
      await expectCode(call({ kind: 'support_message', id: 'm1', chatId: '998901110001' }, who), 'KIND_INVALID');
    }
    await expectCode(call({ kind: 'risk_event', id: '' }, SUPER), 'ID_INVALID');
    await expectCode(call({ kind: 'risk_event', id: 'a/b' }, SUPER), 'ID_INVALID');
    await expectCode(call({ kind: 'support_chat', id: 5, reason: REASON }, SUPER), 'ID_INVALID');
    await expectCode(call({ kind: 'support_chat', id: 'x', reason: 'x'.repeat(301) }, SUPER), 'REASON_TOO_LONG');
  });

  await check('N0 admin_news hujjati KIND_INVALID bilan rad etilganda o\'chmaydi', async () => {
    await db.collection('admin_news').doc('n_keep').set({ title: 'Aksiya', body: 'x', category: 'promo', audience: 'all', targetUserId: '' });
    await expectCode(call({ kind: 'admin_news', id: 'n_keep' }, SUPER), 'KIND_INVALID');
    assert.ok(await exists('admin_news/n_keep'));
    assert.strictEqual((await auditsOf('n_keep')).length, 0);
  });

  await check('R1 risk_event: ochiq signal o\'chirilmaydi (RISK_EVENT_RETENTION)', async () => {
    await db.collection('risk_events').doc('r_open').set({ type: 'x', severity: 'low', status: 'open', userId: USER, createdAt: Timestamp.fromMillis(Date.now() - 800 * DAY) });
    await expectCode(call({ kind: 'risk_event', id: 'r_open' }, SUPER), 'RISK_EVENT_RETENTION');
    assert.ok(await exists('risk_events/r_open'));
    assert.strictEqual((await auditsOf('r_open')).length, 0);
  });

  await check('R2 risk_event: resolved, lekin resolvedAt yo\'q / 10 kun / 364 kun → RISK_EVENT_RETENTION; 366 kun → o\'chadi', async () => {
    await db.collection('risk_events').doc('r_nots').set({ type: 'x', status: 'resolved' });
    await db.collection('risk_events').doc('r_10d').set({ type: 'x', status: 'resolved', resolvedAt: Timestamp.fromMillis(Date.now() - 10 * DAY) });
    await db.collection('risk_events').doc('r_364d').set({ type: 'x', status: 'resolved', resolvedAt: Timestamp.fromMillis(Date.now() - 364 * DAY) });
    for (const id of ['r_nots', 'r_10d', 'r_364d']) {
      await expectCode(call({ kind: 'risk_event', id }, SUPER), 'RISK_EVENT_RETENTION');
      assert.ok(await exists(`risk_events/${id}`), id);
      assert.strictEqual((await auditsOf(id)).length, 0, id);
    }
    await db.collection('risk_events').doc('r_366d').set({
      type: 'same_device_new_phone', severity: 'high', status: 'resolved', userId: USER, deviceId: 'dev-1', message: 'Qurilma bir', meta: { a: 1 },
      createdAt: Timestamp.fromMillis(Date.now() - 400 * DAY), resolvedAt: Timestamp.fromMillis(Date.now() - 366 * DAY), resolvedBy: '+998915000009',
    });
    const r = await call({ kind: 'risk_event', id: 'r_366d', reason: 'muddati otgan' }, SUPER);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists('risk_events/r_366d')));
    const a = await auditsOf('r_366d');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].kind, 'admin_record_deleted');
    assert.strictEqual(a[0].recordKind, 'risk_event');
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].reason, 'muddati otgan');
    assert.deepStrictEqual([a[0].snapshot.type, a[0].snapshot.status, a[0].snapshot.userId, a[0].snapshot.deviceId, a[0].snapshot.meta], ['same_device_new_phone', 'resolved', USER, 'dev-1', { a: 1 }]);
    assert.ok(a[0].at);
    // takroriy: deleted:false, audit ko'paymaydi
    assert.deepStrictEqual(await call({ kind: 'risk_event', id: 'r_366d' }, SUPER), { ok: true, deleted: false });
    assert.strictEqual((await auditsOf('r_366d')).length, 1);
  });

  await check('C1 support_chat: sabab yo\'q / 9 belgi → REASON_REQUIRED (chat saqlanadi); 10 belgi chegara arxivga qadar o\'tadi', async () => {
    const chat = '998901119002';
    await archivedChat(chat);
    await seedMessages(chat, 2);
    await expectCode(call({ kind: 'support_chat', id: chat }, SUPER), 'REASON_REQUIRED');
    await expectCode(call({ kind: 'support_chat', id: chat, reason: '   ' }, SUPER), 'REASON_REQUIRED');
    await expectCode(call({ kind: 'support_chat', id: chat, reason: '123456789' }, SUPER), 'REASON_REQUIRED');
    assert.ok(await exists(`support_chats/${chat}`));
    assert.strictEqual(await msgCount(chat), 2);
    assert.strictEqual((await auditsOf(chat)).length, 0);
    // aynan 10 belgi — qabul qilinadi
    const r = await call({ kind: 'support_chat', id: chat, reason: '1234567890' }, SUPER);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
  });

  await check('C2 support_chat: ARXIVGA olinmagan chat o\'chirilmaydi (CHAT_NOT_ARCHIVED); yangi xabar kelgan (updatedAt > adminArchivedAt) chat ham', async () => {
    const chat = '998901119003';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, lastMessage: 'x', lastFromAdmin: false, updatedAt: Timestamp.fromMillis(1_700_000_000_000) });
    await seedMessages(chat, 3);
    await expectCode(call({ kind: 'support_chat', id: chat, reason: REASON }, SUPER), 'CHAT_NOT_ARCHIVED');
    assert.ok(await exists(`support_chats/${chat}`));
    assert.strictEqual(await msgCount(chat), 3);
    assert.strictEqual((await auditsOf(chat)).length, 0);
    // arxivlangan, lekin keyin yangi xabar → qayta ochilgan
    await db.doc(`support_chats/${chat}`).update({ adminArchivedAt: Timestamp.fromMillis(1_700_000_100_000), updatedAt: Timestamp.fromMillis(1_700_000_200_000) });
    await expectCode(call({ kind: 'support_chat', id: chat, reason: REASON }, SUPER), 'CHAT_NOT_ARCHIVED');
    assert.strictEqual(await msgCount(chat), 3);
    assert.strictEqual((await auditsOf(chat)).length, 0);
  });

  await check('C3 support_chat: arxivlangan, 450 xabar (400 + 50 batch) va chat hujjati o\'chadi; bitta audit (messageCount, arxiv izi, matn yo\'q); takroriy — deleted:false', async () => {
    const chat = '998901119004';
    await archivedChat(chat);
    await seedMessages(chat, 450);
    const r = await call({ kind: 'support_chat', id: chat, reason: REASON }, SUPER);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.ok(!(await exists(`support_chats/${chat}`)));
    assert.strictEqual(await msgCount(chat), 0);
    const a = await auditsOf(chat);
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].recordKind, 'support_chat');
    assert.strictEqual(a[0].actor, SUPER);
    assert.strictEqual(a[0].snapshot.messageCount, 450);
    assert.strictEqual(a[0].snapshot.userPhone, chat);
    assert.strictEqual(a[0].snapshot.adminArchivedBy, ADMIN);
    assert.ok(a[0].snapshot.adminArchivedAt);
    assert.strictEqual(a[0].reason, REASON);
    assert.ok(!JSON.stringify(a[0]).includes('MAXFIY'), 'chat matni audit\'ga tushmasligi kerak');
    assert.deepStrictEqual(await call({ kind: 'support_chat', id: chat, reason: REASON }, SUPER), { ok: true, deleted: false });
    assert.strictEqual((await auditsOf(chat)).length, 1);
  });

  await check('C4 chat hujjati yo\'q, lekin xabarlar qolgan (yetim) — arxiv sharti tekshirilmaydi, xabarlar o\'chadi', async () => {
    const chat = '998901119005';
    await seedMessages(chat, 5);
    const r = await call({ kind: 'support_chat', id: chat, reason: REASON }, SUPER);
    assert.deepStrictEqual(r, { ok: true, deleted: true });
    assert.strictEqual(await msgCount(chat), 0);
    assert.strictEqual((await auditsOf(chat)).length, 1);
  });

  await check('C5 chegara: maxBatches=1 va 450 xabar → partial:true, chat hujjati qoladi; qayta bosilsa tugaydi (2-audit qolgan 50 uchun)', async () => {
    const local = {};
    attachAdminDeleteRecord(local, { functions, db, admin, requireCallerRoles: async () => SUPER, maxBatches: 1 });
    const chat = '998901119006';
    await archivedChat(chat);
    await seedMessages(chat, 450);
    const r1 = await local.adminDeleteRecord.run({ kind: 'support_chat', id: chat, reason: REASON }, ctxOf(SUPER));
    assert.deepStrictEqual(r1, { ok: true, deleted: true, partial: true });
    assert.ok(await exists(`support_chats/${chat}`), 'chat hujjati partial\'da saqlanadi');
    assert.strictEqual(await msgCount(chat), 50);
    const r2 = await local.adminDeleteRecord.run({ kind: 'support_chat', id: chat, reason: REASON }, ctxOf(SUPER));
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
