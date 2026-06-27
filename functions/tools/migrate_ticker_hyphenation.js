/**
 * `home_ticker_ads` collectionidagi mavjud (avval seed qilingan) matnlarni
 * bo'g'in ko'chirish (soft hyphen, \u00AD) qo'shilgan yangi versiyaga
 * yangilaydi. Matn solishtirish soft hyphenlarni olib tashlab (oddiy matn
 * bo'yicha) amalga oshiriladi, shuning uchun eski (hyphensiz) va yangi
 * (hyphenli) matnlar bir xil hujjat deb topiladi.
 *
 * Ishlatish (root'dan):
 *   node functions/tools/migrate_ticker_hyphenation.js
 */
const path = require('path');
const admin = require('firebase-admin');

const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

const { TEXTS: HOME_SEARCH_TEXTS } = require('./seed_home_search_ticker.js');

function stripSoftHyphen(s) {
  return (s || '').replace(/\u00AD/g, '');
}

async function migrateModule(moduleName, hyphenatedTexts) {
  const col = db.collection('home_ticker_ads');
  const snap = await col.where('module', '==', moduleName).get();

  const byPlain = new Map();
  for (const t of hyphenatedTexts) {
    byPlain.set(stripSoftHyphen(t), t);
  }

  let updated = 0;
  let skipped = 0;
  const batch = db.batch();

  snap.docs.forEach((doc) => {
    const current = doc.data().text || '';
    const plain = stripSoftHyphen(current);
    const hyphenated = byPlain.get(plain);
    if (!hyphenated) {
      skipped++;
      return;
    }
    if (current === hyphenated) {
      skipped++;
      return;
    }
    batch.update(doc.ref, {
      text: hyphenated,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updated++;
  });

  if (updated > 0) await batch.commit();
  console.log(`[${moduleName}] Янгиланди: ${updated}, ўтказиб юборилди: ${skipped}`);
}

async function main() {
  await migrateModule('home_search', HOME_SEARCH_TEXTS);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Хатолик:', e);
    process.exit(1);
  });
