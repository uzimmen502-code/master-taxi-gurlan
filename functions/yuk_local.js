'use strict';

/**
 * Туман ичида юк (`yuk_local_drivers`) — Cloud Functions қисми.
 *
 * Ҳозирча фақат намойиш (demo) эълонлари backfill'и: клиент кўриниши =
 * GPS + иш вақти + expiresAt (онлайн модель йўқ). Demo ҳеч қачон expire
 * қилинмайди (client isDemo) — бу job эски demo ҳужжатларга бут кун иш вақти
 * ва узоқ expiresAt ёзади, legacy online/lastOnlineAt майдонларини ўчиради.
 *
 * Deploy бирлиги ўзгармаган — index.js require қилади.
 */
const BATCH_LIMIT = 450;
const DEMO_TTL_MS = 180 * 24 * 60 * 60 * 1000;

function attachYukLocal(exportsObj, deps) {
  const { functions, db, admin } = deps;

  exportsObj.refreshYukDemoPresence = functions.pubsub
    .schedule('every 10 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      const snap = await db.collection('yuk_local_drivers')
        .where('isDemo', '==', true)
        .get();
      if (snap.empty) return null;

      const now = admin.firestore.FieldValue.serverTimestamp();
      const far = admin.firestore.Timestamp.fromMillis(Date.now() + DEMO_TTL_MS);
      let batch = db.batch();
      let writes = 0;
      for (const doc of snap.docs) {
        batch.set(
          doc.ref,
          {
            workStartMinutes: 0,
            workEndMinutes: 24 * 60,
            expiresAt: far,
            updatedAt: now,
            online: admin.firestore.FieldValue.delete(),
            lastOnlineAt: admin.firestore.FieldValue.delete(),
          },
          { merge: true },
        );
        writes += 1;
        if (writes >= BATCH_LIMIT) {
          await batch.commit();
          batch = db.batch();
          writes = 0;
        }
      }
      if (writes > 0) await batch.commit();
      console.log(`refreshYukDemoPresence: total=${snap.size}`);
      return null;
    });
}

module.exports = { attachYukLocal };
