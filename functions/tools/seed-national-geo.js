#!/usr/bin/env node
/**
 * Respublika bo'yicha geo-infratuzilma: barcha 14 viloyat/shahar + tumanlar.
 *
 * XAVFSIZ: faqat `set(..., { merge: true })` — mavjud hujjatlarni buzmaydi.
 * Faqat `geo_regions`/`geo_districts` yozadi. `config/module_defaults`,
 * `geo_district_modules`, `service_areas` — TEGILMAYDI (modul-gating —
 * alohida, ehtiyotkor qaror; hozircha yangi tumanlarda hech qanday modul
 * override yo'q, ular global `config/module_defaults`dan meros oladi).
 *
 * Ishlatish:
 *   node functions/tools/seed-national-geo.js --dry   (faqat ko'rsatadi)
 *   node functions/tools/seed-national-geo.js         (yozadi)
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { REGIONS, DISTRICTS_BY_REGION } = require('./data/uzbekistan_geo_data');

const DRY = process.argv.includes('--dry');
const keyPath = path.join(__dirname, '..', 'service-account.json');

if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

const serviceAccount = require(keyPath);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();
db.settings({ preferRest: true });
const now = admin.firestore.FieldValue.serverTimestamp();
const BY = 'seed-national-geo';

async function run() {
  const plan = [];

  for (const r of REGIONS) {
    const { id, ...data } = r;
    plan.push(['geo_regions/' + id, { ...data, active: true, updatedAt: now, updatedBy: BY }]);
  }

  for (const [regionId, districts] of Object.entries(DISTRICTS_BY_REGION)) {
    districts.forEach((d, i) => {
      plan.push([
        'geo_districts/' + d.id,
        {
          regionId,
          name: d.name,
          nameUz: d.nameUz,
          code: d.id,
          active: true,
          order: (i + 1) * 10,
          updatedAt: now,
          updatedBy: BY,
        },
      ]);
    });
  }

  console.log(`Seed reja: ${plan.length} ta hujjat (merge)${DRY ? ' — DRY RUN' : ''}`);
  console.log(`  Viloyat/shahar: ${REGIONS.length} ta`);
  console.log(`  Tuman/shahar: ${plan.length - REGIONS.length} ta`);

  if (DRY) {
    for (const [pathStr] of plan) console.log('  •', pathStr);
    console.log('DRY: hech narsa yozilmadi.');
    return;
  }

  for (const [pathStr, data] of plan) {
    await db.doc(pathStr).set(data, { merge: true });
  }
  console.log('✅ Seed yozildi:', plan.length, 'ta hujjat.');
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Seed xato:', e.message || e);
    process.exit(1);
  });
