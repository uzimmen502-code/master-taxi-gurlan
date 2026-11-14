/**
 * Bir martalik migratsiya: ochiq hujjatdagi taxminiy nuqtani qayta hisoblash.
 *
 *   node functions/tools/migrate_realty_jitter.js          # faqat ko'rsatadi
 *   node functions/tools/migrate_realty_jitter.js --apply  # yozadi
 *
 * NEGA KERAK. Boshida ochiq hujjatdagi `areaLat/areaLng` geohash4
 * katakchasining markazi edi (~20 km). Keyin har obyekt o'z pinini olishi
 * uchun u 1.2 km radiusdagi tasodifiy siljishga almashtirildi. Eski
 * yozuvlar esa hamon katakcha markazida turibdi — aniq joydan 10 km gacha
 * uzoqda, ya'ni xaritada butunlay boshqa yerni ko'rsatadi.
 *
 * Tahrirlash orqali tuzalmaydi: `updateRealtyListing` nuqta o'zgarmagan
 * bo'lsa ESKI siljishni ataylab saqlaydi (bir necha tahrirning o'rtachasi
 * aniq joyni ochib qo'ymasin uchun). Shuning uchun alohida migratsiya.
 *
 * Faqat siljishi chegaradan KATTA yozuvlarga tegadi — allaqachon to'g'ri
 * siljigan yozuvlar qayta siljitilmaydi.
 */
'use strict';

const admin = require('firebase-admin');
const sa = require('../service-account.json');

admin.initializeApp({ credential: admin.credential.cert(sa) });

/** `functions/realty.js` dagi bilan bir xil bo'lishi shart. */
const JITTER_METERS = 1200;

/** Shundan uzoq yozuv eski katakcha markazida deb hisoblanadi. */
const STALE_THRESHOLD_METERS = 1500;

const APPLY = process.argv.includes('--apply');

function jitteredPoint(lat, lng) {
  const angle = Math.random() * 2 * Math.PI;
  const dist = Math.sqrt(Math.random()) * JITTER_METERS;
  const dLat = (dist * Math.cos(angle)) / 111320;
  const dLng = (dist * Math.sin(angle))
    / (111320 * Math.cos((lat * Math.PI) / 180) || 1);
  const round3 = (v) => Number(v.toFixed(3));
  return { lat: round3(lat + dLat), lng: round3(lng + dLng) };
}

function distMeters(aLat, aLng, bLat, bLng) {
  const R = 6371000;
  const p = Math.PI / 180;
  const dLat = (bLat - aLat) * p;
  const dLng = (bLng - aLng) * p;
  const x = Math.sin(dLat / 2) ** 2
    + Math.cos(aLat * p) * Math.cos(bLat * p) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(x)));
}

(async () => {
  const db = admin.firestore();
  const snap = await db.collection('realty_listings').get();
  console.log(`${APPLY ? 'YOZISH' : 'KO\'RSATISH'} rejimi · ${snap.size} ta e'lon\n`);

  let fixed = 0;
  let skipped = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const priv = await doc.ref.collection('private').doc('detail').get();
    const p = priv.data() || {};
    const lat = Number(p.lat);
    const lng = Number(p.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      console.log(`  ?  ${doc.id} — yopiq hujjatda koordinata yo'q`);
      skipped += 1;
      continue;
    }
    const curLat = Number(d.areaLat);
    const curLng = Number(d.areaLng);
    const shift = Number.isFinite(curLat) && Number.isFinite(curLng)
      ? distMeters(lat, lng, curLat, curLng)
      : Infinity;

    if (shift <= STALE_THRESHOLD_METERS) {
      console.log(`  ok ${doc.id} — siljish ${shift} m, tegilmaydi`);
      skipped += 1;
      continue;
    }

    const next = jitteredPoint(lat, lng);
    const newShift = distMeters(lat, lng, next.lat, next.lng);
    console.log(
      `  →  ${doc.id} — ${shift} m → ${newShift} m`
      + `  (${curLat},${curLng} → ${next.lat},${next.lng})`,
    );
    if (APPLY) {
      await doc.ref.update({
        areaLat: next.lat,
        areaLng: next.lng,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    fixed += 1;
  }

  console.log(
    `\n${APPLY ? 'Yozildi' : 'Yoziladi'}: ${fixed} · tegilmadi: ${skipped}`,
  );
  if (!APPLY && fixed > 0) console.log('Yozish uchun: --apply');
  process.exit(0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
