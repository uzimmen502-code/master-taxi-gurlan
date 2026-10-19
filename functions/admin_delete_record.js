/**
 * ADMIN — yozuvni HAQIQIY o'chirish (support_chat, risk_event), 2026-10-19; SIYOSAT TORAYTIRILDI 2026-10-20 (ega: «ҳа»).
 *
 * Avval: risk_event, admin_news, support_message, support_chat — hammasi admin tomonidan butunlay o'chirilardi.
 * Endi: `admin_news` QAYTARIB OLINADI (`adminRetractNews`), mijoz chati ARXIVGA olinadi (`adminArchiveSupportChat`) —
 * ikkalasi `admin_retract_archive.js` da. Bu callable'da FAQAT ikki holat qoldi, ikkalasi ham SUPERADMIN uchun:
 *   kind = 'support_chat' id = chatId — FAQAT shaxsiy ma'lumotni o'chirish talabi bo'yicha. Shartlar: `reason` >= 10 belgi
 *                         (REASON_REQUIRED) va chat avval ARXIVGA olingan bo'lishi (CHAT_NOT_ARCHIVED). Chat hujjati va
 *                         BARCHA xabarlari (400 tadan batch; chegaraga yetsa `partial:true`). Chat hujjati yo'q, lekin
 *                         yetim xabarlar qolgan bo'lsa — arxiv sharti tekshirilmaydi (mijoz ko'radigan chat yo'q).
 *   kind = 'risk_event'   id = risk_events/{id} — faqat `status == 'resolved'` va `resolvedAt` 365 kundan eski
 *                         (RISK_EVENT_RETENTION). Ochiq / yangi yopilgan signal o'chirilmaydi.
 * `admin_news` va `support_message` → KIND_INVALID (o'chirish yo'li yopilgan).
 *
 * Nega callable: Firestore rules'da `admin_news` / `support_chats` delete = false, `risk_events` esa admin'ga ochiq edi,
 * lekin CLAUDE.md §41: sezgir admin amali audit log'ga tushishi shart. Rules O'ZGARMAYDI.
 *
 * Callable `adminDeleteRecord({ kind, id, reason? })`. Rol: avval admin/superadmin (dispatcher EMAS), kind to'g'ri bo'lsa —
 * faqat superadmin (aks holda permission-denied).
 * Natija: `{ ok:true, deleted:boolean, partial?:true }`. Mavjud bo'lmagan yozuv → `deleted:false`, yangi audit YOZILMAYDI
 * (idempotent). Xato kodlari (`details.code`): KIND_INVALID, ID_INVALID, REASON_TOO_LONG, REASON_REQUIRED,
 * CHAT_NOT_ARCHIVED, RISK_EVENT_RETENTION, DELETE_FAILED.
 *
 * Audit (`admin_audit`, faqat Admin SDK): { kind:'admin_record_deleted', recordKind, recordId, actor, reason, snapshot, at }.
 * risk_event: audit va o'chirish BIR tranzaksiyada. Snapshot PII-minimal (§40): chat matni saqlanmaydi (faqat soni),
 * risk_event — to'liq nusxa (xavf signali audit uchun). `support_chat`: audit batch'dan OLDIN yoziladi; chegaraga yetib
 * qayta bosilsa, qolgani uchun yana bitta audit yoziladi.
 */
'use strict';

const { isSupportChatArchived } = require('./admin_retract_archive');

const ADMIN_AUDIT = 'admin_audit';
const KINDS = ['risk_event', 'support_chat'];
const BATCH_SIZE = 400;
const DEFAULT_MAX_BATCHES = 25; // bitta chaqiruvda ko'pi bilan 10 000 xabar; undan ortig'i — qayta bosiladi
const MAX_REASON = 300;
const MIN_ERASURE_REASON = 10;
const RISK_EVENT_RETENTION_DAYS = 365;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Firestore hujjat ID'si sifatida xavfsiz (yo'l ajratgich, '.', '..', '__x__' yo'q). */
function validDocId(v) {
  return typeof v === 'string' && v.length >= 1 && v.length <= 200 && !v.includes('/') &&
    v !== '.' && v !== '..' && !/^__.*__$/.test(v);
}

