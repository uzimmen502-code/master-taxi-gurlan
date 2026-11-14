/**
 * `yuk_local_drivers` — eski e'lonlarga `districtId` / `regionId` yozadi.
 *
 * Hudud e'lon egasining `users/{ownerId}` hujjatidan olinadi (ega
 * tanlagan variant: "(a) эга телефони орқали users.districtId дан").
 *
 * Nega kerak: bosh sahifadagi 5-bo'lim va `yuk_local` ekrani ro'yxatni
 * `districtId` bo'yicha server tomonda filtrlaydi. Maydonsiz eski
 * yozuvlar hozircha alohida oqimda kelib turadi (barcha tumanda
 * ko'rinadi) — shu skript ishlagach ular ham o'z tumaniga biriktiriladi
 * va o'sha vaqtinchalik oqimni olib tashlash mumkin bo'ladi.
 *
 * Idempotent: `districtId` allaqachon bor hujjat tegilmaydi.
 *
 *   node functions/tools/backfill_yuk_local_district.js --dry
 *   node functions/tools/backfill_yuk_local_district.js
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

/** `+998 90 123 45 67` / `901234567` -> `998901234567`. */
function phoneDigits(raw) {
  return String(raw || '').replace(/\D/g, '');
}

/** users hujjati 9 yoki 12 raqamli ID bilan yozilgan bo'lishi mumkin. */
function ownerAliases(ownerId) {
  const d = phoneDigits(ownerId);
  if (!d) return [];
  const out = new Set([d]);
  if (d.length === 12 && d.startsWith('998')) out.add(d.slice(3));
  if (d.length === 9) out.add(`998${d}`);
  return Array.from(out);
}

const userCache = new Map();

async function geoOfOwner(ownerId) {
  for (const id of ownerAliases(ownerId)) {
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
    const d = snap.data() || {};
    const geo = {
      districtId: String(d.districtId || '').trim(),
      regionId: String(d.regionId || '').trim(),
    };
    userCache.set(id, geo.districtId ? geo : null);
    if (geo.districtId) return geo;
  }
  return null;
}

async function main() {
  const snap = await db.collection('yuk_local_drivers').get();
  console.log(`Jami e'lon: ${snap.size}`);

  let skipped = 0;
  let noOwnerGeo = 0;
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
    const geo = await geoOfOwner(d.ownerId);
    if (!geo) {
      noOwnerGeo++;
      console.warn(`  hudud topilmadi: ${doc.id} (ownerId=${d.ownerId})`);
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
  console.log(`  ega hududi yo'q    : ${noOwnerGeo}`);
  console.log(DRY ? `  yozilardi          : ${planned}` : `  yozildi            : ${written}`);
  if (DRY) console.log('\n(--dry: hech narsa yozilmadi)');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
