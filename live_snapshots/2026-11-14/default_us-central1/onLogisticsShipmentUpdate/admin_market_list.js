'use strict';
/**
 * Admin web — «Аҳоли бозори» рўйхати саҳифалаб (`adminListMarketAds`).
 *
 * Эга, 2026-10-08: рўйхат 500 та билан очилади, «Яна юклаш» кейинги 500
 * тасини олиб келади. Лимитни катталаштириш ўрнига — жавоб ҳажми чекланган,
 * ҳар саҳифа бир марта ўқилади.
 *
 * Тартиб: createdAt DESC, кейин ҳужжат ID DESC — бир хил вақтли эълонлар
 * саҳифа чегарасида тушиб қолмасин ва такрорланмасин. Индекс:
 * ads (type ASC, createdAt DESC); Firestore унга __name__ ни охирги майдон
 * йўналишида (DESC) ўзи қўшади.
 *
 * Курсор — олдинги жавобдаги `nextCursor` ({ seconds, nanos, id }); клиент
 * уни ўзгартирмасдан қайтаради. `after`сиз чақирув — аввалгидек биринчи
 * саҳифа: эски админ саҳифаси шундай чақиради ва `nextCursor`ни ўқимайди.
 * Саҳифа ҳажмини клиент белгиламайди.
 */

const MARKET_ADS_ADMIN_PAGE = 500;

// Firestore Timestamp чегаралари (0001-01-01 … 9999-12-31).
const MIN_SECONDS = -62135596800;
const MAX_SECONDS = 253402300799;

/**
 * Клиентдан келган курсор → `{ createdAt: Timestamp, id }` ёки `null`.
 * Нотўғри курсор — `invalid-argument` (жимгина биринчи саҳифага қайтмайди).
 */
function parseMarketAdsCursor(raw, { admin, functions }) {
  if (raw == null) return null;
  const seconds = Number(raw.seconds);
  const nanos = Number(raw.nanos);
  const id = typeof raw.id === 'string' ? raw.id.trim() : '';
  if (!Number.isSafeInteger(seconds) || seconds < MIN_SECONDS || seconds > MAX_SECONDS ||
      !Number.isInteger(nanos) || nanos < 0 || nanos > 999999999 ||
      !id || id.includes('/')) {
    throw new functions.https.HttpsError('invalid-argument', 'MARKET_ADS_BAD_CURSOR');
  }
  return { createdAt: new admin.firestore.Timestamp(seconds, nanos), id };
}

/** Саҳифа тўлган бўлса — кейингиси учун курсор, акс ҳолда `null`. */
function marketAdsNextCursor(docs, pageSize, { admin }) {
  if (docs.length < pageSize) return null;
  const last = docs[docs.length - 1];
  const ts = last.get('createdAt');
  if (!(ts instanceof admin.firestore.Timestamp)) {
    // `createdAt` ни сервер ёзади (serverTimestamp) — бу ҳолат кутилмайди.
    console.warn(JSON.stringify({
      action: 'adminListMarketAds',
      result: 'no_next_cursor',
      errorCode: 'MARKET_ADS_CURSOR_NOT_TIMESTAMP',
      adId: last.id,
    }));
    return null;
  }
  return { seconds: ts.seconds, nanos: ts.nanoseconds, id: last.id };
}

/** Битта саҳифа: `{ docs, nextCursor }`. */
async function listMarketAdsPage(db, { admin }, { after = null, pageSize = MARKET_ADS_ADMIN_PAGE } = {}) {
  let q = db.collection('ads')
    .where('type', '==', 'cheap_product')
    .orderBy('createdAt', 'desc')
    .orderBy(admin.firestore.FieldPath.documentId(), 'desc');
  if (after) q = q.startAfter(after.createdAt, after.id);
  const snap = await q.limit(pageSize).get();
  return { docs: snap.docs, nextCursor: marketAdsNextCursor(snap.docs, pageSize, { admin }) };
}

module.exports = {
  MARKET_ADS_ADMIN_PAGE,
  parseMarketAdsCursor,
  marketAdsNextCursor,
  listMarketAdsPage,
};
