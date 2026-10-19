/**
 * ADMIN — xabarni QAYTARIB OLISH (`adminRetractNews`), kunlik tozalash (`purgeRetractedAdminNews`) va support chatni
 * ARXIVGA olish (`adminArchiveSupportChat`), siyosat 2026-10-20. HAQIQIY `functions/index.js`, Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-admin-retract \
 *     "node functions/test/admin_retract_archive_cf.test.js"
 *
 * (Emulator porti `FIRESTORE_EMULATOR_HOST` bilan beriladi; berilmasa 127.0.0.1:18095.)
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18095';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-admin-retract';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const { attachAdminRetractArchive, isProtectedNews, isSupportChatArchived } = require('../admin_retract_archive');

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;
const ADMIN = '998915000001';
const SUPER = '998915000002';
const DISPATCHER = '998915000003';
const USER = '998912000001';
const DAY = 24 * 60 * 60 * 1000;
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const retract = (data, who) => fns.adminRetractNews.run(data, ctxOf(who));
const archive = (data, who) => fns.adminArchiveSupportChat.run(data, ctxOf(who));

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
const auditsByKind = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).docs.map((d) => d.data());
const exists = async (path) => (await db.doc(path).get()).exists;
const newsDoc = (id, extra = {}) => db.collection('admin_news').doc(id).set({
  title: 'Aksiya', body: 'MAXFIY-BODY-MATNI', category: 'promo', audience: 'driver', targetUserId: '', source: 'admin_compose',
  createdAt: Timestamp.fromMillis(1_700_000_000_000), priority: 3, ...extra,
});

async function main() {
  await clearEmulator();
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISPATCHER).set({ role: 'dispatcher' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  // ── sof funksiyalar ──
  await check('U1 isProtectedNews: shaxsiy / buyurtma / wallet himoyalangan, ommaviy emas', () => {
    assert.strictEqual(isProtectedNews({ targetUserId: '998901234567' }), true);
    assert.strictEqual(isProtectedNews({ targetUserId: '' }), false);
    assert.strictEqual(isProtectedNews({}), false);
    assert.strictEqual(isProtectedNews({ targetUserId: '', category: 'order' }), true);
    assert.strictEqual(isProtectedNews({ targetUserId: '', category: 'wallet' }), true);
    assert.strictEqual(isProtectedNews({ source: 'order_status' }), true);
    assert.strictEqual(isProtectedNews({ source: 'order_placed' }), true);
    assert.strictEqual(isProtectedNews({ source: 'wallet_topup' }), true);
    assert.strictEqual(isProtectedNews({ orderId: 'o1' }), true);
    assert.strictEqual(isProtectedNews({ category: 'promo', source: 'admin_compose', targetUserId: '' }), false);
  });

  await check('U2 isSupportChatArchived: bo\'sh=yo\'q; arxiv>=updatedAt = arxivda; updatedAt keyin = qayta ochilgan', () => {
    const t = (ms) => Timestamp.fromMillis(ms);
    assert.strictEqual(isSupportChatArchived({}), false);
    assert.strictEqual(isSupportChatArchived({ updatedAt: t(1) }), false);
    assert.strictEqual(isSupportChatArchived({ adminArchivedAt: t(100) }), true);
    assert.strictEqual(isSupportChatArchived({ adminArchivedAt: t(100), updatedAt: t(50) }), true);
    assert.strictEqual(isSupportChatArchived({ adminArchivedAt: t(100), updatedAt: t(100) }), true);
    assert.strictEqual(isSupportChatArchived({ adminArchivedAt: t(100), updatedAt: t(101) }), false);
  });

  // ── rol ──
  await check('A1 oddiy foydalanuvchi, dispatcher va kirmagan: uchala callable rad etiladi; hech narsa o\'zgarmaydi', async () => {
    await newsDoc('n_auth');
    await db.collection('support_chats').doc('998901119101').set({ userPhone: '998901119101', updatedAt: Timestamp.fromMillis(1_700_000_000_000) });
    for (const who of [USER, DISPATCHER]) {
      await assert.rejects(retract({ id: 'n_auth' }, who), (e) => e.code === 'permission-denied');
      await assert.rejects(archive({ chatId: '998901119101', archived: true }, who), (e) => e.code === 'permission-denied');
    }
    await assert.rejects(fns.adminRetractNews.run({ id: 'n_auth' }, {}), (e) => e.code === 'unauthenticated');
    await assert.rejects(fns.adminArchiveSupportChat.run({ chatId: '998901119101', archived: true }, {}), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await db.doc('admin_news/n_auth').get()).data().retractedAt, undefined);
    assert.strictEqual((await db.doc('support_chats/998901119101').get()).data().adminArchivedAt, undefined);
    assert.strictEqual((await auditsOf('n_auth')).length, 0);
  });

  // ── adminRetractNews ──
  await check('N1 validatsiya: id, sabab', async () => {
    await expectCode(retract({}, ADMIN), 'ID_INVALID');
    await expectCode(retract({ id: '' }, ADMIN), 'ID_INVALID');
    await expectCode(retract({ id: 'a/b' }, ADMIN), 'ID_INVALID');
    await expectCode(retract({ id: 5 }, ADMIN), 'ID_INVALID');
    await expectCode(retract({ id: 'n_auth', reason: 'x'.repeat(301) }, ADMIN), 'REASON_TOO_LONG');
    await expectCode(retract({ id: 'n_yoq' }, ADMIN), 'NEWS_NOT_FOUND');
    assert.strictEqual((await db.doc('admin_news/n_auth').get()).data().retractedAt, undefined);
  });

  await check('N2 ommaviy xabar qaytariladi: retractedAt/By/FromAudience, audience=retracted; boshqa maydonlar o\'zgarmaydi; bitta audit (matn yo\'q); hujjat o\'chmaydi', async () => {
    const pushAt = Timestamp.fromMillis(1_700_000_050_000);
    await newsDoc('n1', { pushResendAt: pushAt, pushSentCount: 12 });
    const before = (await db.doc('admin_news/n1').get()).data();
    const r = await retract({ id: 'n1', reason: 'xato yuborilgan' }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, changed: true });
    const after = (await db.doc('admin_news/n1').get()).data();
    assert.ok(after.retractedAt && typeof after.retractedAt.toMillis === 'function');
    assert.strictEqual(after.retractedBy, ADMIN);
    assert.strictEqual(after.retractedFromAudience, 'driver');
    assert.strictEqual(after.audience, 'retracted');
    for (const k of ['title', 'body', 'category', 'targetUserId', 'source', 'priority', 'pushSentCount']) assert.strictEqual(after[k], before[k], k);
    assert.ok(after.createdAt.isEqual(before.createdAt));
    assert.ok(after.pushResendAt.isEqual(pushAt), 'pushResendAt o\'zgarmasligi shart (qayta push ishga tushmasin)');
    const a = await auditsOf('n1');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].kind, 'admin_news_retracted');
    assert.strictEqual(a[0].actor, ADMIN);
    assert.strictEqual(a[0].reason, 'xato yuborilgan');
    assert.deepStrictEqual([a[0].snapshot.title, a[0].snapshot.category, a[0].snapshot.audience, a[0].snapshot.targetUserId, a[0].snapshot.source], ['Aksiya', 'promo', 'driver', '', 'admin_compose']);
    assert.ok(a[0].snapshot.createdAt && a[0].at);
    assert.ok(!JSON.stringify(a[0]).includes('MAXFIY-BODY-MATNI'), 'matn audit\'ga tushmasligi kerak');
  });

  await check('N3 takroriy chaqiruv: changed:false, yangi audit YO\'Q, retractedAt/By/FromAudience o\'zgarmaydi (audience=retracted ikkinchi marta saqlanmaydi); superadmin ham chaqirsa', async () => {
    const first = (await db.doc('admin_news/n1').get()).data();
    assert.deepStrictEqual(await retract({ id: 'n1' }, ADMIN), { ok: true, changed: false });
    assert.deepStrictEqual(await retract({ id: 'n1' }, SUPER), { ok: true, changed: false });
    const second = (await db.doc('admin_news/n1').get()).data();
    assert.ok(second.retractedAt.isEqual(first.retractedAt));
    assert.strictEqual(second.retractedBy, ADMIN);
    assert.strictEqual(second.retractedFromAudience, 'driver');
    assert.strictEqual((await auditsOf('n1')).length, 1);
  });

  await check('N4 superadmin qaytara oladi; audience maydoni yo\'q eski hujjat — retractedFromAudience bo\'sh satr', async () => {
    await db.collection('admin_news').doc('n_old').set({ title: 'Eski', body: 'b', category: 'info', createdAt: Timestamp.fromMillis(1_600_000_000_000) });
    assert.deepStrictEqual(await retract({ id: 'n_old' }, SUPER), { ok: true, changed: true });
    const d = (await db.doc('admin_news/n_old').get()).data();
    assert.strictEqual(d.audience, 'retracted');
    assert.strictEqual(d.retractedFromAudience, '');
    assert.strictEqual(d.retractedBy, SUPER);
    const a = await auditsOf('n_old');
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].snapshot.audience, null);
  });

  await check('N5 SHAXSIY / buyurtma / wallet xabari qaytarilmaydi: PERSONAL_NEWS_NOT_RETRACTABLE, hujjat o\'zgarmaydi, audit yo\'q', async () => {
    await newsDoc('n_personal', { audience: 'user', targetUserId: USER, source: 'identity_request' });
    await newsDoc('n_order', { audience: 'user', targetUserId: '', category: 'order', source: 'order_status', orderId: 'o1' });
    await newsDoc('n_order_target', { audience: 'user', targetUserId: USER, category: 'order', source: 'order_placed', orderId: 'o2' });
    await newsDoc('n_wallet', { audience: 'user', targetUserId: '', category: 'wallet', source: 'wallet_topup' });
    for (const id of ['n_personal', 'n_order', 'n_order_target', 'n_wallet']) {
      const before = (await db.doc(`admin_news/${id}`).get()).data();
      await expectCode(retract({ id }, SUPER), 'PERSONAL_NEWS_NOT_RETRACTABLE');
      const after = (await db.doc(`admin_news/${id}`).get()).data();
      assert.deepStrictEqual(after, before, id);
      assert.strictEqual((await auditsOf(id)).length, 0, id);
    }
  });

  await check('N6 onAdminNewsUpdate qaytarishda ISHLAMAYDI: faqat pushResendAt o\'zgarsa push (musbat nazorat: ref\'ga tegadi); qaytarish update\'i ref\'ga TEGMAYDI', async () => {
    const before = (await db.doc('admin_news/n_old').get()).data();
    // qaytarishdan oldingi va keyingi holat (N4 dan): faqat retracted* va audience o'zgargan.
    const beforeDoc = { ...before, audience: 'all' };
    delete beforeDoc.retractedAt; delete beforeDoc.retractedBy; delete beforeDoc.retractedFromAudience;
    const poisoned = (data) => ({ data: () => data, get ref() { throw new Error('TOUCHED_REF'); } });
    const res = await fns.onAdminNewsUpdate.run({ before: poisoned(beforeDoc), after: poisoned(before) }, {});
    assert.strictEqual(res, null);
    // musbat nazorat: pushResendAt o'zgarsa trigger push yuborishga o'tadi (ref'ga murojaat qiladi)
    const withResend = { ...before, pushResendAt: Timestamp.fromMillis(Date.now()) };
    await assert.rejects(fns.onAdminNewsUpdate.run({ before: poisoned(before), after: poisoned(withResend) }, {}), /TOUCHED_REF/);
  });

  // ── purgeRetractedAdminNews ──
  await check('P1 90 kundan eski qaytarilganlar o\'chadi; yangi (89 kun), qaytarilmagan, shaxsiy (yaroqsiz holat) qoladi; bitta audit; qayta ishga tushirish — hech narsa, audit yo\'q', async () => {
    const at = (days) => Timestamp.fromMillis(Date.now() - days * DAY);
    await newsDoc('p_old1', { audience: 'retracted', retractedAt: at(91), retractedBy: ADMIN, retractedFromAudience: 'all' });
    await newsDoc('p_old2', { audience: 'retracted', retractedAt: at(200), retractedBy: ADMIN, retractedFromAudience: 'all' });
    await newsDoc('p_new', { audience: 'retracted', retractedAt: at(89), retractedBy: ADMIN, retractedFromAudience: 'all' });
    await newsDoc('p_live', { audience: 'all' });
    // yaroqsiz holat (qo'lda/rules orqali): shaxsiy hujjatga retractedAt qo'yilgan — HECH QACHON o'chirilmaydi
    await newsDoc('p_personal', { audience: 'retracted', targetUserId: USER, category: 'order', source: 'order_status', retractedAt: at(300), retractedFromAudience: 'user' });
    await db.collection('admin_audit').doc('keep').set({ kind: 'x' });
    const r = await fns.purgeRetractedAdminNews.run({});
    assert.strictEqual(r, null);
    assert.ok(!(await exists('admin_news/p_old1')));
    assert.ok(!(await exists('admin_news/p_old2')));
    assert.ok(await exists('admin_news/p_new'));
    assert.ok(await exists('admin_news/p_live'));
    assert.ok(await exists('admin_news/p_personal'), 'shaxsiy/buyurtma xabari tozalanmaydi');
    const audits = await auditsByKind('admin_news_purged');
    assert.strictEqual(audits.length, 1);
    assert.strictEqual(audits[0].count, 2);
    assert.deepStrictEqual([...audits[0].ids].sort(), ['p_old1', 'p_old2']);
    assert.strictEqual(audits[0].retentionDays, 90);
    assert.ok(audits[0].cutoff && audits[0].at);
    assert.ok(!JSON.stringify(audits[0]).includes('MAXFIY'), 'matn audit\'da yo\'q');
    // idempotent
    await fns.purgeRetractedAdminNews.run({});
    assert.strictEqual((await auditsByKind('admin_news_purged')).length, 1);
    assert.ok(await exists('admin_news/p_new'));
  });

  await check('P2 chegara: purgeMaxBatches=1 va 450 eski hujjat → 400 o\'chadi, 50 qoladi; ikkinchi ishga tushirishda qolgani; auditlar [400, 50]', async () => {
    const local = {};
    attachAdminRetractArchive(local, { functions, db, admin, requireCallerRoles: async () => ADMIN, purgeMaxBatches: 1 });
    // oldingi test auditlarini ajratish uchun yangi baza
    await db.collection('admin_news').get().then((s) => Promise.all(s.docs.map((d) => d.ref.delete())));
    const old = Timestamp.fromMillis(Date.now() - 120 * DAY);
    for (let i = 0; i < 450; i += 400) {
      const batch = db.batch();
      for (let j = i; j < Math.min(450, i + 400); j += 1) {
        batch.set(db.collection('admin_news').doc(`b${String(j).padStart(4, '0')}`), { title: `t${j}`, body: 'b', category: 'info', audience: 'retracted', retractedAt: old, targetUserId: '' });
      }
      await batch.commit();
    }
    const countNews = async () => (await db.collection('admin_news').count().get()).data().count;
    const beforeAudits = (await auditsByKind('admin_news_purged')).length;
    await local.purgeRetractedAdminNews.run({});
    assert.strictEqual(await countNews(), 50);
    await local.purgeRetractedAdminNews.run({});
    assert.strictEqual(await countNews(), 0);
    const audits = await auditsByKind('admin_news_purged');
    assert.strictEqual(audits.length - beforeAudits, 2);
    const counts = audits.map((x) => x.count).sort((x, y) => y - x);
    assert.deepStrictEqual(counts.slice(0, 2), [400, 50]);
  });

  // ── adminArchiveSupportChat ──
  await check('S1 validatsiya: chatId, archived (boolean), chat yo\'q', async () => {
    await expectCode(archive({ archived: true }, ADMIN), 'CHAT_ID_INVALID');
    await expectCode(archive({ chatId: 'a/b', archived: true }, ADMIN), 'CHAT_ID_INVALID');
    await expectCode(archive({ chatId: '998901119102' }, ADMIN), 'ARCHIVED_INVALID');
    await expectCode(archive({ chatId: '998901119102', archived: 'true' }, ADMIN), 'ARCHIVED_INVALID');
    await expectCode(archive({ chatId: '998901119102', archived: true }, ADMIN), 'CHAT_NOT_FOUND');
    assert.ok(!(await exists('support_chats/998901119102')), 'chat hujjati yaratilmaydi');
  });

  await check('S2 arxivlash: faqat adminArchivedAt/By yoziladi; awaitingAdmin, awaitingAdminMsgAt, lastFromAdmin, updatedAt, lastMessage O\'ZGARMAYDI; audit; xabarlar saqlanadi', async () => {
    const chat = '998901119103';
    const awaitAt = Timestamp.fromMillis(1_700_000_001_000);
    const upd = Timestamp.fromMillis(1_700_000_002_000);
    await db.collection('support_chats').doc(chat).set({
      userPhone: chat, lastMessage: 'salom', lastFromAdmin: false, awaitingAdmin: true, awaitingAdminMsgAt: awaitAt, updatedAt: upd,
    });
    await db.collection('support_chats').doc(chat).collection('messages').doc('m1').set({ text: 'MAXFIY', fromAdmin: false });
    const r = await archive({ chatId: chat, archived: true }, ADMIN);
    assert.deepStrictEqual(r, { ok: true, changed: true });
    const d = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.ok(d.adminArchivedAt && typeof d.adminArchivedAt.toMillis === 'function');
    assert.strictEqual(d.adminArchivedBy, ADMIN);
    assert.strictEqual(d.awaitingAdmin, true);
    assert.ok(d.awaitingAdminMsgAt.isEqual(awaitAt));
    assert.strictEqual(d.lastFromAdmin, false);
    assert.ok(d.updatedAt.isEqual(upd), 'updatedAt tegilmaydi');
    assert.strictEqual(d.lastMessage, 'salom');
    assert.ok(await exists(`support_chats/${chat}/messages/m1`));
    assert.strictEqual(isSupportChatArchived(d), true);
    const a = await auditsOf(chat);
    assert.strictEqual(a.length, 1);
    assert.strictEqual(a[0].kind, 'support_chat_archived');
    assert.strictEqual(a[0].actor, ADMIN);
    assert.ok(!JSON.stringify(a[0]).includes('salom') && !JSON.stringify(a[0]).includes('MAXFIY'), 'chat matni auditda yo\'q');
  });

  await check('S3 takroriy arxivlash: changed:false, audit ko\'paymaydi, adminArchivedAt o\'zgarmaydi', async () => {
    const chat = '998901119103';
    const first = (await db.doc(`support_chats/${chat}`).get()).data().adminArchivedAt;
    assert.deepStrictEqual(await archive({ chatId: chat, archived: true }, SUPER), { ok: true, changed: false });
    assert.ok((await db.doc(`support_chats/${chat}`).get()).data().adminArchivedAt.isEqual(first));
    assert.strictEqual((await auditsOf(chat)).length, 1);
  });

  await check('S4 yangi mijoz xabari (updatedAt oshdi) → chat avtomatik qayta ochiladi; qayta arxivlash changed:true va yangi adminArchivedAt', async () => {
    const chat = '998901119103';
    const archAt = (await db.doc(`support_chats/${chat}`).get()).data().adminArchivedAt;
    await db.doc(`support_chats/${chat}`).update({ updatedAt: Timestamp.fromMillis(archAt.toMillis() + 1), lastMessage: 'yana', lastFromAdmin: false });
    assert.strictEqual(isSupportChatArchived((await db.doc(`support_chats/${chat}`).get()).data()), false);
    await new Promise((res) => setTimeout(res, 20));
    assert.deepStrictEqual(await archive({ chatId: chat, archived: true }, ADMIN), { ok: true, changed: true });
    const d = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.ok(d.adminArchivedAt.toMillis() > archAt.toMillis(), 'adminArchivedAt yangilandi');
    assert.strictEqual(isSupportChatArchived(d), true);
    assert.strictEqual(d.lastMessage, 'yana');
    assert.strictEqual((await auditsOf(chat)).length, 2);
  });

  await check('S5 arxivdan chiqarish: ikkala maydon o\'chadi, changed:true + audit; takroriy changed:false, audit ko\'paymaydi', async () => {
    const chat = '998901119104';
    await db.collection('support_chats').doc(chat).set({ userPhone: chat, updatedAt: Timestamp.fromMillis(1_700_000_000_000), awaitingAdmin: false });
    await archive({ chatId: chat, archived: true }, ADMIN);
    assert.deepStrictEqual(await archive({ chatId: chat, archived: false }, SUPER), { ok: true, changed: true });
    const d = (await db.doc(`support_chats/${chat}`).get()).data();
    assert.strictEqual(d.adminArchivedAt, undefined);
    assert.strictEqual(d.adminArchivedBy, undefined);
    assert.strictEqual(d.awaitingAdmin, false);
    assert.deepStrictEqual(await archive({ chatId: chat, archived: false }, ADMIN), { ok: true, changed: false });
    const kinds = (await auditsOf(chat)).map((x) => x.kind).sort();
    assert.deepStrictEqual(kinds, ['support_chat_archived', 'support_chat_unarchived']);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error('Error:', e); process.exit(1); });
