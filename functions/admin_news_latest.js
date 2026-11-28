/**
 * «Хабарлар»да фақат ОХИРГИ эслатма қолсин, эскилари ўрнига ёзилсин (эга 2026-11-28).
 *
 * Детерминистик ID ли `admin_news/{newsId}` ҳужжатини ТЎЛИҚ алмаштиради (merge эмас): эски майдонлар
 * (retractedAt, pushResendAt, promptDay …) қолмайди, `createdAt` янги — илова хабарни ўқилмаган ва тепада
 * кўрсатади (клиент: `createdAt > users.last*ReadAt` = ўқилмаган, `orderBy('createdAt', desc)`; ҳужжатда
 * «ўқилди» белгиси ЙЎҚ — news_repository.dart).
 *
 * `onAdminNewsCreate` фақат ЯРАТИЛИШда ишлайди (badge `homeBadgePersonal` +1). Алмаштиришда (update) у
 * ишламайди — шунинг учун `existed: true` қайтарилади ва чақирувчи badge'ни ўзи оширади. Push ҳамма ҳолатда
 * `notifyUserInApp`нинг ўзида юборилади (`pushDirect: true`), `onAdminNewsUpdate` эса фақат
 * `pushResendAt` ўзгарса ишлайди (алмаштиришда у майдон йўқолади → afterMs 0 → push такрорланмайди).
 */
'use strict';

const NEWS_ID_RE = /^[A-Za-z0-9_-]{1,140}$/;

/** true — ID яроқли (Firestore ҳужжат ID; `/` ва бошқа белгилар йўқ). */
const validNewsId = (id) => typeof id === 'string' && NEWS_ID_RE.test(id);

/**
 * Транзакцияда: бор-йўқлигини ўқиб, ҳужжатни тўлиқ алмаштиради. Қайтаради `{ existed }`.
 * Транзакция қайта уринилса ҳам натижа битта ҳужжат (идемпотент).
 */
async function replaceLatestNews(db, newsId, data) {
  if (!validNewsId(newsId)) throw new Error(`ADMIN_NEWS_ID_INVALID ${String(newsId).slice(0, 40)}`);
  const ref = db.collection('admin_news').doc(newsId);
  const existed = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    t.set(ref, data);
    return snap.exists;
  });
  return { existed };
}

module.exports = { replaceLatestNews, validNewsId };
