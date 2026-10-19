/**
 * `settings/restaurant_bookings` — stol bronni yoqish (S5, D-REST-23/38; ega «hammasini oxiriga yetkaz», 2026-10-19).
 *
 * Admin callable (`adminSetRestaurantBookings`) faqat admin tokeni bilan chaqiriladi; bu skript xuddi shu
 * `mergeConfig` bilan XUDDI SHU yozuvlarni (sozlama + `restaurant_bookings_history/v{n}` + `admin_audit`)
 * Admin SDK orqali yozadi — qo'lda yozilgan hujjat emas, CF mantiqi. Tarif — eganing qarori (50k/150k/400k).
 *
 * Xavfsizlik (28, 41-qoida):
 *   - DRY RUN — standart: nima yozilishi chiqadi, hech narsa yozilmaydi.
 *   - `--apply`: FAQAT hujjat hali yo'q bo'lsa yaratadi; bor bo'lsa to'xtaydi (admin o'zgartirgan sozlama
 *     ustidan yozilmaydi — o'zgartirish uchun CF).
 *   - Restoranlar bronni o'zlari yoqadi (`acceptsBookings` standart — yo'q); shuning uchun yoqish zararsiz.
 *
 * Ishlatish:
 *   node functions/tools/enable_restaurant_bookings.js [--stage=public|internal] [--apply]
 */
'use strict';

const { mergeConfig, CONFIG_DOC } = require('../restaurant_bookings');

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-bookings' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');
  const stageArg = (process.argv.find((a) => a.startsWith('--stage=')) || '--stage=public').split('=')[1];
  if (!['public', 'internal'].includes(stageArg)) throw new Error(`stage noto'g'ri: ${stageArg}`);

  const fail = (status, code) => new Error(`${status}/${code}`);
  const canonicalUid = (x) => String(x || '').replace(/\D/g, '');
  const cfg = mergeConfig({ stage: stageArg }, {}, { fail, canonicalUid });
  const reason = `Ega buyrug'i 2026-10-19: stol bron ${stageArg}`;
  const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
  const snap = await ref.get();
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} — settings/restaurant_bookings`);
  console.log(JSON.stringify(cfg));
  if (snap.exists) {
    console.log(`Hujjat BOR (versiya ${(snap.data() || {}).version}) — tegilmaydi.`);
    return;
  }
  if (!apply) { console.log('Yaratiladi: v1 + tarix + audit'); return; }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const actor = 'script:enable_restaurant_bookings';
  await db.runTransaction(async (t) => {
    const again = await t.get(ref);
    if (again.exists) throw new Error('Hujjat parallel yaratildi — to\'xtadi');
    const doc = { ...cfg, version: 1, reason, updatedAt: ts, updatedBy: actor };
    t.create(ref, doc);
    t.create(db.collection('restaurant_bookings_history').doc('v1'), { ...doc, previous: null });
    t.set(db.collection('admin_audit').doc(), { kind: 'restaurant_bookings_set', actor, target: 'v1', reason, at: ts });
  });
  console.log('YARATILDI: v1');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
