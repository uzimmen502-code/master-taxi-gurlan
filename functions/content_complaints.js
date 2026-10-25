/**
 * ХАРИДОР ШИКОЯТИ — кафе/ресторан (уй ошпази ҳам шу модул), унинг таоми ва кўчмас мулк эълони
 * (эга вазифаси 2026-10-25, Agent B).
 *
 * Нега алоҳида файл, лекин параллел тизим ЭМАС (3/4/43-банд): мавжуд шикоят инфраструктураси тўлиқ
 * қайта ишлатилади — `reports` коллекцияси, админнинг умумий ёпиш callable'и `adminResolveDatingReport`
 * (`status: resolved`, `resolvedAt`, `resolvedBy`), кунлик чеклов индекси (`type+reporterId+createdAt`),
 * мижоздаги шикоят варағи (`shop_complaint_sheet.dart`). `submitShopComplaint` (business_directory.js)
 * дўкон/маҳсулот учун ЎЗГАРМАЙДИ — у Play'даги иловалар чақирадиган шартнома (эркин матнли сабаб).
 *
 * Фарқлар (вазифа талаби):
 *   • сабаб — ҚАТЪИЙ рўйхатдан код (`REASONS`, PROPOSED — эга тасдиқлайди), изоҳ — ихтиёрий, ≤ 300;
 *   • «бир шикоятчи × бир объект — битта очиқ шикоят» ТРАНЗАКЦИЯДА: `report_open_keys/{key}` қулф ҳужжати
 *     очиқ шикоятни кўрсатади; икки параллел чақирувдан фақат биттаси ҳужжат яратади (21/22-банд).
 *     Шикоят ёпилгач (resolved) кейинги шикоят янги ҳужжат бўлади — эскиси тарихда қолади (16-банд);
 *   • объект ҲОЗИР харидорга кўринаётган бўлиши шарт (ресторан `approved`; эълон `active` ва муддати
 *     ўтмаган) — йўқ/яширин объект бир хил код билан рад этилади (мавжудлиги ошкор бўлмасин);
 *   • эга/аъзо ўзига шикоят қила олмайди: ресторан `ownerUid` ва `members/{uid}`; кўчмас мулк
 *     `users/{uid}.realtyOwnerKey == listing.ownerKey` (жамоа аккаунти ҳам) ёки `private/detail.ownerId`.
 *
 * `reports` ҳужжати (мижоз ЁЗОЛМАЙДИ — firestore.rules):
 *   { type: 'restaurant_content' | 'realty_content', targetType, targetId, restaurantId?, title,
 *     reporterId, reason (код), comment, status: 'open', createdAt }
 *
 * Диагностика кодлари (`details.code`): COMPLAINT_TARGET_INVALID, COMPLAINT_REASON_INVALID,
 * COMPLAINT_COMMENT_INVALID, COMPLAINT_TARGET_NOT_FOUND, COMPLAINT_OWN, COMPLAINT_LIMIT.
 * Лог — телефон/матнсиз (24/40-банд).
 */
'use strict';

const crypto = require('crypto');

const REPORTS = 'reports';
const OPEN_KEYS = 'report_open_keys';
const RESTAURANTS = 'restaurants';
const REALTY = 'realty_listings';

/** targetType → reports.type. */
const TYPE_OF = Object.freeze({
  restaurant: 'restaurant_content',
  restaurant_item: 'restaurant_content',
  realty_listing: 'realty_content',
});
const TARGET_TYPES = Object.freeze(Object.keys(TYPE_OF));
/** Сабаб кодлари (PROPOSED, эга тасдиғигача). `other` — изоҳ мажбурий. Dart: `contentComplaintReasons`. */
const REASONS = Object.freeze(['fraud', 'wrong_info', 'spam', 'abuse', 'other']);
const COMMENT_MAX = 300;
const COMMENT_MIN_OTHER = 3;
/** Кунлик чеклов — бозор/дўкон шикояти билан бир хил (20), ҳар тур учун алоҳида. */
const DAILY_LIMIT = 20;
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Кириш маълумотини текширади (соф функция, тест учун экспорт). `fail(status, code)` — хато ясовчи.
 * Қайтаради: { targetType, targetId, restaurantId, reason, comment, type }.
 */
