/**
 * `settings/restaurant_sections` — bo'limlarni yoqish (S3, D-REST-33; ega «оч» dedi, 2026-10-19).
 *
 * Admin callable (`adminSetRestaurantSections`) faqat admin tokeni bilan chaqiriladi; bu skript xuddi shu
 * `mergeConfig` bilan XUDDI SHU yozuvlarni (sozlama + `restaurant_sections_history/v{n}` + `admin_audit`)
 * Admin SDK orqali yozadi — qo'lda yozilgan hujjat emas, CF mantiqi.
 *
 * Xavfsizlik (28, 41-qoida):
 *   - DRY RUN — standart: nima yozilishi chiqadi, hech narsa yozilmaydi.
 *   - `--apply`: FAQAT hujjat hali yo'q bo'lsa yaratadi; bor bo'lsa to'xtaydi (admin o'zgartirgan sozlama
 *     ustidan yozilmaydi — o'zgartirish uchun admin paneli/CF).
 *   - Audit yozuvi: actor = `script:enable_restaurant_sections`, sabab matni bilan.
 *
 * Ishlatish:
 *   node functions/tools/enable_restaurant_sections.js [--stage=public|internal] [--apply]
 */
'use strict';

const { mergeConfig, CONFIG_DOC } = require('../restaurant_sections_config');
const { SECTION_KEYS } = require('../restaurant_dish_index');

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-sections' });
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
  const cfg = mergeConfig({ sections: Object.fromEntries(SECTION_KEYS.map((k) => [k, stageArg])) }, {}, { fail, canonicalUid });
  const reason = `Ega buyrug'i 2026-10-19: bo'limlar ${stageArg}`;
  const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
  const snap = await ref.get();
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} — settings/restaurant_sections`);
  console.log(JSON.stringify(cfg));
  if (snap.exists) {
    console.log(`Hujjat BOR (versiya ${(snap.data() || {}).version}) — tegilmaydi.`);
    return;
  }
  if (!apply) { console.log('Yaratiladi: v1 + tarix + audit'); return; }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const actor = 'script:enable_restaurant_sections';
  await db.runTransaction(async (t) => {
    const again = await t.get(ref);
    if (again.exists) throw new Error('Hujjat parallel yaratildi — to\'xtadi');
    const doc = { ...cfg, version: 1, reason, updatedAt: ts, updatedBy: actor };
    t.create(ref, doc);
    t.create(db.collection('restaurant_sections_history').doc('v1'), { ...doc, previous: null });
    t.set(db.collection('admin_audit').doc(), { kind: 'restaurant_sections_set', actor, target: 'v1', reason, at: ts });
  });
  console.log('YARATILDI: v1');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
