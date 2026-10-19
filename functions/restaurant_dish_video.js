/**
 * KAFE-RESTORAN — taom o'chirilsa uning videosi ham o'chadi (D-REST-30, ega 2026-10-19:
 * «таом ўчирилса видеоси ҳам бирга ўчирилсин»).
 *
 * Taom hujjati `restaurants/{rid}/menu_items/{iid}` o'chirilganda unga bog'langan AVAGram klip(lar)i
 * (`tv_clips`: `linkKind == 'restaurant_item'`, `linkId == rid`, `linkItemId == iid`) o'chiriladi.
 * Klip hujjati o'chgach mavjud `onTvClipDeleted` triggeri fayllarni (Storage/R2), CDN keshini,
 * do'kon havolasini va ko'rishlar hisobini o'zi tozalaydi — bu yerda MEDIA'ga tegilmaydi (yagona
 * o'chirish yo'li, 7-qoida).
 *
 * Nima uchun SERVERDA, klientda emas: klipni boshqa xodim yuklagan bo'lishi mumkin va qoidaga ko'ra
 * klipni faqat uning egasi o'chira oladi; ega taomni o'chirganda xodim klipini o'chira olmasdi.
 * Trigger Admin SDK bilan ishlaydi va klientga ishonmaydi (18-qoida).
 *
 * Idempotent (21-qoida): qayta ishga tushsa topadigan klip qolmagan bo'ladi. Ichki-kod: log'da
 * `action: 'dish_video_cleanup'`, `restaurantId`, `itemId`, `deleted`; klip id/telefon yozilmaydi.
 */
'use strict';

const CLIPS = 'tv_clips';
const ITEM_LINK_KIND = 'restaurant_item';
/** Bitta o'qishda eng ko'pi; taomda 1 ta bo'ladi, qolgani — himoya (takror yuklash). */
const PAGE = 100;
const MAX_ROUNDS = 5;

function attachRestaurantDishVideoCleanup(exportsObj, deps) {
  const { functions, db } = deps;

  /** [rid]/[iid] ga bog'langan barcha klip hujjatlarini o'chiradi; o'chirilganlar soni. */
  async function deleteItemClips(rid, iid) {
    let deleted = 0;
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      const snap = await db.collection(CLIPS)
        .where('linkKind', '==', ITEM_LINK_KIND)
        .where('linkId', '==', rid)
        .where('linkItemId', '==', iid)
        .limit(PAGE)
        .get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < PAGE) break;
    }
    return deleted;
  }

  exportsObj.onRestaurantMenuItemDeleted = functions.firestore
    .document('restaurants/{rid}/menu_items/{iid}')
    .onDelete(async (snap, context) => {
      const { rid, iid } = context.params;
      const t0 = Date.now();
      try {
        const deleted = await deleteItemClips(rid, iid);
        console.log(JSON.stringify({
          module: 'restaurants', action: 'dish_video_cleanup', restaurantId: rid, itemId: iid,
          deleted, result: 'ok', durationMs: Date.now() - t0,
        }));
      } catch (e) {
        // Taom allaqachon o'chgan — xato uni tiklamaydi; klip yetim qolishi mumkin, admin ko'radi.
        console.error(JSON.stringify({
          module: 'restaurants', action: 'dish_video_cleanup', restaurantId: rid, itemId: iid,
          result: 'error', errorCode: 'CLEANUP_FAILED', message: String((e && e.message) || e).slice(0, 160),
        }));
      }
      return null;
    });
}

module.exports = { attachRestaurantDishVideoCleanup, ITEM_LINK_KIND };