function parseComplaintInput(data, fail) {
  const d = data || {};
  const targetType = typeof d.targetType === 'string' ? d.targetType : '';
  if (!TARGET_TYPES.includes(targetType)) throw fail('invalid-argument', 'COMPLAINT_TARGET_INVALID');
  const targetId = String(d.targetId == null ? '' : d.targetId).trim();
  if (!ID_RE.test(targetId)) throw fail('invalid-argument', 'COMPLAINT_TARGET_INVALID');
  let restaurantId = '';
  if (targetType === 'restaurant_item') {
    restaurantId = String(d.restaurantId == null ? '' : d.restaurantId).trim();
    if (!ID_RE.test(restaurantId)) throw fail('invalid-argument', 'COMPLAINT_TARGET_INVALID');
  } else if (targetType === 'restaurant') {
    restaurantId = targetId;
  }
  const reason = typeof d.reason === 'string' ? d.reason : '';
  if (!REASONS.includes(reason)) throw fail('invalid-argument', 'COMPLAINT_REASON_INVALID');
  if (d.comment != null && typeof d.comment !== 'string') throw fail('invalid-argument', 'COMPLAINT_COMMENT_INVALID');
  const comment = String(d.comment || '').trim();
  if (comment.length > COMMENT_MAX) throw fail('invalid-argument', 'COMPLAINT_COMMENT_INVALID');
  if (reason === 'other' && comment.length < COMMENT_MIN_OTHER) throw fail('invalid-argument', 'COMPLAINT_COMMENT_INVALID');
  return { targetType, targetId, restaurantId, reason, comment, type: TYPE_OF[targetType] };
}

/** Қулф калити: шикоятчи × объект (телефон очиқ ёзилмайди — хэш). */
function openKeyOf(type, uid, targetType, restaurantId, targetId) {
  const h = crypto.createHash('sha256').update([uid, targetType, restaurantId, targetId].join('|')).digest('hex');
  return `${type}__${h.slice(0, 40)}`;
}

