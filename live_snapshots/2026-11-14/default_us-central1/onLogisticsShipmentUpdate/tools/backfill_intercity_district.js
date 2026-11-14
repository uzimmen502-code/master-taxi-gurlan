/**
 * `intercity_drivers` — eski reyslarga `districtId` / `regionId` yozadi.
 *
 * Hudud haydovchining `users/{...}` hujjatidan olinadi (ega tanlagan
 * variant: "(a) эга телефони орқали users.districtId дан"). Hujjat ID'si
 * haydovchining kanonik telefoni, plus `phoneDigits` maydoni ham bor.
 *
 * Nega kerak: bosh sahifadagi 4-bo'lim ("Shahararo taksi") reyslarni
 * `districtId` bo'yicha server tomonda filtrlaydi — "shu tumandan
 * chiqayotgan reyslar". Maydonsiz eski yozuvlar vaqtincha barcha tumanda
 * ko'rinadi.
 *
 * Yangi reyslarga hudud `SchedulesRepository.publishSchedule` ichida
 * allaqachon yoziladi — skript faqat ESKI yozuvlar uchun.
 *
 * Idempotent: `districtId` allaqachon bor hujjat tegilmaydi.
 *
 *   node functions/tools/backfill_intercity_district.js --dry
 *   node functions/tools/backfill_intercity_district.js
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

function phoneDigits(raw) {
  return String(raw || '').replace(/\D/g, '');
}

function aliases(raw) {
  const d = phoneDigits(raw);
  if (d.length < 9) return [];
  const out = new Set([d]);
  if (d.length === 12 && d.startsWith('998')) out.add(d.slice(3));
  if (d.length === 9) out.add(`998${d}`);
  return Array.from(out);
}

const userCache = new Map();

async function geoOfOwner(...candidates) {
  for (const raw of candidates) {
    for (const id of aliases(raw)) {
      if (userCache.has(id)) {
        const hit = userCache.get(id);
        if (hit) return hit;
        continue;
      }
      const snap = await db.collection('users').doc(id).get();
      if (!snap.exists) {
        userCache.set(id, null);
        continue;
      }
      const u = snap.data() || {};
      const districtId = String(u.districtId || '').trim();
      const geo = districtId
        ? { districtId, regionId: String(u.regionId || '').trim() }
        : null;
      userCache.set(id, geo);
      if (geo) return geo;
    }
  }
  return null;
}

async function main() {
  const snap = await db.collection('intercity_drivers').get();
  console.log(`Jami reys hujjati: ${snap.size}`);

  let skipped = 0;
  let noGeo = 0;
  let planned = 0;
  let written = 0;

  let batch = db.batch();
  let inBatch = 0;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (String(d.districtId || '').trim()) {
      skipped++;
      continue;
    }
    // Hujjat ID'si ham kanonik telefon bo'lishi mumkin.
    const geo = await geoOfOwner(d.phoneDigits, d.phone, doc.id);
    if (!geo) {
      noGeo++;
      console.warn(`  hudud topilmadi: ${doc.id} (phone=${d.phone || ''})`);
      continue;
    }
    planned++;
    if (DRY) continue;

    const patch = { districtId: geo.districtId };
    if (geo.regionId) patch.regionId = geo.regionId;
    batch.set(doc.ref, patch, { merge: true });
    inBatch++;
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
  console.log(`  allaqachon hududli : ${skipped}`);
  console.log(`  hudud topilmadi    : ${noGeo}`);
  console.log(DRY ? `  yozilardi          : ${planned}` : `  yozildi            : ${written}`);
  if (DRY) console.log('\n(--dry: hech narsa yozilmadi)');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
