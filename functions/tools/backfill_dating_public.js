/**
 * `dating_profiles_public` — mavjud profillardan ochiq ko'chirmani qurish.
 *
 * Nega kerak: bosh sahifadagi 9-bo'lim endi to'liq `dating_profiles` emas,
 * shu ko'chirmani o'qiydi (unda faqat ism, jins va tug'ilgan yil bor —
 * foto va shahar umuman yo'q). Yangi/o'zgargan profillarni CF
 * `onDatingProfileWriteSyncPublic` o'zi yuritadi; bu skript faqat
 * TRIGGER QO'YILGUNGA QADAR mavjud bo'lgan profillar uchun.
 *
 * Idempotent: mos ko'chirma allaqachon bor bo'lsa tegilmaydi. Ko'rinmasligi
 * kerak bo'lgan (status != approved yoki active == false) profilning eski
 * ko'chirmasi esa o'chiriladi.
 *
 *   node functions/tools/backfill_dating_public.js --dry
 *   node functions/tools/backfill_dating_public.js
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DRY = process.argv.includes('--dry');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

/** CF dagi bilan bir xil ko'chirma. */
function publicCopy(d) {
  return {
    displayName: String(d.displayName || '').slice(0, 60),
    gender: String(d.gender || ''),
    birthYear: Number(d.birthYear) || 0,
    lastActive: d.lastActive || null,
  };
}

function sameCopy(a, b) {
  if (!a || !b) return false;
  const at = a.lastActive ? a.lastActive.toMillis() : 0;
  const bt = b.lastActive ? b.lastActive.toMillis() : 0;
  return a.displayName === b.displayName
    && a.gender === b.gender
    && Number(a.birthYear) === Number(b.birthYear)
    && at === bt;
}

async function main() {
  const snap = await db.collection('dating_profiles').get();
  console.log(`Jami profil: ${snap.size}`);

  let planned = 0;
  let removed = 0;
  let skipped = 0;
  let written = 0;

  let batch = db.batch();
  let inBatch = 0;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const visible = d.status === 'approved' && d.active !== false;
    const ref = db.collection('dating_profiles_public').doc(doc.id);
    const cur = await ref.get();

    if (!visible) {
      if (!cur.exists) { skipped++; continue; }
      removed++;
      if (DRY) continue;
      batch.delete(ref);
      inBatch++;
    } else {
      const copy = publicCopy(d);
      if (cur.exists && sameCopy(cur.data(), copy)) { skipped++; continue; }
      planned++;
      if (DRY) continue;
      if (!copy.lastActive) {
        copy.lastActive = admin.firestore.FieldValue.serverTimestamp();
      }
      batch.set(ref, copy);
      inBatch++;
    }

    if (inBatch >= 400) {
      await batch.commit();
      written += inBatch;
      batch = db.batch();
      inBatch = 0;
    }
  }

  if (!DRY && inBatch > 0) {
    await batch.commit();
    written += inBatch;
  }

  console.log('');
  console.log(`  tegilmadi (mos)    : ${skipped}`);
  console.log(`  ko'chirma          : ${planned}`);
  console.log(`  o'chiriladi        : ${removed}`);
  if (!DRY) console.log(`  yozildi (jami)     : ${written}`);
  if (DRY) console.log('\n(--dry: hech narsa yozilmadi)');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
