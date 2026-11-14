/**
 * `ads` — eski e'lonlarga `districtId` / `regionId` yozadi.
 *
 * Qamrov: `cheap_product` (Aholi bozori) va jobs board (`work` /
 * `service` / `ad`). Hudud e'lon egasining `users/{...}` hujjatidan
 * olinadi — ega tanlagan variant: "(a) эга телефони орқали
 * users.districtId дан".
 *
 * Egalik maydoni ikki xil: bozorda `ownerId`, jobs board'da
 * `authorPhone`.
 *
 * Nega kerak: bosh sahifadagi 2 (e'lonlar), 3 (xizmat takliflari) va
 * 6 (Aholi bozori) bo'limlari ro'yxatni `districtId` bo'yicha server
 * tomonda filtrlaydi. Maydonsiz eski yozuvlar vaqtincha barcha tumanda
 * ko'rinadi; shu skript ishlagach ular o'z tumaniga biriktiriladi.
 *
 * Yangi e'lonlarga hudud `submitJobAd` / `submitMarketAd` ichida
 * (ownerGeoStamp) allaqachon yoziladi — skript faqat ESKI yozuvlar
 * uchun.
 *
 * Idempotent: `districtId` allaqachon bor hujjat tegilmaydi.
 *
 *   node functions/tools/backfill_ads_district.js --dry
 *   node functions/tools/backfill_ads_district.js
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

const JOBS_TYPES = ['work', 'service', 'ad'];

function phoneDigits(raw) {
  return String(raw || '').replace(/\D/g, '');
}

function ownerAliases(raw) {
  const d = phoneDigits(raw);
  if (d.length < 9) return [];
  const out = new Set([d]);
  if (d.length === 12 && d.startsWith('998')) out.add(d.slice(3));
  if (d.length === 9) out.add(`998${d}`);
  return Array.from(out);
}

const userCache = new Map();

async function geoOfOwner(raw) {
  for (const id of ownerAliases(raw)) {
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
  return null;
}

async function main() {
  const snap = await db.collection('ads').get();
  console.log(`Jami 'ads' hujjati: ${snap.size}`);

  const stats = {
    skippedHasGeo: 0,
    skippedOtherType: 0,
    noOwnerGeo: 0,
    planned: 0,
    written: 0,
  };

  let batch = db.batch();
  let inBatch = 0;

  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const type = String(d.type || '');
    const isMarket = type === 'cheap_product';
    const isJobs = JOBS_TYPES.includes(type);
    if (!isMarket && !isJobs) {
      stats.skippedOtherType++;
      continue;
    }
    if (String(d.districtId || '').trim()) {
      stats.skippedHasGeo++;
      continue;
    }

    const owner = isMarket ? d.ownerId : d.authorPhone;
    const geo = await geoOfOwner(owner);
    if (!geo) {
      stats.noOwnerGeo++;
      console.warn(`  hudud topilmadi: ${doc.id} (${type}, owner=${owner})`);
      continue;
    }

    stats.planned++;
    if (DRY) continue;

    const patch = { districtId: geo.districtId };
    if (geo.regionId) patch.regionId = geo.regionId;
    batch.set(doc.ref, patch, { merge: true });
    inBatch++;
    if (inBatch >= 400) {
      await batch.commit();
      stats.written += inBatch;
      batch = db.batch();
      inBatch = 0;
    }
  }

  if (!DRY && inBatch > 0) {
    await batch.commit();
    stats.written += inBatch;
  }

  console.log('');
  console.log(`  boshqa tur (tegilmadi) : ${stats.skippedOtherType}`);
  console.log(`  allaqachon hududli     : ${stats.skippedHasGeo}`);
  console.log(`  ega hududi yo'q        : ${stats.noOwnerGeo}`);
  console.log(
    DRY
      ? `  yozilardi              : ${stats.planned}`
      : `  yozildi                : ${stats.written}`,
  );
  if (DRY) console.log('\n(--dry: hech narsa yozilmadi)');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
