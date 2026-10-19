/**
 * ADMIN — xabarni QAYTARIB OLISH va support chatni ARXIVGA olish (2026-10-20, ega qarori).
 *
 * Nega: avval admin `admin_news` va support chatni butunlay o'chira olardi (`adminDeleteRecord`). Ega xavfsizroq siyosatni
 * tasdiqladi: ommaviy xabar o'chirilmaydi — QAYTARIB OLINADI (90 kun saqlanadi, keyin avtomatik tozalanadi); mijozning
 * chat tarixi o'chirilmaydi — ARXIVGA olinadi (yangi xabar kelsa o'zi qayta ochiladi). Haqiqiy o'chirish faqat
 * `adminDeleteRecord` da: shaxsiy ma'lumotni o'chirish talabi bo'yicha, superadmin (qarang `admin_delete_record.js`).
 * Rules O'ZGARMAYDI (hamma yozuv Admin SDK orqali). Audit — `admin_audit` (CLAUDE.md §41), faqat Admin SDK yozadi.
 *
 * 1) `adminRetractNews({ id, reason? })` — admin / superadmin.
 *    `admin_news/{id}` ga: `retractedAt` (server ts), `retractedBy` (actor uid), `retractedFromAudience` (avvalgi
 *    auditoriya) va `audience: 'retracted'` (ESKI ilova versiyalari `retractedAt` ni bilmaydi, lekin `audience` ni
 *    tekshiradi: 'retracted' ularning guruhlarida yo'q — xabar ro'yxatdan tushadi). Boshqa maydon (title, body, createdAt,
 *    pushResendAt…) TEGILMAYDI. SHAXSIY / buyurtma / wallet xabarlari (moliyaviy yozuv) qaytarilmaydi:
 *    `details.code = PERSONAL_NEWS_NOT_RETRACTABLE`. Idempotent: allaqachon qaytarilgan → `{ ok:true, changed:false }`,
 *    yangi audit YOZILMAYDI. Audit: kind `admin_news_retracted`, snapshot sarlavha/kategoriya/auditoriya/targetUserId/
 *    source/createdAt (MATN yo'q, §40). Xatolar: ID_INVALID, REASON_TOO_LONG, NEWS_NOT_FOUND, PERSONAL_NEWS_NOT_RETRACTABLE,
 *    RETRACT_FAILED.
 *    `onAdminNewsUpdate` (index.js) faqat `pushResendAt` o'zgarganda ishlaydi — bu yangilanish unga TEGMAYDI (test bor).
 *
 * 2) `purgeRetractedAdminNews` — kunlik (03:30 Toshkent): `retractedAt` 90 kundan eski `admin_news` hujjatlarini
 *    o'chiradi. Har 400 hujjat BIR batch'da + bitta audit (`admin_news_purged`: count, cutoff, ids) — yoki hammasi, yoki
 *    hech biri. Chegara: ko'pi bilan 10 batch (4000 hujjat) / ishga tushirish, qolgani ertasiga. Idempotent (qayta
 *    ishga tushirilsa o'chiradigan narsa yo'q → audit yo'q). Shaxsiy hujjatlar HECH QACHON o'chirilmaydi (o'tkazib
 *    yuboriladi va logda sanaladi).
 *
 * 3) `adminArchiveSupportChat({ chatId, archived })` — admin / superadmin. `support_chats/{chatId}` ga FAQAT
 *    `adminArchivedAt` + `adminArchivedBy` yoziladi (`archived:false` → ikkalasi o'chiriladi). `awaitingAdmin`,
 *    `awaitingAdminMsgAt`, `lastFromAdmin`, `updatedAt` TEGILMAYDI. Chat «arxivda» deb hisoblanadi, agar
 *    `adminArchivedAt != null` va `updatedAt` undan KEYIN emas (yangi xabar `updatedAt` ni oshiradi → chat o'zi qayta
 *    ochiladi, serverda o'zgarish shart emas). Idempotent: allaqachon shu holatda → `changed:false`, audit yo'q.
 *    Xatolar: CHAT_ID_INVALID, ARCHIVED_INVALID, CHAT_NOT_FOUND, ARCHIVE_FAILED.
 */
'use strict';

const ADMIN_AUDIT = 'admin_audit';
const MAX_REASON = 300;
const PURGE_BATCH = 400;
const DEFAULT_PURGE_MAX_BATCHES = 10;
const DEFAULT_RETENTION_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;
const SYSTEM_ACTOR = 'system:purgeRetractedAdminNews';

function validDocId(v) {
  return typeof v === 'string' && v.length >= 1 && v.length <= 200 && !v.includes('/') &&
    v !== '.' && v !== '..' && !/^__.*__$/.test(v);
}

const asMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);

/**
 * Shaxsiy yoki buyurtma/wallet xabari (moliyaviy yozuv) — qaytarilmaydi va tozalanmaydi.
 * Klientdagi `NewsItem.isPersonal` / `isOrderNews` / `isWalletNews` bilan bir xil mazmun.
 */
function isProtectedNews(d) {
  const data = d || {};
  const target = String(data.targetUserId == null ? '' : data.targetUserId).replace(/\D/g, '');
  if (target.length >= 9) return true;
  const category = String(data.category || '');
  const source = String(data.source || '');
  if (category === 'order' || category === 'wallet') return true;
  if (source === 'order_status' || source === 'order_placed' || source.startsWith('wallet_')) return true;
  if (typeof data.orderId === 'string' && data.orderId.trim() !== '') return true;
  return false;
}

/**
 * Chat arxivdami: `adminArchivedAt` bor va `updatedAt` undan KEYIN emas. (Flutter'dagi `isSupportChatArchived`
 * bilan bir xil qoida.)
 */
function isSupportChatArchived(d) {
  const data = d || {};
  const archMs = asMs(data.adminArchivedAt);
  if (archMs === null) return false;
  const updMs = asMs(data.updatedAt);
  return !(updMs !== null && updMs > archMs);
}

function attachAdminRetractArchive(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const nowMs = typeof deps.nowMs === 'function' ? deps.nowMs : () => Date.now();
  const retentionDays = Number.isInteger(deps.retentionDays) && deps.retentionDays > 0 ? deps.retentionDays : DEFAULT_RETENTION_DAYS;
  const purgeMaxBatches = Number.isInteger(deps.purgeMaxBatches) && deps.purgeMaxBatches > 0 ? deps.purgeMaxBatches : DEFAULT_PURGE_MAX_BATCHES;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const pick = (v) => (v === undefined ? null : v);

  function log(action, fields) {
    console.log(JSON.stringify({ module: 'admin_retract_archive', action, ...fields }));
  }

  // ── 1) adminRetractNews ───────────────────────────────────────────────────────────────────────
  exportsObj.adminRetractNews = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const input = data && typeof data === 'object' ? data : {};
    let actor = '';
    const id = input.id;
    try {
      actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Фақат админ хабарни қайтариб олади');
      if (!validDocId(id)) throw fail('invalid-argument', 'ID_INVALID');
      const reasonRaw = input.reason == null ? '' : input.reason;
      if (typeof reasonRaw !== 'string' || reasonRaw.trim().length > MAX_REASON) {
        throw fail('invalid-argument', 'REASON_TOO_LONG');
      }
      const reason = reasonRaw.trim();

      const ref = db.collection('admin_news').doc(id);
      const auditRef = db.collection(ADMIN_AUDIT).doc();
      let out;
      try {
        out = await db.runTransaction(async (t) => {
          const snap = await t.get(ref);
          if (!snap.exists) throw fail('not-found', 'NEWS_NOT_FOUND');
          const d = snap.data() || {};
          if (isProtectedNews(d)) throw fail('failed-precondition', 'PERSONAL_NEWS_NOT_RETRACTABLE');
          if (d.retractedAt) return { changed: false };
          t.update(ref, {
            retractedAt: ts(),
            retractedBy: actor,
            retractedFromAudience: d.audience === undefined || d.audience === null ? '' : d.audience,
            audience: 'retracted',
          });
          t.set(auditRef, {
            kind: 'admin_news_retracted',
            recordKind: 'admin_news',
            recordId: id,
            actor,
            reason,
            snapshot: {
              title: pick(d.title), category: pick(d.category), audience: pick(d.audience),
              targetUserId: pick(d.targetUserId), source: pick(d.source), createdAt: pick(d.createdAt),
            },
            at: ts(),
          });
          return { changed: true };
        });
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        console.error('adminRetractNews:', e && e.message ? e.message : e);
        throw fail('internal', 'RETRACT_FAILED');
      }
      log('admin_retract_news', { recordId: id, userId: actor, result: out.changed ? 'retracted' : 'already_retracted', durationMs: Date.now() - started });
      return { ok: true, changed: out.changed };
    } catch (e) {
      log('admin_retract_news', { recordId: typeof id === 'string' ? id : '', userId: actor, result: 'error', errorCode: (e && e.details && e.details.code) || (e && e.code) || 'UNKNOWN', durationMs: Date.now() - started });
      throw e;
    }
  });

  // ── 2) purgeRetractedAdminNews (kunlik) ───────────────────────────────────────────────────────
  async function purgeRetracted() {
    const started = Date.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(nowMs() - retentionDays * DAY_MS);
    let purged = 0;
    let skippedProtected = 0;
    let batches = 0;
    let cursor = null;
    for (let i = 0; i < purgeMaxBatches; i += 1) {
      let q = db.collection('admin_news').where('retractedAt', '<=', cutoff).orderBy('retractedAt').limit(PURGE_BATCH);
      if (cursor) q = q.startAfter(cursor);
      const page = await q.get();
      if (page.empty) break;
      cursor = page.docs[page.docs.length - 1];
      const deletable = page.docs.filter((d) => !isProtectedNews(d.data()));
      skippedProtected += page.size - deletable.length;
      if (deletable.length > 0) {
        const batch = db.batch();
        deletable.forEach((d) => batch.delete(d.ref));
        batch.set(db.collection(ADMIN_AUDIT).doc(), {
          kind: 'admin_news_purged',
          recordKind: 'admin_news',
          actor: SYSTEM_ACTOR,
          count: deletable.length,
          retentionDays,
          cutoff,
          ids: deletable.map((d) => d.id),
          at: ts(),
        });
        await batch.commit();
        purged += deletable.length;
        batches += 1;
      }
      if (page.size < PURGE_BATCH) break;
    }
    log('purge_retracted_admin_news', { result: 'ok', purged, batches, skippedProtected, retentionDays, durationMs: Date.now() - started });
    return { purged, skippedProtected, batches };
  }

  exportsObj.purgeRetractedAdminNews = functions
    .runWith({ timeoutSeconds: 300, memory: '256MB' })
    .pubsub.schedule('30 3 * * *')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      try {
        await purgeRetracted();
      } catch (e) {
        console.error('purgeRetractedAdminNews:', e && e.message ? e.message : e);
        log('purge_retracted_admin_news', { result: 'error', errorCode: 'PURGE_FAILED' });
        throw e;
      }
      return null;
    });

  // ── 3) adminArchiveSupportChat ────────────────────────────────────────────────────────────────
  exportsObj.adminArchiveSupportChat = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const input = data && typeof data === 'object' ? data : {};
    let actor = '';
    const chatId = input.chatId;
    try {
      actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Фақат админ чатни архивлайди');
      if (!validDocId(chatId)) throw fail('invalid-argument', 'CHAT_ID_INVALID');
      if (typeof input.archived !== 'boolean') throw fail('invalid-argument', 'ARCHIVED_INVALID');
      const archived = input.archived;

      const ref = db.collection('support_chats').doc(chatId);
      const auditRef = db.collection(ADMIN_AUDIT).doc();
      let out;
      try {
        out = await db.runTransaction(async (t) => {
          const snap = await t.get(ref);
          if (!snap.exists) throw fail('not-found', 'CHAT_NOT_FOUND');
          const d = snap.data() || {};
          if (archived) {
            if (isSupportChatArchived(d)) return { changed: false };
            t.update(ref, { adminArchivedAt: ts(), adminArchivedBy: actor });
          } else {
            if (d.adminArchivedAt === undefined || d.adminArchivedAt === null) return { changed: false };
            t.update(ref, {
              adminArchivedAt: admin.firestore.FieldValue.delete(),
              adminArchivedBy: admin.firestore.FieldValue.delete(),
            });
          }
          t.set(auditRef, {
            kind: archived ? 'support_chat_archived' : 'support_chat_unarchived',
            recordKind: 'support_chat',
            recordId: chatId,
            actor,
            snapshot: { userPhone: pick(d.userPhone), awaitingAdmin: pick(d.awaitingAdmin), updatedAt: pick(d.updatedAt) },
            at: ts(),
          });
          return { changed: true };
        });
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        console.error('adminArchiveSupportChat:', e && e.message ? e.message : e);
        throw fail('internal', 'ARCHIVE_FAILED');
      }
      log('admin_archive_support_chat', { recordId: chatId, userId: actor, result: out.changed ? (archived ? 'archived' : 'unarchived') : 'no_change', durationMs: Date.now() - started });
      return { ok: true, changed: out.changed };
    } catch (e) {
      log('admin_archive_support_chat', { recordId: typeof chatId === 'string' ? chatId : '', userId: actor, result: 'error', errorCode: (e && e.details && e.details.code) || (e && e.code) || 'UNKNOWN', durationMs: Date.now() - started });
      throw e;
    }
  });

  return { purgeRetracted };
}

module.exports = { attachAdminRetractArchive, isProtectedNews, isSupportChatArchived, PURGE_BATCH };