function attachContentComplaints(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid } = deps;
  const HttpsError = functions.https.HttpsError;
  const fail = (status, code) => new HttpsError(status, code, { code });
  const ts = () => admin.firestore.FieldValue.serverTimestamp();
  const log = (o) => console.log(JSON.stringify({ module: 'content_complaints', action: 'submitContentComplaint', ...o }));
  const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);
  const tsMillis = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : 0);

  /** Объект ҳозир харидорга кўринадими ва шикоятчи унинг эгаси/аъзосими. → { title } */
  async function resolveTarget(p, uid) {
    if (p.targetType === 'realty_listing') {
      const ref = db.collection(REALTY).doc(p.targetId);
      const [snap, userSnap, detailSnap] = await Promise.all([
        ref.get(), db.collection('users').doc(uid).get(), ref.collection('private').doc('detail').get(),
      ]);
      const x = snap.exists ? (snap.data() || {}) : null;
      const exp = x ? tsMillis(x.expiresAt) : 0;
      if (!x || x.status !== 'active' || (exp && exp < Date.now())) throw fail('not-found', 'COMPLAINT_TARGET_NOT_FOUND');
      const myKey = String((userSnap.data() || {}).realtyOwnerKey || '');
      const ownerId = canonicalUid(String((detailSnap.data() || {}).ownerId || ''));
      if ((myKey && myKey === String(x.ownerKey || '')) || (ownerId && ownerId === uid)) {
        throw fail('failed-precondition', 'COMPLAINT_OWN');
      }
      // Эркин матн (`text`) олинмайди — унда эга ёзган телефон бўлиши мумкин (40-банд); сарлавҳасиз эски эълон — ID.
      return { title: str(x.title, 120) || `#${p.targetId}` };
    }
    const rRef = db.collection(RESTAURANTS).doc(p.restaurantId);
    const reads = [rRef.get(), rRef.collection('members').doc(uid).get()];
    if (p.targetType === 'restaurant_item') reads.push(rRef.collection('menu_items').doc(p.targetId).get());
    const [rSnap, memberSnap, itemSnap] = await Promise.all(reads);
    const r = rSnap.exists ? (rSnap.data() || {}) : null;
    if (!r || r.status !== 'approved') throw fail('not-found', 'COMPLAINT_TARGET_NOT_FOUND');
    if (itemSnap && !itemSnap.exists) throw fail('not-found', 'COMPLAINT_TARGET_NOT_FOUND');
    if (canonicalUid(String(r.ownerUid || '')) === uid || memberSnap.exists) {
      throw fail('failed-precondition', 'COMPLAINT_OWN');
    }
    const name = itemSnap ? (itemSnap.data() || {}).name : r.name;
    return { title: str(name, 120) };
  }

  /**
   * data: { targetType: 'restaurant' | 'restaurant_item' | 'realty_listing', targetId, restaurantId? (таом учун),
   *         reason: REASONS, comment? (≤ 300; `other` да 3..300) } → { ok, reportId, duplicate? }.
   */
  exportsObj.submitContentComplaint = functions.https.onCall(async (data, context) => {
    const started = Date.now();
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    let p = null;
    try {
      p = parseComplaintInput(data, fail);
      const { title } = await resolveTarget(p, uid);

      const reports = db.collection(REPORTS);
      const dayStart = new Date();
      dayStart.setHours(0, 0, 0, 0);
      const today = await reports.where('type', '==', p.type).where('reporterId', '==', uid)
        .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(dayStart)).limit(DAILY_LIMIT + 1).get();
      if (today.size >= DAILY_LIMIT) throw fail('resource-exhausted', 'COMPLAINT_LIMIT');

      const keyRef = db.collection(OPEN_KEYS).doc(openKeyOf(p.type, uid, p.targetType, p.restaurantId, p.targetId));
      const out = await db.runTransaction(async (t) => {
        const key = await t.get(keyRef);
        const prevId = key.exists ? String((key.data() || {}).reportId || '') : '';
        if (prevId) {
          const prev = await t.get(reports.doc(prevId));
          if (prev.exists && (prev.data() || {}).status === 'open') return { reportId: prevId, duplicate: true };
        }
        const ref = reports.doc();
        t.set(ref, {
          type: p.type,
          targetType: p.targetType,
          targetId: p.targetId,
          ...(p.restaurantId ? { restaurantId: p.restaurantId } : {}),
          title,
          reporterId: uid,
          reason: p.reason,
          comment: p.comment,
          status: 'open',
          createdAt: ts(),
        });
        t.set(keyRef, { reportId: ref.id, type: p.type, updatedAt: ts() });
        return { reportId: ref.id, duplicate: false };
      });
      log({
        targetType: p.targetType, targetId: p.targetId, reportId: out.reportId,
        result: out.duplicate ? 'duplicate' : 'created', durationMs: Date.now() - started,
      });
      return out.duplicate ? { ok: true, reportId: out.reportId, duplicate: true } : { ok: true, reportId: out.reportId };
    } catch (e) {
      const errorCode = (e && e.details && e.details.code) || 'INTERNAL';
      log({
        targetType: p ? p.targetType : '', targetId: p ? p.targetId : '', result: 'rejected', errorCode,
        durationMs: Date.now() - started,
      });
      if (e instanceof HttpsError) throw e;
      console.error(JSON.stringify({ module: 'content_complaints', action: 'submitContentComplaint', error: String(e && e.message) }));
      throw new HttpsError('internal', 'INTERNAL', { code: 'INTERNAL' });
    }
  });
}

module.exports = {
  attachContentComplaints, parseComplaintInput, openKeyOf, TYPE_OF, TARGET_TYPES, REASONS, COMMENT_MAX, DAILY_LIMIT,
};