function attachAdminDeleteRecord(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const maxBatches = Number.isInteger(deps.maxBatches) && deps.maxBatches > 0 ? deps.maxBatches : DEFAULT_MAX_BATCHES;
  const nowMs = typeof deps.nowMs === 'function' ? deps.nowMs : () => Date.now();
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  function log(fields) {
    console.log(JSON.stringify({ module: 'admin_delete_record', action: 'admin_delete_record', ...fields }));
  }

  /** risk_event: tranzaksiyada o'qish → saqlash muddati tekshiruvi → audit + delete. */
  async function deleteRiskEvent({ id, actor, reason }) {
    const auditRef = db.collection(ADMIN_AUDIT).doc();
    const ref = db.collection('risk_events').doc(id);
    return db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) return { deleted: false };
      const d = snap.data() || {};
      const resolvedMs = d.resolvedAt && typeof d.resolvedAt.toMillis === 'function' ? d.resolvedAt.toMillis() : null;
      if (d.status !== 'resolved' || resolvedMs === null || nowMs() - resolvedMs < RISK_EVENT_RETENTION_DAYS * DAY_MS) {
        throw fail('failed-precondition', 'RISK_EVENT_RETENTION');
      }
      t.set(auditRef, { kind: 'admin_record_deleted', recordKind: 'risk_event', recordId: id, actor, reason, snapshot: d, at: ts() });
      t.delete(ref);
      return { deleted: true };
    });
  }

  /** Butun chat: avval audit, so'ng xabarlar batch'lab, oxirida chat hujjati. */
  async function deleteChat({ id, actor, reason }) {
    const chatRef = db.collection('support_chats').doc(id);
    const msgsCol = chatRef.collection('messages');
    const [chatSnap, countSnap] = await Promise.all([chatRef.get(), msgsCol.count().get()]);
    const messageCount = countSnap.data().count;
    if (!chatSnap.exists && messageCount === 0) return { deleted: false };

    const c = chatSnap.exists ? chatSnap.data() || {} : {};
    // Chat hujjati bor bo'lsa — avval ARXIVGA olingan bo'lishi shart (mijoz tarixi tasodifan o'chmasin).
    if (chatSnap.exists && !isSupportChatArchived(c)) throw fail('failed-precondition', 'CHAT_NOT_ARCHIVED');
    const pick = (v) => (v === undefined ? null : v);
    // Xabar matni YO'Q: lastMessage ham saqlanmaydi (§40).
    await db.collection(ADMIN_AUDIT).add({
      kind: 'admin_record_deleted',
      recordKind: 'support_chat',
      recordId: id,
      actor,
      reason,
      snapshot: {
        chatExists: chatSnap.exists,
        userPhone: pick(c.userPhone),
        lastFromAdmin: pick(c.lastFromAdmin),
        awaitingAdmin: pick(c.awaitingAdmin),
        updatedAt: pick(c.updatedAt),
        adminArchivedAt: pick(c.adminArchivedAt),
        adminArchivedBy: pick(c.adminArchivedBy),
        messageCount,
      },
      at: ts(),
    });

    for (let i = 0; i < maxBatches; i += 1) {
      const page = await msgsCol.limit(BATCH_SIZE).get();
      if (page.empty) break;
      const batch = db.batch();
      page.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      if (page.size < BATCH_SIZE) break;
    }
    // Chegara tugagach qolgan xabar bormi? Bo'lsa chat hujjati TEGILMAYDI (qayta bosiladi).
    const rest = await msgsCol.limit(1).get();
    if (!rest.empty) return { deleted: true, partial: true };
    await chatRef.delete();
    return { deleted: true };
  }

  exportsObj.adminDeleteRecord = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    const input = data && typeof data === 'object' ? data : {};
    const kind = typeof input.kind === 'string' ? input.kind : '';
    const base = { recordKind: kind };
    let actor = '';
    try {
      await requireCallerRoles(context, ['admin', 'superadmin'], 'Фақат админ');
      if (!KINDS.includes(kind)) throw fail('invalid-argument', 'KIND_INVALID');
      // Ikkala qolgan holat ham faqat superadmin uchun.
      actor = await requireCallerRoles(context, ['superadmin'], 'Фақат superadmin ўчира олади');
      const id = input.id;
      if (!validDocId(id)) throw fail('invalid-argument', 'ID_INVALID');
      const reasonRaw = input.reason == null ? '' : input.reason;
      if (typeof reasonRaw !== 'string' || reasonRaw.trim().length > MAX_REASON) {
        throw fail('invalid-argument', 'REASON_TOO_LONG');
      }
      const reason = reasonRaw.trim();
      if (kind === 'support_chat' && reason.length < MIN_ERASURE_REASON) {
        throw fail('invalid-argument', 'REASON_REQUIRED');
      }

      let out;
      try {
        out = kind === 'support_chat'
          ? await deleteChat({ id, actor, reason })
          : await deleteRiskEvent({ id, actor, reason });
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        console.error('adminDeleteRecord:', e && e.message ? e.message : e);
        throw fail('internal', 'DELETE_FAILED');
      }
      log({ ...base, recordId: id, userId: actor, result: out.deleted ? (out.partial ? 'partial' : 'deleted') : 'not_found', durationMs: Date.now() - started });
      return out.partial ? { ok: true, deleted: true, partial: true } : { ok: true, deleted: out.deleted };
    } catch (e) {
      log({ ...base, userId: actor, result: 'error', errorCode: (e && e.details && e.details.code) || (e && e.code) || 'UNKNOWN', durationMs: Date.now() - started });
      throw e;
    }
  });
}

module.exports = { attachAdminDeleteRecord, KINDS, BATCH_SIZE };
