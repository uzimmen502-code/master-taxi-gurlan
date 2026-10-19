/**
 * ADMIN — yozuvni o'chirish (risk_event, admin_news, support_message, support_chat), 2026-10-19.
 *
 * Nega callable: Firestore rules'da `admin_news` / `support_chats` delete = false (mijoz o'chira olmaydi), `risk_events`
 * esa to'g'ridan-to'g'ri admin'ga ochiq edi — lekin CLAUDE.md §41: sezgir admin amali audit log'ga tushishi shart.
 * Shuning uchun BARCHA o'chirish faqat shu yerdan (Admin SDK), audit bilan. Rules O'ZGARMAYDI.
 *
 * Callable `adminDeleteRecord({ kind, id, chatId?, reason? })`; rol: admin / superadmin (dispatcher EMAS).
 *   kind = 'risk_event'      id = risk_events/{id}
 *   kind = 'admin_news'      id = admin_news/{id}
 *   kind = 'support_message' id = messages/{id}, chatId = support_chats/{chatId}
 *   kind = 'support_chat'    id = chatId; chat hujjati va BARCHA xabarlari (400 tadan batch; chegaraga yetsa `partial:true`)
 * Natija: `{ ok:true, deleted:boolean, partial?:true }`. Mavjud bo'lmagan yozuv → `deleted:false`, yangi audit YOZILMAYDI
 * (idempotent). Xato kodlari (`details.code`): KIND_INVALID, ID_INVALID, CHAT_ID_INVALID, REASON_TOO_LONG, DELETE_FAILED.
 *
 * Audit (`admin_audit`, faqat Admin SDK): { kind:'admin_record_deleted', recordKind, recordId, chatId?, actor, reason,
 * snapshot, at }. Yakka hujjatda audit va o'chirish BIR tranzaksiyada (yoki ikkalasi, yoki hech biri). Snapshot PII-minimal
 * (§40): xabar/yangilik MATNI saqlanmaydi (faqat uzunlik / sarlavha), risk_event — to'liq nusxa (xavf signali audit uchun).
 * `support_chat`: audit batch'dan OLDIN yoziladi; chegaraga yetib qayta bosilsa, qolgani uchun yana bitta audit yoziladi.
 *
 * `support_message` oxirgi xabar o'chirilsa chat hujjatidagi `lastMessage` qolgan eng yangi xabarga o'tadi.
 * `lastFromAdmin` faqat TUSHIRILADI (true → false), hech qachon false → true qilinmaydi: aks holda mijoz ilovasida
 * «admindan o'qilmagan xabar» belgisi o'z-o'zidan yonib qolardi. `awaitingAdmin*` ga TEGILMAYDI.
 */
'use strict';

const ADMIN_AUDIT = 'admin_audit';
const KINDS = ['risk_event', 'admin_news', 'support_message', 'support_chat'];
const BATCH_SIZE = 400;
const DEFAULT_MAX_BATCHES = 25; // bitta chaqiruvda ko'pi bilan 10 000 xabar; undan ortig'i — qayta bosiladi
const MAX_REASON = 300;

/** Firestore hujjat ID'si sifatida xavfsiz (yo'l ajratgich, '.', '..', '__x__' yo'q). */
function validDocId(v) {
  return typeof v === 'string' && v.length >= 1 && v.length <= 200 && !v.includes('/') &&
    v !== '.' && v !== '..' && !/^__.*__$/.test(v);
}

function attachAdminDeleteRecord(exportsObj, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const maxBatches = Number.isInteger(deps.maxBatches) && deps.maxBatches > 0 ? deps.maxBatches : DEFAULT_MAX_BATCHES;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code, extra = {}) => new HttpsError(status, code, { code, ...extra });
  const ts = () => admin.firestore.FieldValue.serverTimestamp();

  function log(fields) {
    console.log(JSON.stringify({ module: 'admin_delete_record', action: 'admin_delete_record', ...fields }));
  }

  /** Yakka hujjat: tranzaksiyada o'qish → (bor bo'lsa) audit + delete. */
  async function deleteSingle({ kind, id, chatId, actor, reason }) {
    const auditRef = db.collection(ADMIN_AUDIT).doc();
    const audit = (extra) => ({ kind: 'admin_record_deleted', recordKind: kind, recordId: id, ...extra, actor, reason, at: ts() });

    if (kind === 'risk_event') {
      const ref = db.collection('risk_events').doc(id);
      return db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) return { deleted: false };
        t.set(auditRef, audit({ snapshot: snap.data() || {} }));
        t.delete(ref);
        return { deleted: true };
      });
    }

    if (kind === 'admin_news') {
      const ref = db.collection('admin_news').doc(id);
      return db.runTransaction(async (t) => {
        const snap = await t.get(ref);
        if (!snap.exists) return { deleted: false };
        const d = snap.data() || {};
        const pick = (v) => (v === undefined ? null : v);
        t.set(auditRef, audit({
          snapshot: {
            title: pick(d.title), category: pick(d.category), audience: pick(d.audience),
            targetUserId: pick(d.targetUserId), source: pick(d.source), createdAt: pick(d.createdAt),
          },
        }));
        t.delete(ref);
        return { deleted: true };
      });
    }

    // support_message
    const chatRef = db.collection('support_chats').doc(chatId);
    const msgRef = chatRef.collection('messages').doc(id);
    return db.runTransaction(async (t) => {
      const [msgSnap, chatSnap, topSnap] = await Promise.all([
        t.get(msgRef),
        t.get(chatRef),
        t.get(chatRef.collection('messages').orderBy('createdAt', 'desc').limit(2)),
      ]);
      if (!msgSnap.exists) return { deleted: false };
      const m = msgSnap.data() || {};
      t.set(auditRef, audit({
        chatId,
        snapshot: {
          fromAdmin: m.fromAdmin === true,
          fromPhone: typeof m.fromPhone === 'string' ? m.fromPhone : '',
          createdAt: m.createdAt === undefined ? null : m.createdAt,
          textLength: typeof m.text === 'string' ? m.text.length : 0,
        },
      }));
      t.delete(msgRef);
      const wasNewest = topSnap.docs.length > 0 && topSnap.docs[0].id === id;
      if (wasNewest && chatSnap.exists) {
        const next = topSnap.docs[1] ? topSnap.docs[1].data() || {} : null;
        const curLastFromAdmin = (chatSnap.data() || {}).lastFromAdmin === true;
        t.update(chatRef, {
          lastMessage: next ? String(next.text || '').slice(0, 200) : '',
          lastFromAdmin: next ? curLastFromAdmin && next.fromAdmin === true : false,
        });
      }
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
      actor = await requireCallerRoles(context, ['admin', 'superadmin'], 'Фақат админ ўчира олади');
      if (!KINDS.includes(kind)) throw fail('invalid-argument', 'KIND_INVALID');
      const id = input.id;
      if (!validDocId(id)) throw fail('invalid-argument', 'ID_INVALID');
      let chatId = '';
      if (kind === 'support_message') {
        chatId = input.chatId;
        if (!validDocId(chatId)) throw fail('invalid-argument', 'CHAT_ID_INVALID');
      }
      const reasonRaw = input.reason == null ? '' : input.reason;
      if (typeof reasonRaw !== 'string' || reasonRaw.trim().length > MAX_REASON) {
        throw fail('invalid-argument', 'REASON_TOO_LONG');
      }
      const reason = reasonRaw.trim();

      let out;
      try {
        out = kind === 'support_chat'
          ? await deleteChat({ id, actor, reason })
          : await deleteSingle({ kind, id, chatId, actor, reason });
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
