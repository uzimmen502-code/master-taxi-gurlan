/**
 * KO'CHMAS MULK — e'lon o'chirilsa uning videosi ham o'chadi (ega qarori 2026-10-19:
 * «Агар эълон ўчирилса видео ҳам ўчирилади»).
 *
 * E'lon hujjati `realty_listings/{listingId}` o'chirilganda unga bog'langan AVAGram klip(lar)i
 * (`tv_clips`: `linkKind == 'realty_listing'`, `linkId == listingId`) o'chiriladi. Klip hujjati
 * o'chgach mavjud `onTvClipDeleted` triggeri fayllarni (Storage/R2), CDN keshini, do'kon
 * havolasini va ko'rishlar hisobini o'zi tozalaydi — bu yerda MEDIA'ga tegilmaydi (yagona
 * o'chirish yo'li, 7-qoida). Naqsh — `restaurant_dish_video.js` (D-REST-30) bilan bir xil.
 *
 * E'lon bugun FAQAT qattiq o'chiriladi (soft-delete yo'q) va uch yo'ldan: egasi
 * (`deleteRealtyListing`), admin (`adminDeleteRealtyListing`) va muddat tugashi
 * (`realtyExpirySweep`) — hammasi `deleteListingDeep` → `ref.delete()`. Shu uchun BITTA
 * Firestore triggeri uchala yo'lni ham qoplaydi, `realty.js` ga tegilmaydi. «Blocked»/«pending»
 * holatlar o'chirish HISOBLANMAYDI (klipga tegilmaydi).
 *
 * Nima uchun SERVERDA, klientda emas: klipni boshqa jamoa a'zosi yuklagan bo'lishi mumkin va
 * qoidaga ko'ra klipni faqat uning egasi o'chira oladi; muddat tugashida esa klient umuman
 * yo'q (cron). Trigger Admin SDK bilan ishlaydi va klientga ishonmaydi (18-qoida).
 *
 * Eski, mavjud «o'z klipini e'longa ulash» yo'li (`linkRealtyVideo`: `avagramClipId`/`adClipId`)
 * bilan ulangan klipga TEGILMAYDI — u egasining mustaqil klipi (pullik reklama bo'lishi ham
 * mumkin) va `unlinkRealtyVideo` ham klipni o'chirmaydi. Bu ega bilan tasdiqlanishi kerak.
 *
 * Idempotent (21-qoida): qayta ishga tushsa topadigan klip qolmagan bo'ladi. Log:
 * `action: 'realty_video_cleanup'`, `listingId`, `deleted`; klip id/telefon yozilmaydi (40-qoida).
 */
'use strict';

const CLIPS = 'tv_clips';
const REALTY_LINK_KIND = 'realty_listing';
/** Bitta o'qishda eng ko'pi; e'londa 1 ta bo'ladi, qolgani — himoya (takror yuklash). */
const PAGE = 100;
const MAX_ROUNDS = 5;

function attachRealtyVideoCleanup(exportsObj, deps) {
  const { functions, db } = deps;

  /** [listingId] ga bog'langan barcha klip hujjatlarini o'chiradi; o'chirilganlar soni. */
  async function deleteListingClips(listingId) {
    let deleted = 0;
    for (let round = 0; round < MAX_ROUNDS; round += 1) {
      const snap = await db.collection(CLIPS)
        .where('linkKind', '==', REALTY_LINK_KIND)
        .where('linkId', '==', listingId)
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

  exportsObj.onRealtyListingDeleted = functions.firestore
    .document('realty_listings/{listingId}')
    .onDelete(async (snap, context) => {
      const { listingId } = context.params;
      const t0 = Date.now();
      try {
        const deleted = await deleteListingClips(listingId);
        console.log(JSON.stringify({
          module: 'realty', action: 'realty_video_cleanup', listingId,
          deleted, result: 'ok', durationMs: Date.now() - t0,
        }));
      } catch (e) {
        // E'lon allaqachon o'chgan — xato uni tiklamaydi; klip yetim qolishi mumkin, admin ko'radi.
        console.error(JSON.stringify({
          module: 'realty', action: 'realty_video_cleanup', listingId,
          result: 'error', errorCode: 'REALTY_VIDEO_CLEANUP_FAILED',
          message: String((e && e.message) || e).slice(0, 160),
        }));
      }
      return null;
    });
}

module.exports = { attachRealtyVideoCleanup, REALTY_LINK_KIND };
