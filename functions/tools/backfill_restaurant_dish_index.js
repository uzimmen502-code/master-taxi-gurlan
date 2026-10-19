/**
 * `restaurant_dish_index` — mavjud menyularni BIR MARTA indekslash (S3, D-REST-33).
 *
 * Triggerlar (`functions/restaurant_dish_index.js`) faqat deploydan KEYINGI o'zgarishlarni tutadi; deploydan
 * oldin yozilgan taomlar uchun indeks hujjati yo'q. Bu skript xuddi shu `buildIndexDoc` bilan hammasini hisoblaydi
 * (qoida ikkita joyda emas, 7-qoida) va indeksni manbaga tenglashtiradi.
 *
 * Xavfsizlik (27, 28-qoida):
 *   - DRY RUN — standart: nima yoziladi/o'chiriladi/o'zgarmaydi chiqadi, hech narsa yozilmaydi.
 *   - `--apply` faqat `restaurant_dish_index` ga yozadi (manba hujjatlarga TEGMAYDI); takror ishga tushirish xavfsiz
 *     (o'zgarmagan hujjat yozilmaydi — idempotent). Tarqalish: restoran ketma-ket, 400 yozuvlik paketlar.
 *   - Yetim indeks hujjatlari (taomi yoki restorani yo'q) o'chiriladi — `--apply` bilan.
 *
 * Ishlatish:
 *   node functions/tools/backfill_restaurant_dish_index.js            # dry run
 *   node functions/tools/backfill_restaurant_dish_index.js --apply
 *
 * Production'ga yozish — ega ruxsati bilan (28-qoida); emulator uchun FIRESTORE_EMULATOR_HOST.
 */
'use strict';

const { buildIndexDoc, fingerprint, INDEX } = require('../restaurant_dish_index');

const BATCH = 400;

/** Sof o'zak (testlanadi): `db` — Firestore, `apply` — yozish. Natija: { written, deleted, unchanged, restaurants }. */
async function run(db, { apply = false, log = () => {} } = {}) {
  const counts = { written: 0, deleted: 0, unchanged: 0, restaurants: 0 };
  let batch = db.batch();
  let pending = 0;
  const flush = async () => {
    if (apply && pending > 0) await batch.commit();
    batch = db.batch();
    pending = 0;
  };
  const queue = async (fn) => {
    fn(batch);
    pending += 1;
    if (pending >= BATCH) await flush();
  };

  const wanted = new Set();
  const restaurants = await db.collection('restaurants').get();
  for (const r of restaurants.docs) {
    counts.restaurants += 1;
    const menu = await r.ref.collection('menu_items').get();
    for (const it of menu.docs) {
      const id = `${r.id}_${it.id}`;
      const [stats, cur] = await Promise.all([
        r.ref.collection('menu_item_stats').doc(it.id).get(),
        db.collection(INDEX).doc(id).get(),
      ]);
      const next = buildIndexDoc({
        rid: r.id, iid: it.id, item: it.data(), restaurant: r.data(), stats: stats.exists ? stats.data() : null,
      });
      if (next) wanted.add(id);
      if (!next) {
        if (cur.exists) {
          counts.deleted += 1;
          log(`  ${apply ? "O'CHIRILDI" : "o'chiriladi"} ${id}`);
          await queue((b) => b.delete(cur.ref));
        } else counts.unchanged += 1;
      } else if (cur.exists && fingerprint(cur.data()) === fingerprint(next)) {
        counts.unchanged += 1;
      } else {
        counts.written += 1;
        log(`  ${apply ? 'YOZILDI' : 'yoziladi'} ${id}  [${next.sections.join(',')}]`);
        await queue((b) => b.set(db.collection(INDEX).doc(id), next));
      }
    }
  }
  // Yetim hujjatlar: manba yo'q (taom/restoran o'chgan) yoki endi indeksga kirmaydi.
  const all = await db.collection(INDEX).get();
  for (const d of all.docs) {
    if (!wanted.has(d.id)) {
      // yuqorida o'chirilgan (cur.exists && !next) hujjatlar ham shu yerda emas: ularni ikkinchi marta sanamaymiz
      const src = d.data() || {};
      const sourceStillThere = src.restaurantId && src.itemId
        && (await db.collection('restaurants').doc(src.restaurantId).collection('menu_items').doc(src.itemId).get()).exists;
      if (!sourceStillThere) {
        counts.deleted += 1;
        log(`  ${apply ? "YETIM O'CHIRILDI" : "yetim o'chiriladi"} ${d.id}`);
        await queue((b) => b.delete(d.ref));
      }
    }
  }
  await flush();
  return counts;
}

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-backfill' });
    } else {
      const sa = path.join(__dirname, '..', 'service-account.json');
      admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
    }
  }
  const apply = process.argv.includes('--apply');
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} — restaurant_dish_index`);
  const c = await run(admin.firestore(), { apply, log: (s) => console.log(s) });
  console.log(`Natija: restoran ${c.restaurants}, ${apply ? 'yozildi' : 'yoziladi'} ${c.written}, ${apply ? "o'chirildi" : "o'chiriladi"} ${c.deleted}, o'zgarmagan ${c.unchanged}`);
}

if (require.main === module) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { run };
