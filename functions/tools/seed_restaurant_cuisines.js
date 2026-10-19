/**
 * `restaurant_cuisines/{id}` — TAYYOR kuxnalarni kiritish (D-REST-24, ega 2026-10-19).
 *
 * «Milliy» va «Dunyo» — ikkita alohida bo'lim; sotuvchi shu ro'yxatdan tanlaydi yoki
 * O'Z nomini qo'shadi (`restaurantAddCuisine`). Tayyor kuxnalarning 3 tildagi nomi
 * (`names`) shu yerda — admin keyin Firestore'dan emas, shu skript orqali kengaytiradi.
 *
 * Xavfsizlik (28, 27-qoida):
 *   - DRY RUN — standart: nima yaratilishi, nima allaqachon borligi chiqadi, hech narsa yozilmaydi.
 *   - `--apply` faqat YO'Q hujjatni yaratadi (`create`); BOR hujjatga TEGMAYDI
 *     (admin yashirgan/tahrirlagan nom o'zgarmaydi) — takror ishga tushirish xavfsiz (idempotent).
 *   - Hujjat identifikatori `restaurantAddCuisine` bilan BIR XIL funksiyadan (`cuisineDocId`),
 *     shuning uchun sotuvchi «O'zbek» deb yozsa shu tayyor hujjatga tushadi.
 *
 * Ishlatish:
 *   node functions/tools/seed_restaurant_cuisines.js            # dry run
 *   node functions/tools/seed_restaurant_cuisines.js --apply
 *
 * Production'ga yozish — ega ruxsati bilan (28-qoida); emulator uchun FIRESTORE_EMULATOR_HOST.
 */
'use strict';

const { cuisineKey, cuisineDocId } = require('../restaurant_cuisines');

/** [guruh, uz_Cyrl, uz_Latn, ru] — ro'yxat ega tasdig'ida o'zgarishi mumkin (PROPOSED). */
const PRESETS = Object.freeze([
  ['national', 'Ўзбек', "O'zbek", 'Узбекская'],
  ['national', 'Хоразм', 'Xorazm', 'Хорезмская'],
  ['national', 'Фарғона', "Farg'ona", 'Ферганская'],
  ['national', 'Самарқанд-Бухоро', 'Samarqand-Buxoro', 'Самаркандско-бухарская'],
  ['national', 'Қорақалпоқ', 'Qoraqalpoq', 'Каракалпакская'],
  ['national', 'Бошқа миллий', 'Boshqa milliy', 'Другая национальная'],
  ['world', 'Турк', 'Turk', 'Турецкая'],
  // Лотинда «Evropa» (кирилл «Европа» кўриниши билан бир хил калит беради — қуйидаги текширув).
  ['world', 'Рус-Европа', 'Rus-Evropa', 'Русско-европейская'],
  ['world', 'Итальян', 'Italyan', 'Итальянская'],
  ['world', 'Корейс', 'Koreys', 'Корейская'],
  ['world', 'Хитой', 'Xitoy', 'Китайская'],
  ['world', 'Япон', 'Yapon', 'Японская'],
  ['world', 'Америка', 'Amerika', 'Американская'],
  ['world', 'Араб', 'Arab', 'Арабская'],
  ['world', 'Ҳинд', 'Hind', 'Индийская'],
  ['world', 'Бошқа', 'Boshqa', 'Другая'],
]);

/** Соф: [{ id, data }] — `id` ва `nameKey` тугаллик текшируви билан. */
function buildDocs(presets = PRESETS) {
  const seen = new Set();
  return presets.map(([group, cyrl, latn, ru]) => {
    const key = cuisineKey(latn);
    const id = cuisineDocId(group, key);
    if (key.length < 2 || seen.has(id)) throw new Error(`Noto'g'ri yoki takror kuxna: ${group}/${latn} → ${id}`);
    // Lotin va kirill yozuvi BIR XIL kalit berishi shart — aks holda sotuvchi kirillcha yozsa
    // tayyor kuxnaga tushmay, takror yaratar edi.
    if (cuisineKey(cyrl) !== key) throw new Error(`Kirill/lotin kaliti mos emas: ${cyrl} (${cuisineKey(cyrl)}) ≠ ${latn} (${key})`);
    seen.add(id);
    return {
      id,
      data: {
        name: cyrl,
        nameKey: key,
        group,
        names: { uz_Cyrl: cyrl, uz_Latn: latn, ru },
        custom: false,
        hidden: false,
        createdBy: 'seed',
      },
    };
  });
}

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-seed' });
    } else {
      const sa = path.join(__dirname, '..', 'service-account.json');
      admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
    }
  }
  const db = admin.firestore();
  const APPLY = process.argv.includes('--apply');
  const docs = buildDocs();

  console.log(`${APPLY ? 'APPLY' : 'DRY RUN'} — ${docs.length} ta tayyor kuxna`);
  let created = 0;
  let existing = 0;
  for (const { id, data } of docs) {
    const ref = db.collection('restaurant_cuisines').doc(id);
    const snap = await ref.get();
    if (snap.exists) {
      existing += 1;
      console.log(`  bor      ${id}`);
      continue;
    }
    console.log(`  ${APPLY ? 'YARATILDI' : 'yaratiladi'} ${id}  (${data.names.uz_Latn})`);
    if (APPLY) {
      await ref.create({ ...data, createdAt: admin.firestore.FieldValue.serverTimestamp() });
    }
    created += 1;
  }
  console.log(`Natija: ${APPLY ? 'yaratildi' : 'yaratilardi'} ${created}, allaqachon bor ${existing}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { PRESETS, buildDocs };
